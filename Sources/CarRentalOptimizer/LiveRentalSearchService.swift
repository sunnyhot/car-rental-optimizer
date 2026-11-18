import CarRentalDomain
import Foundation
import WebKit

protocol RentalSearchProviding {
    func search(request: SearchRequest) async -> [PlatformEvidenceResult]
}

let livePlatformQueryTimeoutSeconds: TimeInterval = 35
let liveZucheQueryTimeoutSeconds: TimeInterval = 60

@MainActor
func platformResultWithTimeout(
    platform: PlatformId,
    timeoutSeconds: TimeInterval = livePlatformQueryTimeoutSeconds,
    onTimeout: @escaping @MainActor () -> Void = {},
    operation: @escaping @MainActor () async -> PlatformEvidenceResult
) async -> PlatformEvidenceResult {
    let operationTask = Task { @MainActor in
        await operation()
    }
    let timeoutTask = Task {
        let nanoseconds = timeoutNanoseconds(for: timeoutSeconds)
        if nanoseconds > 0 {
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
        return platformTimeoutResult(platform: platform, timeoutSeconds: timeoutSeconds)
    }

    return await withCheckedContinuation { continuation in
        var didResume = false

        let finishWithOperation: @MainActor (PlatformEvidenceResult) -> Void = { result in
            guard !didResume else { return }
            didResume = true
            timeoutTask.cancel()
            continuation.resume(returning: result)
        }

        let finishWithTimeout: @MainActor (PlatformEvidenceResult) -> Void = { result in
            guard !didResume else { return }
            didResume = true
            operationTask.cancel()
            onTimeout()
            continuation.resume(returning: result)
        }

        Task { @MainActor in
            finishWithOperation(await operationTask.value)
        }
        Task { @MainActor in
            finishWithTimeout(await timeoutTask.value)
        }
    }
}

private func timeoutNanoseconds(for timeoutSeconds: TimeInterval) -> UInt64 {
    let clampedSeconds = min(max(timeoutSeconds, 0), 3_600)
    return UInt64(clampedSeconds * 1_000_000_000)
}

private func platformTimeoutResult(platform: PlatformId, timeoutSeconds: TimeInterval) -> PlatformEvidenceResult {
    let seconds = max(1, Int(ceil(timeoutSeconds)))
    return PlatformEvidenceResult(
        platform: platform,
        status: PlatformEvidenceStatus(
            platform: platform,
            kind: .parseFailed,
            message: "\(platform.label) API 查询超时（超过 \(seconds) 秒），已停止等待，请稍后重试。",
            sourceUrl: officialPlatformURL(for: platform)
        ),
        listings: []
    )
}

@MainActor
final class LiveRentalSearchService: NSObject, RentalSearchProviding {
    private let zucheClient = ZucheAPIClient()
    private let ehiClient = EhiBridgeClient()

    func search(request: SearchRequest) async -> [PlatformEvidenceResult] {
        traceLiveSearch("origin=\(request.origin) dates=\(request.pickupAt)..\(request.returnAt) radius=\(request.radiusKm)")
        if let issue = validateSearchPreflight(request).issues.first(where: { $0.severity == .blocking }) {
            return request.platforms.map { platform in
                PlatformEvidenceResult(platform: platform, status: PlatformEvidenceStatus(platform: platform, kind: .unavailable, message: issue.message, sourceUrl: officialPlatformURL(for: platform)), listings: [])
            }
        }
        var results: [PlatformEvidenceResult] = []

        if request.platforms.contains(.carInc) {
            results.append(await platformResultWithTimeout(
                platform: .carInc,
                timeoutSeconds: liveZucheQueryTimeoutSeconds
            ) {
                await self.zucheClient.search(request: request)
            })
        }

        if request.platforms.contains(.ehi) {
            results.append(await ehiClient.search(request: request))
        }

        return request.platforms.compactMap { platform in
            results.first { $0.platform == platform }
        }
    }
}

struct SnapshotRentalSearchService: RentalSearchProviding {
    let snapshotProvider: PlatformSnapshotProviding

    func search(request: SearchRequest) async -> [PlatformEvidenceResult] {
        var results: [PlatformEvidenceResult] = []
        for platform in request.platforms {
            do {
                let snapshot = try await snapshotProvider.snapshot(for: platform)
                results.append(parsePlatformEvidence(
                    input: PlatformEvidenceInput(
                        platform: platform,
                        text: snapshot.text,
                        sourceUrl: snapshot.url
                    ),
                    request: request
                ))
            } catch {
                results.append(PlatformEvidenceResult(
                    platform: platform,
                    status: PlatformEvidenceStatus(
                        platform: platform,
                        kind: .parseFailed,
                        message: "\(platform.label)页面读取失败：\(error.localizedDescription)",
                        sourceUrl: officialPlatformURL(for: platform)
                    ),
                    listings: []
                ))
            }
        }
        return results
    }
}

struct StoreListingsBatch {
    let distanceKm: Double
    let listings: [RentalListing]
}

private struct ZucheListingCandidate {
    let listing: RentalListing
    let confirmationContext: ZucheConfirmationContext
}

private struct ZucheConfirmationContext: Hashable {
    let modelId: Int
    let pickupCityId: String
    let returnCityId: String
    let pickupDeptId: Int
    let returnDeptId: Int
    let pickupTime: String
    let returnTime: String
    let entrance: Int
    let priceType: Int
    let prepaidFlag: Bool
    let pickUpWebsite: Int?
    let pickUpAppropriate: Int?
    let allianceBusinessFlag: Bool

    var payload: [String: Any] {
        var baseInfo: [String: Any] = [
            "pickupWay": 0,
            "returnWay": 0,
            "modelId": modelId,
            "prepaidFlag": prepaidFlag,
            "priceType": priceType,
            "allianceBusinessFlag": allianceBusinessFlag,
            "estimatedPickupTime": pickupTime,
            "estimatedReturnTime": returnTime,
            "entrance": entrance,
            "enterpriseUseCarType": entrance == 5 ? 2 : 1,
            "pickupDeptId": pickupDeptId,
            "returnDeptId": returnDeptId,
            "pickupCityId": pickupCityId,
            "returnCityId": returnCityId
        ]
        if let pickUpWebsite {
            baseInfo["pickUpWebsite"] = pickUpWebsite
        }
        if let pickUpAppropriate {
            baseInfo["pickUpAppropriate"] = pickUpAppropriate
        }
        return ["baseInfo": baseInfo]
    }
}

private struct ZucheFeeEnrichment {
    let listings: [RentalListing]
    let attemptedWithCookies: Bool
    let confirmedFeeCount: Int
    let loginRejected: Bool
    var confirmedTotalCount: Int = 0
}

let maxZucheVehicleSearchCityCount = 60
private let maxConcurrentZucheConfirmationRequests = 1
private let zucheGatewayRequestTimeoutSeconds: TimeInterval = 10

func zucheCityQueryConcurrency(for cityCount: Int) -> Int {
    guard cityCount > 0 else { return 0 }

    let limit: Int
    switch cityCount {
    case ...12:
        limit = 3
    case ...30:
        limit = 4
    case ...48:
        limit = 6
    default:
        limit = 8
    }
    return min(cityCount, limit)
}

struct ZucheGatewayEndpoint: Equatable {
    let url: URL
    let referer: String
}

func zucheGatewayEndpoints(for uri: String) -> [ZucheGatewayEndpoint] {
    let normalizedURI = uri.hasPrefix("/") ? uri : "/\(uri)"
    return [
        ZucheGatewayEndpoint(
            url: URL(string: "https://m.zuche.com/api/gw.do?uri=\(normalizedURI)")!,
            referer: "https://m.zuche.com/"
        ),
        ZucheGatewayEndpoint(
            url: URL(string: "https://www.zuche.com/api/gw.do?uri=\(normalizedURI)")!,
            referer: "https://www.zuche.com/"
        )
    ]
}

func isRetryableZucheTransportError(_ error: Error) -> Bool {
    guard let urlError = error as? URLError else { return false }
    switch urlError.code {
    case .secureConnectionFailed,
         .timedOut,
         .networkConnectionLost,
         .cannotFindHost,
         .cannotConnectToHost,
         .dnsLookupFailed:
        return true
    default:
        return false
    }
}

struct ZucheSearchCity: Equatable {
    let id: String
    let name: String
    let location: GeoPoint?
}

struct ZucheCandidateCity: Equatable {
    let city: ZucheSearchCity
    let distanceKm: Double
    let isCurrentCity: Bool
}

func zucheCandidateCities(from cities: [ZucheSearchCity], request: SearchRequest) -> [ZucheCandidateCity] {
    guard !cities.isEmpty else { return [] }
    let currentCityID = currentZucheCityID(from: cities, request: request)

    return cities.compactMap { city -> ZucheCandidateCity? in
        let distanceKm = city.location.map { distanceKmBetween(from: request.origin, to: $0) }
        let isCurrentCity = city.id == currentCityID
        guard isCurrentCity || (distanceKm.map { $0 <= request.radiusKm } ?? false) else {
            return nil
        }
        return ZucheCandidateCity(
            city: city,
            distanceKm: distanceKm ?? 0,
            isCurrentCity: isCurrentCity
        )
    }
    .sorted {
        if $0.isCurrentCity != $1.isCurrentCity {
            return $0.isCurrentCity
        }
        if $0.distanceKm != $1.distanceKm {
            return $0.distanceKm < $1.distanceKm
        }
        return $0.city.name.localizedStandardCompare($1.city.name) == .orderedAscending
    }
}

func plannedZucheCities(
    from candidateCities: [ZucheCandidateCity],
    hasVehicleQuery: Bool,
    maxVehicleCityCount: Int = maxZucheVehicleSearchCityCount
) -> [ZucheCandidateCity] {
    guard hasVehicleQuery else {
        return Array(candidateCities.prefix(1))
    }

    let cityLimit = max(1, maxVehicleCityCount)
    return Array(candidateCities.prefix(cityLimit))
}

func zucheListingsMatchingVehicleQuery(_ listings: [RentalListing], vehicleQuery: String) -> [RentalListing] {
    let query = vehicleQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return listings }

    let isSpecificVehicleQuery = isSpecificVehicleModelQuery(query)
    return listings.filter { listing in
        let match = matchVehicle(
            query: query,
            vehicleName: listing.vehicleName,
            vehicleClass: listing.vehicleClass
        )
        return isSpecificVehicleQuery ? match.kind == .exact : match.kind != .lowConfidence
    }
}

func zucheSelectedStore(from stores: [Store], cityName: String, isCurrentCity: Bool) -> Store? {
    let sortedStores = stores.sorted {
        if $0.distanceKm != $1.distanceKm {
            return $0.distanceKm < $1.distanceKm
        }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
    if isCurrentCity {
        return sortedStores.first
    }
    return sortedStores.first { isZucheRailwayStationStore($0, cityName: cityName) }
}

func zucheAcceptsQuotedStore(_ store: Store, queryStore: Store, isCurrentCity: Bool, radiusKm: Double) -> Bool {
    guard store.distanceKm <= radiusKm else { return false }
    // The requested coordinates are only a search center. The server may return
    // other bookable nearby stores when that center has no stock.
    return isCurrentCity || isZucheRailwayStationStore(store, cityName: queryStore.city)
}

private func currentZucheCityID(from cities: [ZucheSearchCity], request: SearchRequest) -> String? {
    if let exact = cities.first(where: { zucheCityNameMatchesOrigin($0.name, request: request) }) {
        return exact.id
    }
    return cities
        .compactMap { city -> (String, Double)? in
            guard let location = city.location else { return nil }
            return (city.id, distanceKmBetween(from: request.origin, to: location))
        }
        .min { $0.1 < $1.1 }?
        .0
}

private func zucheCityNameMatchesOrigin(_ cityName: String, request: SearchRequest) -> Bool {
    let label = localizedChineseLocationText(request.originLabel)
    let aliases = originCityCandidates(from: request.originLabel)
    let normalizedCityName = normalizedZucheCityName(cityName)
    guard !normalizedCityName.isEmpty else { return false }

    return label.contains(cityName)
        || label.contains(normalizedCityName)
        || aliases.contains(cityName)
        || aliases.contains(normalizedCityName)
}

private func isZucheRailwayStationStore(_ store: Store, cityName: String) -> Bool {
    let text = "\(store.name) \(store.address)"
    if text.contains("机场") {
        return false
    }
    if ["火车站", "高铁站", "高铁", "动车站", "铁路"].contains(where: { text.contains($0) }) {
        return true
    }

    let normalizedCityName = normalizedZucheCityName(cityName)
    guard !normalizedCityName.isEmpty else { return false }
    let stationTokens = [
        "\(normalizedCityName)站",
        "\(normalizedCityName)东站",
        "\(normalizedCityName)西站",
        "\(normalizedCityName)南站",
        "\(normalizedCityName)北站"
    ]
    if stationTokens.contains(where: { text.contains($0) }) {
        return true
    }
    return false
}

private func normalizedZucheCityName(_ cityName: String) -> String {
    localizedChineseLocationText(cityName)
        .replacingOccurrences(of: "市", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func nearestPricedStoreBatch(_ batches: [StoreListingsBatch]) -> StoreListingsBatch? {
    batches.filter { !$0.listings.isEmpty }.min { $0.distanceKm < $1.distanceKm }
}

func blankVehicleCandidateListings(
    from batches: [StoreListingsBatch],
    minimumVehicleCount: Int = 12,
    maxStoreCount: Int = 6
) -> [RentalListing] {
    _ = minimumVehicleCount
    _ = maxStoreCount
    guard let nearestPricedStore = nearestPricedStoreBatch(batches) else {
        return []
    }

    var listingsByVehicle: [String: RentalListing] = [:]

    for listing in nearestPricedStore.listings {
        let key = normalizedVehicleKey(listing.vehicleName)
        if let existing = listingsByVehicle[key], !isBetterBlankVehicleListing(listing, than: existing) {
            continue
        }
        listingsByVehicle[key] = listing
    }

    return listingsByVehicle.values.sorted {
        if $0.basePrice != $1.basePrice {
            return $0.basePrice < $1.basePrice
        }
        if $0.store.distanceKm != $1.store.distanceKm {
            return $0.store.distanceKm < $1.store.distanceKm
        }
        return $0.vehicleName.localizedStandardCompare($1.vehicleName) == .orderedAscending
    }
}

private func normalizedVehicleKey(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func isBetterBlankVehicleListing(_ candidate: RentalListing, than current: RentalListing) -> Bool {
    if candidate.basePrice != current.basePrice {
        return candidate.basePrice < current.basePrice
    }
    return candidate.store.distanceKm < current.store.distanceKm
}

// MARK: - Zuche

final class ZucheAPIClient {
    private let session: URLSession
    private let cookieAccess: ZucheSessionCookieAccess?

    init(session: URLSession? = nil, cookieAccess: ZucheSessionCookieAccess? = nil) {
        self.session = session ?? URLSession(configuration: .ephemeral, delegate: ZucheSessionRedirectPolicy(), delegateQueue: nil)
        self.cookieAccess = cookieAccess
    }

    func search(request: SearchRequest) async -> PlatformEvidenceResult {
        do {
            let cities: ZucheCityListContent = try await postGateway(uri: "/action/carrctapi/order/cityList/v1", payload: [:])
            let candidateCities = zucheCandidateCities(
                from: cities.allCities.map(\.searchCity),
                request: request
            )
            guard !candidateCities.isEmpty else {
                return status(.unavailable, "神州没有识别到当前位置对应的可租城市。")
            }

            let timeRange = platformQueryTimeRange(pickupDate: request.pickupAt, returnDate: request.returnAt)
            let hasVehicleQuery = !request.vehicleQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let plannedCities = plannedZucheCities(from: candidateCities, hasVehicleQuery: hasVehicleQuery)
            let cityQueryConcurrency = zucheCityQueryConcurrency(for: plannedCities.count)
            let requestThrottle = ZucheRequestThrottle(minimumInterval: 0.12)
            let isCityPlanLimited = hasVehicleQuery && plannedCities.count < candidateCities.count
            var citiesByID: [String: ZucheCity] = [:]
            for city in cities.allCities {
                citiesByID[city.cityId] = city
            }
            var listingsByKey: [String: RentalListing] = [:]
            var nearestStoreBatches: [StoreListingsBatch] = []
            var confirmationContextsByListingID: [String: ZucheConfirmationContext] = [:]
            var queryErrors: [String] = []

            // Query each planned city concurrently. City planning stays breadth-
            // limited by maxZucheVehicleSearchCityCount; within that bound every
            // city is fetched in parallel (capped by the dynamic concurrency tier)
            // so a 500km radius no longer times out on the nearest handful only.
            await withTaskGroup(of: ZucheCityQueryResult?.self) { group in
                func addNextCity(at index: Int) {
                    guard index < plannedCities.count else { return }
                    let candidate = plannedCities[index]
                    guard let city = citiesByID[candidate.city.id] else {
                        addNextCity(at: index + 1)
                        return
                    }
                    group.addTask { [weak self] in
                        guard let self else { return nil }
                        return await self.zucheCityQueryResult(
                            city: city,
                            candidate: candidate,
                            request: request,
                            timeRange: timeRange,
                            hasVehicleQuery: hasVehicleQuery,
                            throttle: requestThrottle
                        )
                    }
                }

                var nextIndex = 0
                for _ in 0..<cityQueryConcurrency {
                    addNextCity(at: nextIndex)
                    nextIndex += 1
                }

                while let result = await group.next() {
                    if let result {
                        queryErrors.append(contentsOf: result.errors)
                        if let batch = result.nearestStoreBatch {
                            nearestStoreBatches.append(batch)
                        }
                        for (id, context) in result.confirmationContexts {
                            confirmationContextsByListingID[id] = context
                        }
                        for (key, listing) in result.listingsByKey {
                            if let old = listingsByKey[key], old.basePrice <= listing.basePrice {
                                continue
                            }
                            listingsByKey[key] = listing
                        }
                    }
                    if nextIndex < plannedCities.count {
                        addNextCity(at: nextIndex)
                        nextIndex += 1
                    }
                }
            }

            let queryListings = hasVehicleQuery
                ? Array(listingsByKey.values)
                : blankVehicleCandidateListings(from: nearestStoreBatches)
            let rawListings = zucheListingsMatchingVehicleQuery(queryListings, vehicleQuery: request.vehicleQuery)
            guard !rawListings.isEmpty else {
                if !queryErrors.isEmpty {
                    return status(.parseFailed, "神州 API 部分查询失败：\(queryErrors.prefix(2).joined(separator: "；"))")
                }
                if isCityPlanLimited {
                    return status(.unavailable, "神州真实接口返回成功，但半径内候选城市超过 \(plannedCities.count) 个，为避免超时只扫描了最近的 \(plannedCities.count) 个，没有找到匹配车型。请缩小半径或更换取车地后重试。")
                }
                return status(.unavailable, "神州真实接口返回成功，但当前条件没有可订车型。")
            }

            let feeEnrichment = await enrichListingsWithConfirmationFees(
                rawListings,
                contextsByListingID: confirmationContextsByListingID
            )

            return PlatformEvidenceResult(
                platform: .carInc,
                status: PlatformEvidenceStatus(
                    platform: .carInc,
                    kind: .ready,
                    message: zucheStatusMessage(listingCount: feeEnrichment.listings.count, feeEnrichment: feeEnrichment),
                    sourceUrl: "https://www.zuche.com/"
                ),
                listings: feeEnrichment.listings
            )
        } catch {
            return status(.parseFailed, "神州 API 查询失败：\(error.localizedDescription)")
        }
    }

    /// Aggregated results from querying a single city's deptList + chooseCar,
    /// merged back into the caller's accumulators after the concurrent task group
    /// collects it. Keeping these as one value lets the parallel loop stay lock-free
    /// (each task produces an isolated result; the loop merges sequentially).
    private struct ZucheCityQueryResult {
        var listingsByKey: [String: RentalListing]
        var nearestStoreBatch: StoreListingsBatch?
        var confirmationContexts: [String: ZucheConfirmationContext]
        var errors: [String]
    }

    /// Query one city end to end: deptList (store list) → select station store →
    /// chooseCar (vehicles + prices). Returns nil only when the city id cannot be
    /// resolved (already filtered upstream). All per-city logic — radius filtering,
    /// station-store selection, store+vehicle dedup — is unchanged from the prior
    /// serial loop; this method just isolates one city's work for concurrency.
    private func zucheCityQueryResult(
        city: ZucheCity,
        candidate: ZucheCandidateCity,
        request: SearchRequest,
        timeRange: PlatformQueryTimeRange,
        hasVehicleQuery: Bool,
        throttle: ZucheRequestThrottle
    ) async -> ZucheCityQueryResult {
        var listingsByKey: [String: RentalListing] = [:]
        var nearestStoreBatch: StoreListingsBatch?
        var confirmationContexts: [String: ZucheConfirmationContext] = [:]
        var errors: [String] = []

        let deptList: ZucheDeptListContent
        do {
            deptList = try await postCityGateway(
                uri: "/action/carrctapi/order/deptList/v1",
                payload: ["cityId": city.cityId, "entrance": 1, "pickupFlag": 1],
                throttle: throttle
            )
        } catch {
            errors.append("\(city.cityName)：\(error.localizedDescription)")
            return ZucheCityQueryResult(
                listingsByKey: listingsByKey,
                nearestStoreBatch: nearestStoreBatch,
                confirmationContexts: confirmationContexts,
                errors: errors
            )
        }

        let stores = flattenDepartments(deptList)
            .compactMap { makeStore(from: $0, cityName: city.cityName, request: request) }
            .filter { $0.distanceKm <= request.radiusKm }
        guard let selectedStore = zucheSelectedStore(
            from: stores,
            cityName: city.cityName,
            isCurrentCity: candidate.isCurrentCity
        ) else {
            return ZucheCityQueryResult(
                listingsByKey: listingsByKey,
                nearestStoreBatch: nearestStoreBatch,
                confirmationContexts: confirmationContexts,
                errors: errors
            )
        }

        traceLiveSearch("city=\(city.cityName) stores=\(stores.count) selected=\(selectedStore.id) \(selectedStore.name)")
        let chooseCar: ZucheChooseCarContent
        do {
            chooseCar = try await postCityGateway(
                uri: "/resource/carrctapi/order/chooseCar/v3",
                payload: [
                    "pickupCityId": city.cityId,
                    "pickupTime": timeRange.pickupTime,
                    "returnCityId": city.cityId,
                    "returnTime": timeRange.returnTime,
                    "entrance": 1,
                    "userChooseLat": String(selectedStore.location.lat),
                    "userChooseLon": String(selectedStore.location.lng),
                    "holidaysWaitingFlag": 0,
                ],
                throttle: throttle
            )
        } catch {
            errors.append("\(city.cityName)：\(error.localizedDescription)")
            return ZucheCityQueryResult(
                listingsByKey: listingsByKey,
                nearestStoreBatch: nearestStoreBatch,
                confirmationContexts: confirmationContexts,
                errors: errors
            )
        }

        traceLiveSearch("returned stores=\(chooseCar.deptHangModels.map { ($0.deptId, $0.models.count) })")
        for dept in chooseCar.deptHangModels {
            guard let store = makeStore(from: dept, cityName: city.cityName, request: request) else { continue }
            guard zucheAcceptsQuotedStore(store, queryStore: selectedStore, isCurrentCity: candidate.isCurrentCity, radiusKm: request.radiusKm) else { continue }

            let deptListings = listings(from: dept.models, city: city, dept: dept, store: store, request: request, timeRange: timeRange)
            for priced in deptListings {
                confirmationContexts[priced.listing.id] = priced.confirmationContext
            }
            let listings = deptListings.map(\.listing)
            if !hasVehicleQuery {
                let batch = StoreListingsBatch(distanceKm: store.distanceKm, listings: listings)
                nearestStoreBatch = nearestPricedStoreBatch([nearestStoreBatch, batch].compactMap { $0 })
                continue
            }

            for listing in listings {
                let key = "\(store.id)-\(listing.vehicleName)"
                if let old = listingsByKey[key], old.basePrice <= listing.basePrice {
                    continue
                }
                listingsByKey[key] = listing
            }
        }

        return ZucheCityQueryResult(
            listingsByKey: listingsByKey,
            nearestStoreBatch: nearestStoreBatch,
            confirmationContexts: confirmationContexts,
            errors: errors
        )
    }

    private func postCityGateway<Response: Decodable>(
        uri: String,
        payload: [String: Any],
        throttle: ZucheRequestThrottle
    ) async throws -> Response {
        try await withZucheRateLimitRetry(throttle: throttle) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.postGateway(uri: uri, payload: payload)
        }
    }

    private func postGateway<Response: Decodable>(uri: String, payload: [String: Any]) async throws -> Response {
        let envelope: ZucheResponse<Response> = try await postGatewayForm(uri: uri, payload: payload)
        guard envelope.code == 1 || envelope.status == "SUCCESS", let content = envelope.content else {
            let message = envelope.msg ?? "神州接口返回异常"
            if isZucheRateLimitMessage(message) {
                throw ZucheRateLimitError(message: message)
            }
            throw PlatformAPIError.message(message)
        }
        return content
    }

    func postGatewayForm<Response: Decodable>(
        uri: String,
        payload: [String: Any],
        cookieHeader: String? = nil
    ) async throws -> ZucheResponse<Response> {
        var transportErrors: [String] = []
        var lastLoginFailure: ZucheResponse<Response>?
        for endpoint in zucheGatewayEndpoints(for: uri) {
            do {
                let envelope: ZucheResponse<Response> = try await postForm(
                    url: endpoint.url,
                    payload: payload,
                    referer: endpoint.referer,
                    cookieHeader: cookieHeader
                )
                if cookieHeader != nil && (envelope.code == 5 || envelope.status == "NOT_LOGIN") {
                    lastLoginFailure = envelope
                    continue // Desktop and H5 can use different scoped sessions.
                }
                return envelope
            } catch let error as PlatformAPIError {
                if cookieHeader != nil, case .loginRequired = error {
                    lastLoginFailure = ZucheResponse(code: 5, status: "NOT_LOGIN", msg: "登录未通过", content: nil)
                    continue
                }
                throw error
            } catch {
                guard isRetryableZucheTransportError(error) else {
                    throw error
                }
                let host = endpoint.url.host() ?? endpoint.url.host ?? endpoint.url.absoluteString
                transportErrors.append("\(host)：\(error.localizedDescription)")
            }
        }

        if transportErrors.isEmpty, let lastLoginFailure { return lastLoginFailure }
        throw PlatformAPIError.message("神州 API 网络连接失败：\(transportErrors.joined(separator: "；"))")
    }

    private func postForm<Response: Decodable>(
        url: URL,
        payload: [String: Any],
        referer: String,
        cookieHeader: String? = nil
    ) async throws -> ZucheResponse<Response> {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let json = String(data: data, encoding: .utf8) ?? "{}"
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "data", value: json)]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.timeoutInterval = zucheGatewayRequestTimeoutSeconds
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
        if cookieHeader != nil {
            let scopedHeader: String?
            if let cookieAccess { scopedHeader = await cookieAccess.header(url) }
            else { scopedHeader = await zucheCookieHeader(for: url) }
            if let scopedHeader { request.setValue(scopedHeader, forHTTPHeaderField: "Cookie") }
        }

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PlatformAPIError.message("神州接口没有返回有效 HTTP 响应")
        }
        if http.statusCode == 401 && cookieHeader != nil { throw PlatformAPIError.loginRequired }
        guard 200..<300 ~= http.statusCode else { throw PlatformAPIError.message("HTTP \(http.statusCode)") }
        // The official web client also treats content.status == -910 as expired authentication,
        // even when the envelope itself reports code 1.
        let sessionMetadata = try JSONDecoder().decode(ZucheSessionResponseMetadata.self, from: responseData)
        if sessionMetadata.contentStatus == -910 {
            throw PlatformAPIError.loginRequired
        }
        // A rejected gateway can issue a new anonymous session. Do not let it
        // overwrite the session used by the next official gateway or login page.
        if cookieHeader != nil, canAdoptZucheSessionCookies(httpStatus: http.statusCode, code: sessionMetadata.code, status: sessionMetadata.status) {
            let fields = http.allHeaderFields.reduce(into: [String: String]()) { result, entry in
                result[String(describing: entry.key)] = String(describing: entry.value)
            }
            let responseURL = http.url ?? url
            let updates = HTTPCookie.cookies(withResponseHeaderFields: fields, for: responseURL)
            if let cookieAccess { await cookieAccess.accept(updates, responseURL) }
            else { await PlatformSessionPersistence.shared.applyAuthenticatedResponseCookies(updates, for: responseURL) }
        }
        return try JSONDecoder().decode(ZucheResponse<Response>.self, from: responseData)
    }

    private func flattenDepartments(_ content: ZucheDeptListContent) -> [ZucheDept] {
        content.districtList.flatMap(\.deptList).filter { $0.inventoryAbleFlag != false }
    }

    private func listings(
        from models: [ZucheModel],
        city: ZucheCity,
        dept: ZucheDeptModels,
        store: Store,
        request: SearchRequest,
        timeRange: PlatformQueryTimeRange
    ) -> [ZucheListingCandidate] {
        models.compactMap { model in
            guard model.bookFlag != false && model.havePriceFlag != false,
                  let dailyPrice = model.price
            else { return nil }

            let listing = RentalListing(
                id: "car-inc-\(store.id)-\(model.modelId)",
                platform: .carInc,
                store: store,
                vehicleName: model.modelName,
                vehicleClass: model.modelDesc,
                basePrice: dailyPrice * Double(rentalDays(request)),
                platformFees: 0,
                insuranceFees: 0,
                oneWayFee: 0,
                sourceUrl: "https://www.zuche.com/#/rent/list",
                dataCompleteness: 0.72,
                warnings: [.partialPrice, .loginRequired]
            )

            return ZucheListingCandidate(
                listing: listing,
                confirmationContext: ZucheConfirmationContext(
                    modelId: model.modelId,
                    pickupCityId: city.cityId,
                    returnCityId: city.cityId,
                    pickupDeptId: dept.deptId,
                    returnDeptId: dept.deptId,
                    pickupTime: timeRange.pickupTime,
                    returnTime: timeRange.returnTime,
                    entrance: 1,
                    priceType: 1,
                    prepaidFlag: false,
                    pickUpWebsite: dept.pickupWebsite,
                    pickUpAppropriate: dept.pickupAppropriate,
                    allianceBusinessFlag: dept.chainFlag ?? false
                )
            )
        }
    }

    private func enrichListingsWithConfirmationFees(
        _ listings: [RentalListing],
        contextsByListingID: [String: ZucheConfirmationContext]
    ) async -> ZucheFeeEnrichment {
        guard let cookieHeader = await zucheCookieHeader() else {
            return ZucheFeeEnrichment(
                listings: listings,
                attemptedWithCookies: false,
                confirmedFeeCount: 0,
                loginRejected: false
            )
        }

        let confirmationInputs = listings.compactMap { listing -> (String, ZucheConfirmationContext)? in
            guard let context = contextsByListingID[listing.id] else { return nil }
            return (listing.id, context)
        }
        guard !confirmationInputs.isEmpty else {
            return ZucheFeeEnrichment(
                listings: listings,
                attemptedWithCookies: true,
                confirmedFeeCount: 0,
                loginRejected: false
            )
        }

        var confirmationsByListingID: [String: ZucheConfirmOrderContent] = [:]
        var loginRejected = false
        var nextIndex = 0

        await withTaskGroup(of: (String, Result<ZucheConfirmOrderContent, PlatformAPIError>).self) { group in
            func addNext() {
                guard nextIndex < confirmationInputs.count else { return }
                let input = confirmationInputs[nextIndex]
                nextIndex += 1
                group.addTask { [weak self] in
                    guard let self else { return (input.0, .failure(.message("核价已取消"))) }
                    do {
                        let content = try await self.confirmationQuoteContent(
                            context: input.1,
                            cookieHeader: cookieHeader
                        )
                        return (input.0, .success(content))
                    } catch let error as PlatformAPIError {
                        return (input.0, .failure(error))
                    } catch {
                        return (input.0, .failure(.message(error.localizedDescription)))
                    }
                }
            }

            for _ in 0..<min(maxConcurrentZucheConfirmationRequests, confirmationInputs.count) {
                addNext()
            }

            while let (listingID, result) = await group.next() {
                switch result {
                case .success(let content):
                    confirmationsByListingID[listingID] = content
                case .failure(.loginRequired):
                    loginRejected = true
                    group.cancelAll()
                case .failure:
                    break
                }
                if !loginRejected {
                    addNext()
                }
            }
        }

        let enrichedListings = listings.map { listing in
            guard let content = confirmationsByListingID[listing.id] else {
                return zucheUnconfirmedListing(listing, loginRejected: loginRejected)
            }
            return listingWithZucheConfirmation(listing, content: content)
        }

        return ZucheFeeEnrichment(
            listings: enrichedListings,
            attemptedWithCookies: true,
            confirmedFeeCount: confirmationsByListingID.values.filter { zucheActualBaseServiceFee(from: $0) != nil }.count,
            loginRejected: loginRejected,
            confirmedTotalCount: enrichedListings.filter { $0.confirmedQuote != nil }.count
        )
    }

    private func confirmationQuoteContent(
        context: ZucheConfirmationContext,
        cookieHeader: String
    ) async throws -> ZucheConfirmOrderContent {
        let envelope: ZucheResponse<ZucheConfirmOrderContent> = try await postGatewayForm(
            uri: "/action/carrctapi/order/confirmOrderInfo/v4",
            payload: context.payload,
            cookieHeader: cookieHeader
        )
        if envelope.status == "NOT_LOGIN" || envelope.code == 5 {
            throw PlatformAPIError.loginRequired
        }
        guard envelope.code == 1 || envelope.status == "SUCCESS", let content = envelope.content else {
            throw PlatformAPIError.message(envelope.msg ?? "神州确认页接口返回异常")
        }
        return content
    }

    @MainActor
    private func zucheCookieHeader(for url: URL? = nil) async -> String? {
        let store = WKWebsiteDataStore.default().httpCookieStore
        await PlatformSessionPersistence.shared.start()
        return await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                let valid = cookies.filter { ZucheCookieVault.isZucheCookie($0) && ($0.expiresDate.map { $0 > Date() } ?? true) }
                let zucheCookies = url.map { cookiesForRequest(valid, url: $0) } ?? valid
                guard !zucheCookies.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: HTTPCookie.requestHeaderFields(with: zucheCookies)["Cookie"])
            }
        }
    }

    private func listingWithZucheConfirmation(_ listing: RentalListing, content: ZucheConfirmOrderContent) -> RentalListing {
        let quote = zucheConfirmedQuote(from: content)
        let serviceFee = zucheActualBaseServiceFee(from: content) ?? listing.platformFees
        return RentalListing(
            id: listing.id,
            platform: listing.platform,
            store: listing.store,
            vehicleName: listing.vehicleName,
            vehicleClass: listing.vehicleClass,
            basePrice: listing.basePrice,
            platformFees: serviceFee,
            insuranceFees: listing.insuranceFees,
            oneWayFee: listing.oneWayFee,
            sourceUrl: listing.sourceUrl,
            dataCompleteness: 0.90,
            warnings: listing.warnings.filter { $0 != .loginRequired && !(quote != nil && $0 == .partialPrice) },
            confirmedQuote: quote
        )
    }

    private func zucheStatusMessage(listingCount: Int, feeEnrichment: ZucheFeeEnrichment) -> String {
        if feeEnrichment.confirmedTotalCount > 0 {
            let pendingMessage = feeEnrichment.loginRejected
                ? "部分后续核价请求未通过登录校验；已核价结果保留，未完成的报价可重新登录后重试。"
                : "其余报价仍待核实，不代表登录已失效。"
            return "已读取 \(listingCount) 个候选，\(feeEnrichment.confirmedTotalCount) 个已取得登录后的确认页应付总额；\(pendingMessage)"
        }
        if feeEnrichment.confirmedFeeCount > 0 {
            return "已从神州 API 读取 \(listingCount) 个真实候选车型，其中 \(feeEnrichment.confirmedFeeCount) 个已补入确认页基础服务费。"
        }
        if feeEnrichment.attemptedWithCookies && feeEnrichment.loginRejected {
            return "已从神州 API 读取 \(listingCount) 个真实候选车型；确认页费用接口提示登录未通过，当前仅含车辆租赁费。"
        }
        if feeEnrichment.attemptedWithCookies {
            return "已从神州 API 读取 \(listingCount) 个真实候选车型；本次核价未完成，请重试核价。本次未收到登录失效响应。"
        }
        return "已从神州 API 读取 \(listingCount) 个真实候选车型；未检测到神州登录态，当前仅含车辆租赁费。"
    }

    private func makeStore(from dept: ZucheDept, cityName: String, request: SearchRequest) -> Store? {
        guard let location = dept.location else { return nil }
        return Store(
            id: String(dept.deptId),
            platform: .carInc,
            name: dept.deptName,
            city: cityName,
            address: dept.deptAddress,
            location: location,
            distanceKm: distanceKmBetween(from: request.origin, to: location),
            hours: dept.workTime
        )
    }

    private func makeStore(from dept: ZucheDeptModels, cityName: String, request: SearchRequest) -> Store? {
        guard let location = dept.location else { return nil }
        return Store(
            id: String(dept.deptId),
            platform: .carInc,
            name: dept.deptName,
            city: cityName,
            address: dept.deptAddress,
            location: location,
            distanceKm: distanceKmBetween(from: request.origin, to: location),
            hours: dept.workTime
        )
    }

    private func status(_ kind: PlatformEvidenceStatusKind, _ message: String) -> PlatformEvidenceResult {
        PlatformEvidenceResult(
            platform: .carInc,
            status: PlatformEvidenceStatus(platform: .carInc, kind: kind, message: message, sourceUrl: "https://www.zuche.com/"),
            listings: []
        )
    }
}

// MARK: - Ehi

@MainActor
private final class EhiBridgeClient: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Never>?
    private var sessionObserver: NSObjectProtocol?
    private var queryStartedAt = Date()

    override init() {
        super.init()
        sessionObserver = NotificationCenter.default.addObserver(
            forName: EhiLoginSession.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resetWebView()
            }
        }
    }

    deinit {
        if let sessionObserver {
            NotificationCenter.default.removeObserver(sessionObserver)
        }
    }

    func search(request: SearchRequest) async -> PlatformEvidenceResult {
        queryStartedAt = Date()
        return await platformResultWithTimeout(
            platform: .ehi,
            onTimeout: { [weak self] in
                self?.resetWebView()
            }
        ) { [weak self] in
            guard let self else {
                return PlatformEvidenceResult(
                    platform: .ehi,
                    status: PlatformEvidenceStatus(
                        platform: .ehi,
                        kind: .parseFailed,
                        message: "一嗨 API 查询已取消，请重试。",
                        sourceUrl: "https://booking.1hai.cn/order/firstStep"
                    ),
                    listings: []
                )
            }
            return await self.performSearch(request: request)
        }
    }

    private func performSearch(request: SearchRequest) async -> PlatformEvidenceResult {
        do {
            let webView = try await readyWebView()
            try Task.checkCancellation()
            let timeRange = platformQueryTimeRange(pickupDate: request.pickupAt, returnDate: request.returnAt)
            let payload = try JSONEncoder().encode(EhiBridgeRequest(request: request, timeRange: timeRange, queryBudgetMilliseconds: Int(max(1, min(28000, (32 - Date().timeIntervalSince(queryStartedAt)) * 1000)))))
            let json = String(data: payload, encoding: .utf8) ?? "{}"
            let result = try await webView.callAsyncJavaScript(ehiSearchScript(json: json), arguments: [:], in: nil, contentWorld: .page)
            guard let resultString = result as? String else {
                return status(.parseFailed, "一嗨 API 桥接返回了无法识别的数据。")
            }
            if let response = try? JSONSerialization.jsonObject(with: Data(resultString.utf8)) as? [String: Any], let diagnostics = response["diagnostics"] {
                traceLiveSearch("ehi stages=\(diagnostics)")
            }
            let decoded = try JSONDecoder().decode(EhiBridgeResponse.self, from: Data(resultString.utf8))
            let kind = PlatformEvidenceStatusKind(rawValue: decoded.statusKind) ?? .parseFailed
            let listings = decoded.listings.map { $0.domainListing(request: request) }
            var message = decoded.message
            let query = request.vehicleQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty && !listings.isEmpty {
                let matched = listings.filter { listing in
                    let match = matchVehicle(query: query, vehicleName: listing.vehicleName, vehicleClass: listing.vehicleClass)
                    return isSpecificVehicleModelQuery(query) ? match.kind == .exact : match.kind != .lowConfidence
                }.count
                message += matched > 0 ? "其中匹配当前车型 \(matched) 个。" : "已查结果未匹配当前车型，不代表未查门店无车。"
            }
            traceLiveSearch("ehi cities=\(decoded.queriedCityCount ?? 0) stores=\(decoded.completedStoreCount ?? 0) unknownCitiesSkipped=\(decoded.skippedUnknownCityCount ?? 0) budgetExpired=\(decoded.budgetExpired ?? false)")
            if decoded.budgetExpired == true { resetWebView() }
            return PlatformEvidenceResult(
                platform: .ehi,
                status: PlatformEvidenceStatus(platform: .ehi, kind: kind, message: message, sourceUrl: decoded.sourceUrl),
                listings: listings
            )
        } catch {
            return status(.parseFailed, "一嗨 API 查询失败：\(error.localizedDescription)")
        }
    }

    private func readyWebView() async throws -> WKWebView {
        if let webView, let currentURL = webView.url, currentURL.host == "booking.1hai.cn", currentURL.path == "/order/firstStep" {
            return webView
        }

        let dataStore = WKWebsiteDataStore.default()
        await PlatformSessionPersistence.shared.start()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.navigationDelegate = self
        self.webView = webView

        await withCheckedContinuation { continuation in
            self.continuation = continuation
            webView.load(EhiLoginSession.makeLoginRequest())
        }
        return webView
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume()
        continuation = nil
    }

    private func resetWebView() {
        continuation?.resume()
        continuation = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
    }

    private func status(_ kind: PlatformEvidenceStatusKind, _ message: String) -> PlatformEvidenceResult {
        PlatformEvidenceResult(
            platform: .ehi,
            status: PlatformEvidenceStatus(platform: .ehi, kind: kind, message: message, sourceUrl: "https://booking.1hai.cn/order/firstStep"),
            listings: []
        )
    }

    private func ehiSearchScript(json: String) -> String {
        makeEhiSearchScript(json: json)
    }
}

func makeEhiSearchScript(json: String) -> String {
        """
        const request = \(json);
        const sourceUrl = 'https://booking.1hai.cn/order/firstStep';
        const apiTimeoutMs = 6000;
        \(makeEhiQueryBudgetScript())
        for (let i = 0; i < 50 && !window.webpackChunkbooking; i += 1) {
          await new Promise(resolve => setTimeout(resolve, 100));
        }
        if (!window.webpackChunkbooking) {
          return JSON.stringify({
            statusKind: 'parse-failed',
            message: '一嗨 API 页面脚本未加载完成，请稍后重试。',
            sourceUrl,
            listings: []
          });
        }
        const reqId = Math.floor(Math.random() * 1000000000);
        let requireFn;
        window.webpackChunkbooking.push([[reqId], {}, function(r) { requireFn = r; }]);
        const http = requireFn(4211).A;
        const util = requireFn(2780).A;
        const days = request.rentalDays || Math.max(1, Math.ceil((Date.parse(request.returnTime.replace(' ', 'T') + ':00+08:00') - Date.parse(request.pickupTime.replace(' ', 'T') + ':00+08:00')) / 86400000));
        const hasVehicleQuery = (request.vehicleQuery || '').trim().length > 0;
        // The official encrypted SDK is kept serial: parallel stock calls can return incomplete bodies.
        const ehiProbeConcurrency = 1;
        const decodeObfuscatedDigits = (value) => String(value).split('').map(ch => {
          const code = ch.charCodeAt(0);
          return code >= 57345 && code <= 57354 ? String(code - 57345) : ch;
        }).join('');
        const num = (value) => {
          if (value === null || value === undefined || value === '') return null;
          const n = Number(decodeObfuscatedDigits(value).replace(/[^0-9.]/g, ''));
          return Number.isFinite(n) ? n : null;
        };
        const firstNumber = (...values) => {
          for (const value of values) {
            const n = num(value);
            if (Number.isFinite(n)) return n;
          }
          return null;
        };
        const firstText = (...values) => {
          for (const value of values) {
            if (value === null || value === undefined) continue;
            const text = String(value).trim();
            if (text.length) return text;
          }
          return '';
        };
        const distanceKm = (a, b) => {
          const rad = Math.PI / 180;
          const dLat = (b.lat - a.lat) * rad;
          const dLng = (b.lng - a.lng) * rad;
          const lat1 = a.lat * rad;
          const lat2 = b.lat * rad;
          const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
          return 6371 * 2 * Math.asin(Math.sqrt(h));
        };
        \(makeEhiResponseFailureScript())
        const responseBody = (resp) => (resp && resp.data && (resp.data.result ?? resp.data.data ?? resp.data)) ?? (resp && (resp.result ?? resp.data)) ?? resp ?? {};
        const hasResponseBody = (value) => {
          if (value === null || value === undefined) return false;
          if (Array.isArray(value)) return value.length > 0;
          return typeof value !== 'object' || Object.keys(value).length > 0;
        };
        const shape = (value) => Array.isArray(value) ? `array(${value.length})` : `${typeof value}:${Object.keys(value || {}).slice(0, 8).join(',')}`;
        const arraysFrom = (value) => {
          if (Array.isArray(value)) return value;
          if (!value || typeof value !== 'object') return [];
          const direct = ['cities', 'cityList', 'allCities', 'hotCities', 'hotCityList', 'list', 'items', 'records']
            .flatMap(key => Array.isArray(value[key]) ? value[key] : []);
          if (direct.length) return direct;
          return Object.values(value).flatMap(child => Array.isArray(child) ? child : []);
        };
        const cityName = (city) => firstText(city.city, city.cityName, city.name, city.shortName);
        const cityId = (city) => city.cityId ?? city.id ?? city.cityCode;
        const cityPoint = (city) => {
          const lat = firstNumber(city.cityLat, city.lat, city.latitude, city.centerLat);
          const lng = firstNumber(city.cityLon, city.cityLng, city.lon, city.lng, city.longitude, city.centerLng);
          return Number.isFinite(lat) && Number.isFinite(lng) ? { lat, lng } : null;
        };
        const origin = { lat: request.origin.lat, lng: request.origin.lng };
        const originLabel = request.originLabel || '';
        const originCityCandidates = Array.isArray(request.originCityCandidates) ? request.originCityCandidates : [];

        const cityListResp = await withAPITimeout(() => http.getEncrypt('/Address/City/List', {}), '一嗨城市接口');
        const cityFailure = ehiResponseFailure(cityListResp);
        if (cityFailure) return JSON.stringify({ ...cityFailure, sourceUrl, listings: [] });
        const cityResult = responseBody(cityListResp);
        const cities = arraysFrom(cityResult).filter(city => city && typeof city === 'object' && cityId(city) !== undefined);
        if (!cities.length) {
          return JSON.stringify({
            statusKind: 'parse-failed',
            message: `一嗨城市接口返回成功，但没有可解析城市：${shape(cityResult)}。`,
            sourceUrl,
            listings: []
          });
        }
        const aliasMatchesCity = (name) => {
          const normalized = name.replace(/市$/, '');
          return originCityCandidates.some(alias => {
            const value = String(alias || '').trim();
            return value && (name.includes(value) || normalized.includes(value) || value.includes(name) || value.includes(normalized));
          });
        };
        const normalizedCityName = (name) => String(name || '').replace(/市$/, '').trim();
        const cityMatchesOrigin = (candidate) => {
          const name = cityName(candidate);
          const normalized = normalizedCityName(name);
          return name && (originLabel.includes(name) || originLabel.includes(normalized) || aliasMatchesCity(name));
        };
        const cityEntries = cities.map(candidate => {
          const point = cityPoint(candidate);
          return {
            city: candidate,
            distanceKm: point ? distanceKm(origin, point) : null,
            isCurrentCity: false
          };
        });
        const currentCityEntry = cityEntries.find(entry => cityMatchesOrigin(entry.city))
          || cityEntries
            .filter(entry => Number.isFinite(entry.distanceKm))
            .sort((a, b) => a.distanceKm - b.distanceKm)[0];
        if (!currentCityEntry) {
          return JSON.stringify({ statusKind: 'unavailable', message: `一嗨没有识别到“${originLabel}”对应的可租城市。`, sourceUrl, listings: [] });
        }
        const currentCityId = String(cityId(currentCityEntry.city));
        \(makeEhiCityPlanningScript())
        const ehiCandidateCities = planEhiCityEntries(cityEntries, currentCityId, request.radiusKm);
        if (!ehiCandidateCities.length) {
          return JSON.stringify({ statusKind: 'unavailable', message: `一嗨没有识别到“${originLabel}”对应的可租城市。`, sourceUrl, listings: [] });
        }

        const isRailwayStationStore = (store, cityPlan) => {
          const text = `${store.name} ${store.address}`;
          if (text.includes('机场')) return false;
          if (['火车站', '高铁站', '高铁', '动车站', '铁路'].some(token => text.includes(token))) return true;
          const normalized = normalizedCityName(cityName(cityPlan.city));
          return normalized && [`${normalized}站`, `${normalized}东站`, `${normalized}西站`, `${normalized}南站`, `${normalized}北站`].some(token => text.includes(token));
        };
        const selectedStoreForCity = (cityPlan, cityStores) => {
          const sortedStores = cityStores.slice().sort((a, b) => {
            if (a.distanceKm !== b.distanceKm) return a.distanceKm - b.distanceKm;
            return a.name.localeCompare(b.name, 'zh-Hans-CN');
          });
          return cityPlan.isCurrentCity ? sortedStores[0] : sortedStores.find(store => isRailwayStationStore(store, cityPlan));
        };
        const collectStores = (value, output = []) => {
          if (!value) return output;
          if (Array.isArray(value)) {
            value.forEach(item => collectStores(item, output));
            return output;
          }
          if (typeof value !== 'object') return output;
          const lat = firstNumber(value.amapPickupLatitude, value.pickupLatitude, value.latitude, value.lat, value.storeLat);
          const lng = firstNumber(value.amapPickupLongitude, value.pickupLongitude, value.longitude, value.lng, value.storeLng);
          const id = value.id ?? value.managerId ?? value.storeId ?? value.manageStoreId;
          const name = firstText(value.name, value.shortName, value.storeName, value.managerName);
          if (id !== undefined && name && Number.isFinite(lat) && Number.isFinite(lng)) {
            output.push(value);
          }
          ['stores', 'storeList', 'children', 'items', 'list', 'records', 'data', 'result'].forEach(key => collectStores(value[key], output));
          return output;
        };
        const storeCityPlans = hasVehicleQuery
          ? ehiCandidateCities
          : ehiCandidateCities.filter(entry => entry.isCurrentCity).slice(0, 1);
        const queryErrors = [];
        const cityStoreCandidates = [];
        const vehicleStoreCandidates = [];
        const cityFetchResults = [];
        const storeCandidates = [];
        const candidates = [];
        let citiesCompleted = 0;
        let storesCompleted = 0;
        const maxCurrentCityStoreProbes = 4;
        const fetchStoresForCity = async (cityPlan) => {
          let storeResult = null;
          try {
            const storeResp = await withAPITimeout(
              () => http.getEncrypt('/Address/ReservationBooking/List', { cityId: cityId(cityPlan.city), operationTime: request.pickupTime }),
              `${cityName(cityPlan.city)}一嗨门店接口`
            );
            const failure = ehiResponseFailure(storeResp);
            if (failure) return { cityStores: [], selectedStore: null, error: failure.message, failure };
            storeResult = responseBody(storeResp);
          } catch (error) {
            return {
              cityStores: [],
              selectedStore: null,
              error: `${cityName(cityPlan.city)}门店接口: ${String(error && (error.message || error.stack) || error)}`
            };
          }
          const storesById = {};
          for (const store of collectStores(storeResult)) {
            const id = String(store.id ?? store.managerId ?? store.storeId ?? store.manageStoreId);
            storesById[id] = store;
          }
          const cityStores = Object.values(storesById)
            .map(s => ({
              raw: s,
              city: cityPlan.city,
              cityId: cityId(cityPlan.city),
              id: String(s.id ?? s.managerId ?? s.storeId ?? s.manageStoreId),
              name: firstText(s.name, s.shortName, s.storeName, '一嗨门店'),
              address: firstText(s.address, s.pickupAddress, s.pickupDropoffAddress),
              lat: firstNumber(s.amapPickupLatitude, s.pickupLatitude, s.latitude, s.lat, s.storeLat),
              lng: firstNumber(s.amapPickupLongitude, s.pickupLongitude, s.longitude, s.lng, s.storeLng),
              hours: `${firstText(String(s.fromTime || '').slice(11, 16), '以平台为准')}-${firstText(String(s.toTime || '').slice(11, 16), '')}`
            }))
            .filter(s => Number.isFinite(s.lat) && Number.isFinite(s.lng))
            .map(s => ({ ...s, distanceKm: distanceKm(origin, { lat: s.lat, lng: s.lng }) }))
            .sort((a, b) => a.distanceKm - b.distanceKm);
          if (!cityStores.length && hasResponseBody(storeResult)) {
            const failure = { statusKind: 'parse-failed', message: '门店接口返回了内容，但未解析到有效坐标：' + shape(storeResult) };
            return { cityStores: [], selectedStore: null, error: failure.message, failure };
          }
          const storesInsideRadiusForCity = cityStores.filter(s => s.distanceKm <= request.radiusKm);
          const selectedStore = selectedStoreForCity(cityPlan, storesInsideRadiusForCity);
          const selectedStores = cityPlan.isCurrentCity ? storesInsideRadiusForCity.slice(0, maxCurrentCityStoreProbes) : (selectedStore ? [selectedStore] : []);
          return { cityStores, selectedStore, selectedStores, error: null,
            diagnostic: { city: cityName(cityPlan.city), code: storeResult?.code, message: storeResult?.message, shape: shape(storeResult), children: Object.entries(storeResult || {}).slice(0, 6).map(([key, value]) => [key, shape(value)]), parsed: cityStores.length }
          };
        };
        const carName = (item, car) => firstText(car.name, car.carTypeName, car.modelName, car.vehicleName, item.carTypeName, item.modelName, item.vehicleName, item.name);
        const carId = (item, car, name) => firstText(car.id, car.carTypeId, car.modelId, item.carTypeId, item.modelId, item.id, name);
        const collectCarItems = (value, output = []) => {
          if (!value) return output;
          if (Array.isArray(value)) {
            value.forEach(item => collectCarItems(item, output));
            return output;
          }
          if (typeof value !== 'object') return output;
          const car = value.carType || value.car || value.vehicle || value.model || value;
          const looksLikeCar = carName(value, car) && (
            value.carType ||
            ['baseAvgAmount', 'avgAmount', 'baseAmount', 'price', 'dailyPrice', 'dayPrice', 'totalAmount', 'totalPrice', 'lowPrice']
              .some(key => value[key] !== undefined || car[key] !== undefined)
          );
          if (looksLikeCar) output.push(value);
          ['bookingAvailableCarTypes', 'unAvailableCarTypes', 'availableCarTypes', 'carTypes', 'carTypeList', 'vehicleList', 'carList', 'models', 'list', 'items', 'records']
            .forEach(key => collectCarItems(value[key], output));
          return output;
        };
        const priceFrom = (item, car) => {
          const daily = firstNumber(
            item.baseAvgAmount, item.avgAmount, item.baseAmount, item.price, item.dailyPrice, item.dayPrice, item.lowPrice,
            car.baseAvgAmount, car.avgAmount, car.baseAmount, car.price, car.dailyPrice, car.dayPrice, car.lowPrice
          );
          if (Number.isFinite(daily) && daily > 0) return daily * days;
          const total = firstNumber(
            item.baseTotalAmount, item.totalAmount, item.totalPrice, item.orderTotalAmount, item.payAmount,
            car.baseTotalAmount, car.totalAmount, car.totalPrice, car.orderTotalAmount, car.payAmount
          );
          return Number.isFinite(total) && total > 0 ? total : null;
        };

        const listingsByKey = {};
        const storeSkips = [];
        const stock401SkipMessage = (store, label) => `${store.name} ${label}: 报价接口返回 401，已跳过该候选`;
        let carsSeen = 0;
        let stockAttemptCount = 0;
        let stock401Count = 0;
        let selectedBlankStoreId = null;
        const quoteStore = async (store) => {
          const storeSkips = [];
          const storeListings = [];
          let storeStockAttemptCount = 0;
          let storeStock401Count = 0;
          const makeStockPayload = (isEnterprise) => ({
            stockType: 1,
            whereFilter: null,
            pickupDto: { cityId: store.cityId, storeId: Number(store.id), operationTime: request.pickupTime, isService: false },
            pickupAddressDto: null,
            returnDto: { cityId: store.cityId, storeId: Number(store.id), operationTime: request.returnTime, isService: false },
            returnAddressDto: null,
            requestContext: {
              platform: util.getGD('platform'),
              platformSource: null,
              operatorId: null,
              userId: null,
              channelId: null,
              enterpriseId: null,
              optionTag: { isRecalculation: false, isChargeFee: false, choose: 3, isEnterprise, moduleIds: null }
            }
          });
          const stockPayloads = [
            { label: '个人方案', isEnterprise: false },
            { label: '默认上下文', isEnterprise: true }
          ];

          let stockResult = null;
          for (const { label, isEnterprise } of stockPayloads) {
            if (remainingQueryBudget() <= 0) { queryBudgetExpired = true; break; }
            const payload = makeStockPayload(isEnterprise);
            try {
              const verifyResp = await withAPITimeout(() => http.postEncrypt('/Verify/Step1', '', payload), `${store.name} ${label} 校验接口`);
              const verify = responseBody(verifyResp);
              if (!hasResponseBody(verify)) {
                storeSkips.push(`${store.name} ${label}: 校验接口没有返回内容`);
                continue;
              }
              if (!verify.isSuccess) {
                storeSkips.push(`${store.name} ${label}: ${verify.message || '取还时间不可用'}`);
                continue;
              }
              storeStockAttemptCount += 1;
              const stockResp = await withAPITimeout(() => http.postEncrypt('/Stock/Step2', '', payload), `${store.name} ${label} 报价接口`);
              const code = stockResp?.code ?? stockResp?.status ?? stockResp?.data?.code ?? stockResp?.data?.status;
              if (code === 401) {
                storeStock401Count += 1;
                storeSkips.push(stock401SkipMessage(store, label));
                continue;
              }
              stockResult = responseBody(stockResp);
              if (!hasResponseBody(stockResult)) {
                storeSkips.push(`${store.name} ${label}: 报价接口没有返回内容`);
                stockResult = null;
                continue;
              }
              break;
            } catch (error) {
              const message = String(error && (error.message || error.stack) || error);
              if (message.includes('401')) {
                storeStock401Count += 1;
                storeSkips.push(stock401SkipMessage(store, label));
                continue;
              }
              storeSkips.push(`${store.name} ${label}: ${message}`);
            }
          }
          if (!stockResult) {
            return { storeListings: [], storeSkips, carsSeen: 0, stockAttemptCount: storeStockAttemptCount, stock401Count: storeStock401Count };
          }

          let storeCarsSeen = 0;
          const carItems = collectCarItems(stockResult);
          for (const item of carItems) {
            const car = item.carType || item.car || item.vehicle || item.model || item;
            const name = carName(item, car);
            if (!name) continue;
            storeCarsSeen += 1;
            const basePrice = priceFrom(item, car);
            if (!basePrice) continue;
            const key = `${store.id}-${name}`;
            const listing = {
              id: `ehi-${store.id}-${carId(item, car, name)}`,
              storeId: store.id,
              storeName: store.name,
              city: cityName(store.city),
              address: store.address,
              lat: store.lat,
              lng: store.lng,
              distanceKm: store.distanceKm,
              hours: store.hours,
              vehicleName: name,
              vehicleClass: [
                firstText(car.gearName, item.gearName),
                firstText(car.structureName, item.structureName),
                firstText(car.maxPassenger ? `${car.maxPassenger}座` : '', item.maxPassenger ? `${item.maxPassenger}座` : '')
              ].filter(Boolean).join(' | '),
              basePrice,
              platformFees: 0,
              insuranceFees: 0,
              oneWayFee: 0,
              sourceUrl,
              dataCompleteness: 0.88
            };
            storeListings.push({ key, listing });
          }
          return { storeListings, storeSkips, carsSeen: storeCarsSeen, stockAttemptCount: storeStockAttemptCount, stock401Count: storeStock401Count };
        };
        const applyQuoteResult = (quoteResult) => {
          storeSkips.push(...quoteResult.storeSkips);
          carsSeen += quoteResult.carsSeen;
          stockAttemptCount += quoteResult.stockAttemptCount || 0;
          stock401Count += quoteResult.stock401Count || 0;
          for (const { key, listing } of quoteResult.storeListings) {
            if (!listingsByKey[key] || listingsByKey[key].basePrice > listing.basePrice) listingsByKey[key] = listing;
          }
        };
        const recordCityResult = result => {
          citiesCompleted += 1;
          cityFetchResults.push(result);
          if (result.error) queryErrors.push(result.error);
          cityStoreCandidates.push(...result.cityStores);
        };
        if (hasVehicleQuery) {
          const queue = createEhiQueryQueue(ehiProbeConcurrency, error => queryErrors.push(String(error)));
          for (const cityPlan of storeCityPlans) {
            queue.add(async () => {
              const result = await fetchStoresForCity(cityPlan);
              recordCityResult(result);
              const targets = result.selectedStores || [];
              vehicleStoreCandidates.push(...targets);
              candidates.push(...targets);
              queue.addAll(targets.map(store => async () => {
                const quote = await quoteStore(store);
                applyQuoteResult(quote);
                storesCompleted += 1;
              }), cityPlan.isCurrentCity);
            });
          }
          await withEhiQueryBudget(() => queue.run());
          storeCandidates.push(...cityStoreCandidates.sort((a, b) => a.distanceKm - b.distanceKm));
        } else {
          await withEhiQueryBudget(async () => {
            const result = await fetchStoresForCity(storeCityPlans[0]);
            recordCityResult(result);
            storeCandidates.push(...result.cityStores.sort((a, b) => a.distanceKm - b.distanceKm));
            const blankStoreProbeLimit = 40;
            const blankStoreCandidates = storeCandidates.filter(s => s.distanceKm <= request.radiusKm);
            candidates.push(...blankStoreCandidates.slice(0, blankStoreProbeLimit));
            for (const store of candidates) {
              if (remainingQueryBudget() <= 0) { queryBudgetExpired = true; break; }
              if (!hasVehicleQuery && selectedBlankStoreId && store.id !== selectedBlankStoreId) break;
              const quote = await quoteStore(store);
              applyQuoteResult(quote);
              storesCompleted += 1;
              if (quote.storeListings.length) { selectedBlankStoreId = store.id; break; }
            }
          });
        }
        const coverage = '已查 ' + citiesCompleted + '/' + storeCityPlans.length + ' 个可定位城市，完成 ' + storesCompleted + ' 个门店报价';
        if (queryBudgetExpired && !Object.keys(listingsByKey).length) {
          return JSON.stringify({statusKind: 'parse-failed', message: '一嗨查询达到本次时限，' + coverage + '，尚未取得可用报价；请缩小范围或重试。', sourceUrl, listings: [], budgetExpired: true});
        }
        if (!candidates.length) {
          const failures = cityFetchResults.map(item => item.failure).filter(Boolean);
          const failure = failures.find(item => item.statusKind === 'login-required') || failures[0];
          if (failure) return JSON.stringify({ ...failure, message: '一嗨门店接口：' + failure.message, sourceUrl, listings: [] });
          if (queryErrors.length) return JSON.stringify({ statusKind: 'parse-failed', message: '一嗨门店查询失败：' + queryErrors.slice(0, 2).join('；'), sourceUrl, listings: [] });
          const message = hasVehicleQuery
            ? '一嗨在当前范围内没有可用取车点。'
            : `一嗨在当前 ${Math.round(request.radiusKm)}km 内没有可用取车点。`;
          return JSON.stringify({ statusKind: 'unavailable', message, sourceUrl, listings: [], diagnostics: request.includeDiagnostics ? cityFetchResults.map(item => item.diagnostic || item.error) : undefined });
        }
        const listings = Object.values(listingsByKey);
        if (!listings.length && stockAttemptCount > 0 && stock401Count === stockAttemptCount) {
          return JSON.stringify({
            statusKind: 'login-required',
            message: `一嗨库存报价 /Stock/Step2 均返回 401；请先登录一嗨后重试。已识别 ${storeCandidates.length} 个门店。`,
            sourceUrl,
            listings: []
          });
        }
        if (!listings.length && carsSeen > 0) {
          return JSON.stringify({
            statusKind: 'parse-failed',
            message: `一嗨库存接口返回了 ${carsSeen} 个车型，但未识别到可用价格字段。`,
            sourceUrl,
            listings: []
          });
        }
        if (!listings.length && queryErrors.length) {
          return JSON.stringify({
            statusKind: 'parse-failed',
            message: `一嗨 API 查询失败：${queryErrors.slice(0, 2).join('；')}`,
            sourceUrl,
            listings: []
          });
        }
        if (!listings.length && storeSkips.length) {
          const message = hasVehicleQuery
            ? `一嗨真实接口可访问，但候选门店暂不可报价：${storeSkips.slice(0, 2).join('；')}`
            : `一嗨真实接口可访问，但半径 ${Math.round(request.radiusKm)}km 内候选门店暂不可报价：${storeSkips.slice(0, 2).join('；')}`;
          return JSON.stringify({
            statusKind: 'unavailable',
            message,
            sourceUrl,
            listings: []
          });
        }
        const blankUnavailableMessage = `一嗨真实接口返回成功，但半径 ${Math.round(request.radiusKm)}km 内已探测 ${candidates.length} 个候选门店没有可订车型。`;
        const vehicleUnavailableMessage = '一嗨' + coverage + '，当前已查门店未返回可订车型；不代表范围内所有门店均无车。';
        return JSON.stringify({
          statusKind: listings.length ? 'ready' : 'unavailable',
          message: listings.length
            ? ('已从一嗨 API 读取 ' + listings.length + ' 个真实候选车型；' + coverage + (queryBudgetExpired ? '，达到时限，已保留返回结果。' : '。'))
            : (hasVehicleQuery ? vehicleUnavailableMessage : blankUnavailableMessage),
          sourceUrl,
          listings,
          budgetExpired: queryBudgetExpired,
          queriedCityCount: citiesCompleted,
          completedStoreCount: storesCompleted,
          skippedUnknownCityCount: cityEntries.filter(e => String(cityId(e.city)) !== currentCityId && !Number.isFinite(e.distanceKm)).length
        });
        """
}

// MARK: - Shared Models

struct ZucheResponse<Content: Decodable>: Decodable {
    let code: Int?
    let status: String?
    let msg: String?
    let content: Content?
}

private struct ZucheCityListContent: Decodable {
    let allCities: [ZucheCity]
}

private struct ZucheCity: Decodable {
    let cityId: String
    let cityName: String
    let cityLat: String?
    let cityLon: String?

    var searchCity: ZucheSearchCity {
        ZucheSearchCity(id: cityId, name: cityName, location: location)
    }

    var location: GeoPoint? {
        guard let lat = Double(cityLat ?? ""), let lng = Double(cityLon ?? "") else { return nil }
        return GeoPoint(lat: lat, lng: lng)
    }
}

private struct ZucheDeptListContent: Decodable {
    let districtList: [ZucheDistrict]
}

private struct ZucheDistrict: Decodable {
    let deptList: [ZucheDept]
}

private struct ZucheDept: Decodable {
    let deptName: String
    let deptAddress: String
    let deptLon: String
    let deptLat: String
    let workTime: String
    let deptId: Int
    let inventoryAbleFlag: Bool?

    var location: GeoPoint? {
        guard let lat = Double(deptLat), let lng = Double(deptLon) else { return nil }
        return GeoPoint(lat: lat, lng: lng)
    }
}

private struct ZucheChooseCarContent: Decodable {
    let deptHangModels: [ZucheDeptModels]
}

private struct ZucheDeptModels: Decodable {
    let deptName: String
    let lon: String
    let lat: String
    let deptAddress: String
    let workTime: String
    let deptId: Int
    let cityId: Int?
    let pickupWebsite: Int?
    let pickupAppropriate: Int?
    let chainFlag: Bool?
    let models: [ZucheModel]

    var location: GeoPoint? {
        guard let lat = Double(lat), let lng = Double(lon) else { return nil }
        return GeoPoint(lat: lat, lng: lng)
    }
}

private struct ZucheModel: Decodable {
    let packagePrice: String?
    let lowPrice: Double?
    let modelId: Int
    let havePriceFlag: Bool?
    let modelName: String
    let modelDesc: String
    let bookFlag: Bool?

    var price: Double? {
        lowPrice ?? Double(packagePrice ?? "")
    }
}

struct ZucheConfirmOrderContent: Decodable {
    let feeInfos: ZucheConfirmFeeInfos?
    let bottomInfo: ZucheConfirmBottomInfo?
}

struct ZucheConfirmFeeInfos: Decodable {
    let baseFeeInfo: [ZucheConfirmFeeItem]?
}

struct ZucheConfirmFeeItem: Decodable {
    let itemName: String?
    let itemDesc: String?
    let itemPrice: Double?

    private enum CodingKeys: String, CodingKey {
        case itemName
        case itemDesc
        case itemPrice
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemName = try container.decodeIfPresent(String.self, forKey: .itemName)
        itemDesc = try container.decodeIfPresent(String.self, forKey: .itemDesc)
        itemPrice = try container.decodeLosslessDoubleIfPresent(forKey: .itemPrice)
    }
}

struct ZucheConfirmBottomInfo: Decodable {
    let totalPrice: Double?

    private enum CodingKeys: String, CodingKey {
        case totalPrice
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalPrice = try container.decodeLosslessDoubleIfPresent(forKey: .totalPrice)
    }
}

func zucheConfirmedQuote(from content: ZucheConfirmOrderContent, checkedAt: Date = Date()) -> ConfirmedRentalQuote? {
    guard let total = content.bottomInfo?.totalPrice, total.isFinite, total >= 0 else { return nil }
    let items = (content.feeInfos?.baseFeeInfo ?? []).compactMap { item -> ConfirmedRentalFee? in
        guard let name = item.itemName, !name.isEmpty else { return nil }
        let amount = item.itemPrice.flatMap { $0.isFinite ? $0 : nil }
        return ConfirmedRentalFee(name: name, amount: amount, detail: item.itemDesc)
    }
    return ConfirmedRentalQuote(
        payableTotal: total,
        items: items,
        checkedAt: checkedAt,
        sourceURL: "https://www.zuche.com/",
        scope: "同店取还、平台默认预订方案；改变保障、优惠或取还条件后需重新核价。押金/预授权及退订规则以官方页面为准。"
    )
}

func zucheActualBaseServiceFee(from content: ZucheConfirmOrderContent) -> Double? {
    let feeItems = content.feeInfos?.baseFeeInfo ?? []
    let serviceFee = feeItems
        .filter { item in
            let name = item.itemName ?? ""
            return name.contains("基础服务费") || name.contains("基本服务费")
        }
        .compactMap(zucheFeeAmount)
        .reduce(0, +)
    return serviceFee > 0 ? serviceFee : nil
}

private func zucheFeeAmount(from item: ZucheConfirmFeeItem) -> Double? {
    if let itemPrice = item.itemPrice {
        return itemPrice
    }
    if let itemDesc = item.itemDesc {
        return parseZucheMoneyAmount(from: itemDesc, preferTrailingTotal: true)
    }
    return nil
}

private func parseZucheMoneyAmount(from text: String, preferTrailingTotal: Bool = false) -> Double? {
    let candidateText: String
    if preferTrailingTotal, let equalIndex = text.lastIndex(of: "=") {
        candidateText = String(text[text.index(after: equalIndex)...])
    } else {
        candidateText = text
    }
    let amounts = extractNumericAmounts(from: candidateText)
    return preferTrailingTotal ? amounts.last : amounts.first
}

private func extractNumericAmounts(from text: String) -> [Double] {
    var amounts: [Double] = []
    var buffer = ""

    func flush() {
        guard !buffer.isEmpty, buffer != "-", buffer != "." else {
            buffer = ""
            return
        }
        if let value = Double(buffer) {
            amounts.append(value)
        }
        buffer = ""
    }

    for character in text {
        if character.isNumber || character == "." || (character == "-" && buffer.isEmpty) {
            buffer.append(character)
        } else {
            flush()
        }
    }
    flush()
    return amounts
}

private extension KeyedDecodingContainer {
    func decodeLosslessDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return parseZucheMoneyAmount(from: value)
        }
        return nil
    }
}

private struct EhiBridgeRequest: Encodable {
    let origin: GeoPoint
    let originLabel: String
    let originCityCandidates: [String]
    let pickupAt: String
    let returnAt: String
    let pickupTime: String
    let returnTime: String
    let rentalDays: Int
    let includeDiagnostics: Bool
    let queryBudgetMilliseconds: Int
    let radiusKm: Double
    let vehicleQuery: String

    init(request: SearchRequest, timeRange: PlatformQueryTimeRange, queryBudgetMilliseconds: Int = 28000) {
        self.queryBudgetMilliseconds = queryBudgetMilliseconds
        origin = request.origin
        originLabel = localizedChineseLocationText(request.originLabel)
        originCityCandidates = CarRentalOptimizer.originCityCandidates(from: request.originLabel)
        pickupAt = request.pickupAt
        returnAt = request.returnAt
        pickupTime = timeRange.pickupTime
        returnTime = timeRange.returnTime
        rentalDays = CarRentalOptimizer.rentalDays(request)
        includeDiagnostics = ProcessInfo.processInfo.environment["CAR_RENTAL_LIVE_PROBE"] == "1"
        radiusKm = request.radiusKm
        vehicleQuery = request.vehicleQuery
    }
}

private struct EhiBridgeResponse: Decodable {
    let statusKind: String
    let message: String
    let sourceUrl: String
    let listings: [EhiBridgeListing]
    let budgetExpired: Bool?
    let queriedCityCount: Int?
    let completedStoreCount: Int?
    let skippedUnknownCityCount: Int?
}

private struct EhiBridgeListing: Decodable {
    let id: String
    let storeId: String
    let storeName: String
    let city: String
    let address: String
    let lat: Double
    let lng: Double
    let distanceKm: Double
    let hours: String
    let vehicleName: String
    let vehicleClass: String
    let basePrice: Double
    let platformFees: Double
    let insuranceFees: Double
    let oneWayFee: Double
    let sourceUrl: String
    let dataCompleteness: Double

    func domainListing(request: SearchRequest) -> RentalListing {
        let store = Store(
            id: storeId,
            platform: .ehi,
            name: storeName,
            city: city,
            address: address,
            location: GeoPoint(lat: lat, lng: lng),
            distanceKm: distanceKm,
            hours: hours
        )
        return RentalListing(
            id: id,
            platform: .ehi,
            store: store,
            vehicleName: vehicleName,
            vehicleClass: vehicleClass,
            basePrice: basePrice,
            platformFees: platformFees,
            insuranceFees: insuranceFees,
            oneWayFee: oneWayFee,
            sourceUrl: sourceUrl,
            dataCompleteness: dataCompleteness,
            warnings: [.partialPrice]
        )
    }
}

private enum PlatformAPIError: LocalizedError {
    case message(String)
    case loginRequired

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        case .loginRequired:
            return "需要登录"
        }
    }
}

struct PlatformQueryTimeRange: Equatable {
    let pickupTime: String
    let returnTime: String
}

func platformQueryTimeRange(pickupDate: String, returnDate: String, now: Date = Date()) -> PlatformQueryTimeRange {
    let pickup = platformDateTime(for: pickupDate, alignedWith: nil, now: now)
    let returnValue = platformDateTime(for: returnDate, alignedWith: pickup.date, now: now)
    let adjustedReturn = returnValue.date <= pickup.date
        ? PlatformDateTime(date: AppDateRules.calendar.date(byAdding: .day, value: 1, to: pickup.date) ?? pickup.date)
        : returnValue
    return PlatformQueryTimeRange(pickupTime: pickup.formatted, returnTime: adjustedReturn.formatted)
}

private struct PlatformDateTime {
    let date: Date

    var formatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter.string(from: date)
    }
}

private func platformDateTime(for value: String, alignedWith pickupDate: Date?, now: Date) -> PlatformDateTime {
    if let explicit = parsePlatformDateTime(value) {
        return PlatformDateTime(date: explicit)
    }

    guard let day = AppDateRules.parseRequestDate(value) else {
        return PlatformDateTime(date: now)
    }

    if let pickupDate {
        return PlatformDateTime(date: date(on: day, hour: AppDateRules.calendar.component(.hour, from: pickupDate)))
    }

    if AppDateRules.calendar.isDate(day, inSameDayAs: now) {
        let leadTime = AppDateRules.calendar.date(byAdding: .hour, value: 2, to: now) ?? now
        let rounded = roundUpToNextHour(leadTime)
        let tenAM = date(on: day, hour: 10)
        return PlatformDateTime(date: max(rounded, tenAM))
    }

    return PlatformDateTime(date: date(on: day, hour: 10))
}

private func parsePlatformDateTime(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return formatter.date(from: value)
}

private func date(on day: Date, hour: Int) -> Date {
    var components = AppDateRules.calendar.dateComponents([.year, .month, .day], from: day)
    components.hour = hour
    components.minute = 0
    components.second = 0
    return AppDateRules.calendar.date(from: components) ?? day
}

private func roundUpToNextHour(_ value: Date) -> Date {
    let calendar = AppDateRules.calendar
    var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: value)
    let shouldRoundUp = (components.minute ?? 0) > 0 || (components.second ?? 0) > 0
    components.minute = 0
    components.second = 0
    let roundedDown = calendar.date(from: components) ?? value
    return shouldRoundUp ? (calendar.date(byAdding: .hour, value: 1, to: roundedDown) ?? roundedDown) : roundedDown
}

private func rentalDays(_ request: SearchRequest) -> Int {
    calculateRentalDays(pickupAt: request.pickupAt, returnAt: request.returnAt)
}
