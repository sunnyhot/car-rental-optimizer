import CarRentalDomain
import Foundation
import WebKit

protocol RentalSearchProviding {
    func search(request: SearchRequest) async -> [PlatformEvidenceResult]
}

@MainActor
final class LiveRentalSearchService: NSObject, RentalSearchProviding {
    private let zucheClient = ZucheAPIClient()
    private let ehiClient = EhiBridgeClient()

    func search(request: SearchRequest) async -> [PlatformEvidenceResult] {
        var results: [PlatformEvidenceResult] = []

        if request.platforms.contains(.carInc) {
            results.append(await zucheClient.search(request: request))
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

func blankVehicleCandidateListings(
    from batches: [StoreListingsBatch],
    minimumVehicleCount: Int = 12,
    maxStoreCount: Int = 6
) -> [RentalListing] {
    _ = minimumVehicleCount
    _ = maxStoreCount
    guard let nearestPricedStore = batches.sorted(by: { $0.distanceKm < $1.distanceKm }).first(where: { !$0.listings.isEmpty }) else {
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

private final class ZucheAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(request: SearchRequest) async -> PlatformEvidenceResult {
        do {
            let cities: ZucheCityListContent = try await postGateway(uri: "/action/carrctapi/order/cityList/v1", payload: [:])
            guard let city = selectCity(from: cities.allCities, request: request) else {
                return status(.unavailable, "神州没有识别到当前位置对应的可租城市。")
            }

            let deptList: ZucheDeptListContent = try await postGateway(
                uri: "/action/carrctapi/order/deptList/v1",
                payload: ["cityId": city.cityId, "entrance": 1, "pickupFlag": 1]
            )
            let stores = flattenDepartments(deptList)
            guard !stores.isEmpty else {
                return status(.unavailable, "神州当前城市没有返回可用取车点。")
            }

            let candidates = candidateStores(stores, request: request)
            guard !candidates.isEmpty else {
                return status(.unavailable, "神州在当前范围内没有可用取车点。")
            }

            let timeRange = platformQueryTimeRange(pickupDate: request.pickupAt, returnDate: request.returnAt)
            let hasVehicleQuery = !request.vehicleQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            var listingsByKey: [String: RentalListing] = [:]
            var nearestStoreBatches: [StoreListingsBatch] = []
            var queryErrors: [String] = []

            for anchor in queryAnchors(candidates: candidates, request: request) {
                let chooseCar: ZucheChooseCarContent
                do {
                    chooseCar = try await postGateway(
                        uri: "/resource/carrctapi/order/chooseCar/v3",
                        payload: [
                            "pickupCityId": city.cityId,
                            "pickupTime": timeRange.pickupTime,
                            "returnCityId": city.cityId,
                            "returnTime": timeRange.returnTime,
                            "entrance": 1,
                            "userChooseLat": String(anchor.lat),
                            "userChooseLon": String(anchor.lng),
                            "holidaysWaitingFlag": 0,
                        ]
                    )
                } catch {
                    queryErrors.append(error.localizedDescription)
                    continue
                }

                for dept in chooseCar.deptHangModels {
                    guard let store = makeStore(from: dept, request: request) else { continue }
                    if hasVehicleQuery {
                        guard store.distanceKm <= request.radiusKm else { continue }
                    }

                    let deptListings = listings(from: dept.models, store: store, request: request)
                    if !hasVehicleQuery {
                        nearestStoreBatches.append(StoreListingsBatch(distanceKm: store.distanceKm, listings: deptListings))
                        continue
                    }

                    for listing in deptListings {
                        let key = "\(store.id)-\(listing.vehicleName)"
                        if let old = listingsByKey[key], old.basePrice <= listing.basePrice {
                            continue
                        }
                        listingsByKey[key] = listing
                    }
                }
            }

            let listings = hasVehicleQuery
                ? Array(listingsByKey.values)
                : blankVehicleCandidateListings(from: nearestStoreBatches)
            guard !listings.isEmpty else {
                if !queryErrors.isEmpty {
                    return status(.parseFailed, "神州 API 部分查询失败：\(queryErrors.prefix(2).joined(separator: "；"))")
                }
                return status(.unavailable, "神州真实接口返回成功，但当前条件没有可订车型。")
            }

            return PlatformEvidenceResult(
                platform: .carInc,
                status: PlatformEvidenceStatus(
                    platform: .carInc,
                    kind: .ready,
                    message: "已从神州 API 读取 \(listings.count) 个真实候选车型。",
                    sourceUrl: "https://m.zuche.com/"
                ),
                listings: listings
            )
        } catch {
            return status(.parseFailed, "神州 API 查询失败：\(error.localizedDescription)")
        }
    }

    private func postGateway<Response: Decodable>(uri: String, payload: [String: Any]) async throws -> Response {
        let envelope: ZucheResponse<Response> = try await postForm(
            url: URL(string: "https://m.zuche.com/api/gw.do?uri=\(uri)")!,
            payload: payload,
            referer: "https://m.zuche.com/"
        )
        guard envelope.code == 1 || envelope.status == "SUCCESS", let content = envelope.content else {
            throw PlatformAPIError.message(envelope.msg ?? "神州接口返回异常")
        }
        return content
    }

    private func postForm<Response: Decodable>(url: URL, payload: [String: Any], referer: String) async throws -> ZucheResponse<Response> {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let json = String(data: data, encoding: .utf8) ?? "{}"
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "data", value: json)]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw PlatformAPIError.message("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return try JSONDecoder().decode(ZucheResponse<Response>.self, from: responseData)
    }

    private func selectCity(from cities: [ZucheCity], request: SearchRequest) -> ZucheCity? {
        let label = request.originLabel
        if let exact = cities.first(where: { label.contains($0.cityName) }) {
            return exact
        }

        return cities
            .compactMap { city -> (ZucheCity, Double)? in
                guard let point = city.location else { return nil }
                return (city, distanceKmBetween(from: request.origin, to: point))
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    private func flattenDepartments(_ content: ZucheDeptListContent) -> [ZucheDept] {
        content.districtList.flatMap(\.deptList).filter { $0.inventoryAbleFlag != false }
    }

    private func candidateStores(_ stores: [ZucheDept], request: SearchRequest) -> [Store] {
        let sorted = stores.compactMap { makeStore(from: $0, request: request) }.sorted { $0.distanceKm < $1.distanceKm }
        let hasVehicleQuery = !request.vehicleQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasVehicleQuery ? sorted.filter { $0.distanceKm <= request.radiusKm } : sorted
    }

    private func queryAnchors(candidates: [Store], request: SearchRequest) -> [GeoPoint] {
        let hasVehicleQuery = !request.vehicleQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasVehicleQuery else {
            return [request.origin]
        }

        let maxAnchorCount = 6
        let minimumSpacingKm = max(8, request.radiusKm / 4)
        var anchors = [request.origin]

        for candidate in candidates {
            guard anchors.count < maxAnchorCount else { break }
            let isFarEnough = anchors.allSatisfy {
                distanceKmBetween(from: $0, to: candidate.location) >= minimumSpacingKm
            }
            if isFarEnough {
                anchors.append(candidate.location)
            }
        }

        return anchors
    }

    private func listings(from models: [ZucheModel], store: Store, request: SearchRequest) -> [RentalListing] {
        models.compactMap { model in
            guard model.bookFlag != false && model.havePriceFlag != false,
                  let dailyPrice = model.price
            else { return nil }

            return RentalListing(
                id: "car-inc-\(store.id)-\(model.modelId)",
                platform: .carInc,
                store: store,
                vehicleName: model.modelName,
                vehicleClass: model.modelDesc,
                basePrice: dailyPrice * Double(rentalDays(request)),
                platformFees: 0,
                insuranceFees: 0,
                oneWayFee: 0,
                sourceUrl: "https://m.zuche.com/#/rent/list",
                dataCompleteness: 0.88,
                warnings: [.partialPrice]
            )
        }
    }

    private func makeStore(from dept: ZucheDept, request: SearchRequest) -> Store? {
        guard let location = dept.location else { return nil }
        return Store(
            id: String(dept.deptId),
            platform: .carInc,
            name: dept.deptName,
            city: request.originLabel.contains("北京") ? "北京" : "",
            address: dept.deptAddress,
            location: location,
            distanceKm: distanceKmBetween(from: request.origin, to: location),
            hours: dept.workTime
        )
    }

    private func makeStore(from dept: ZucheDeptModels, request: SearchRequest) -> Store? {
        guard let location = dept.location else { return nil }
        return Store(
            id: String(dept.deptId),
            platform: .carInc,
            name: dept.deptName,
            city: request.originLabel.contains("北京") ? "北京" : "",
            address: dept.deptAddress,
            location: location,
            distanceKm: distanceKmBetween(from: request.origin, to: location),
            hours: dept.workTime
        )
    }

    private func status(_ kind: PlatformEvidenceStatusKind, _ message: String) -> PlatformEvidenceResult {
        PlatformEvidenceResult(
            platform: .carInc,
            status: PlatformEvidenceStatus(platform: .carInc, kind: kind, message: message, sourceUrl: "https://m.zuche.com/"),
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

    override init() {
        super.init()
        sessionObserver = NotificationCenter.default.addObserver(
            forName: EhiLoginSession.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
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
        do {
            let webView = try await readyWebView()
            let timeRange = platformQueryTimeRange(pickupDate: request.pickupAt, returnDate: request.returnAt)
            let payload = try JSONEncoder().encode(EhiBridgeRequest(request: request, timeRange: timeRange))
            let json = String(data: payload, encoding: .utf8) ?? "{}"
            let result = try await webView.callAsyncJavaScript(ehiSearchScript(json: json), arguments: [:], in: nil, contentWorld: .page)
            guard let resultString = result as? String else {
                return status(.parseFailed, "一嗨 API 桥接返回了无法识别的数据。")
            }
            let decoded = try JSONDecoder().decode(EhiBridgeResponse.self, from: Data(resultString.utf8))
            let kind = PlatformEvidenceStatusKind(rawValue: decoded.statusKind) ?? .parseFailed
            let listings = decoded.listings.map { $0.domainListing(request: request) }
            return PlatformEvidenceResult(
                platform: .ehi,
                status: PlatformEvidenceStatus(platform: .ehi, kind: kind, message: decoded.message, sourceUrl: decoded.sourceUrl),
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
        await EhiCookieVault.restore(into: dataStore.httpCookieStore)

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
        const responseBody = (resp) => (resp && resp.data && (resp.data.result ?? resp.data.data ?? resp.data)) ?? (resp && (resp.result ?? resp.data)) ?? resp ?? {};
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

        const cityListResp = await http.getEncrypt('/Address/City/List', {});
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
        let city = cities.find(candidate => {
          const name = cityName(candidate);
          const normalized = name.replace(/市$/, '');
          return name && (originLabel.includes(name) || originLabel.includes(normalized) || aliasMatchesCity(name));
        });
        if (!city) {
          city = cities
            .map(candidate => {
              const point = cityPoint(candidate);
              return point ? { city: candidate, distance: distanceKm(origin, point) } : null;
            })
            .filter(Boolean)
            .sort((a, b) => a.distance - b.distance)[0]?.city;
        }
        if (!city) {
          return JSON.stringify({ statusKind: 'unavailable', message: `一嗨没有识别到“${originLabel}”对应的可租城市。`, sourceUrl, listings: [] });
        }

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
        const storeResp = await http.getEncrypt('/Address/ReservationBooking/List', { cityId: cityId(city), operationTime: request.pickupTime });
        const storeResult = responseBody(storeResp);
        const storesById = {};
        for (const store of collectStores(storeResult)) {
          const id = String(store.id ?? store.managerId ?? store.storeId ?? store.manageStoreId);
          storesById[id] = store;
        }
        const stores = Object.values(storesById);
        const storeCandidates = stores
          .map(s => ({
            raw: s,
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
        const nearestStoreProbeLimit = 12;
        const candidates = hasVehicleQuery
          ? storeCandidates.filter(s => s.distanceKm <= request.radiusKm)
          : storeCandidates.slice(0, nearestStoreProbeLimit);
        if (!candidates.length) {
          const message = hasVehicleQuery ? '一嗨在当前范围内没有可用取车点。' : '一嗨当前城市没有可用取车点。';
          return JSON.stringify({ statusKind: 'unavailable', message, sourceUrl, listings: [] });
        }

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
        const verifyFailures = [];
        const queryErrors = [];
        let stockRequests = 0;
        let carsSeen = 0;
        let selectedBlankStoreId = null;
        for (const store of candidates) {
          if (!hasVehicleQuery && selectedBlankStoreId && store.id !== selectedBlankStoreId) break;
          const storeListings = [];
          const payload = {
            stockType: 1,
            whereFilter: null,
            pickupDto: { cityId: cityId(city), storeId: Number(store.id), operationTime: request.pickupTime, isService: false },
            pickupAddressDto: null,
            returnDto: { cityId: cityId(city), storeId: Number(store.id), operationTime: request.returnTime, isService: false },
            returnAddressDto: null,
            requestContext: {
              platform: util.getGD('platform'),
              platformSource: null,
              operatorId: null,
              userId: null,
              channelId: null,
              enterpriseId: null,
              optionTag: { isRecalculation: false, isChargeFee: false, choose: 3, isEnterprise: true, moduleIds: null }
            }
          };
          try {
            const verifyResp = await http.postEncrypt('/Verify/Step1', '', payload);
            const verify = verifyResp.data || verifyResp;
            if (!verify.isSuccess) {
              verifyFailures.push(`${store.name}: ${verify.message || '取还时间不可用'}`);
              continue;
            }
            stockRequests += 1;
            const stockResp = await http.postEncrypt('/Stock/Step2', '', payload);
            const code = stockResp.code ?? stockResp.status ?? stockResp.data?.code ?? stockResp.data?.status;
            if (code === 401) {
              return JSON.stringify({
                statusKind: 'login-required',
                message: `一嗨城市和门店 API 可匿名读取，但库存报价 /Stock/Step2 返回 401；请登录一嗨后重试。已识别 ${stores.length} 个门店。`,
                sourceUrl,
                listings: []
              });
            }
            const stockResult = responseBody(stockResp);
            const carItems = collectCarItems(stockResult);
            for (const item of carItems) {
              const car = item.carType || item.car || item.vehicle || item.model || item;
              const name = carName(item, car);
              if (!name) continue;
              carsSeen += 1;
              const basePrice = priceFrom(item, car);
              if (!basePrice) continue;
              const key = `${store.id}-${name}`;
              const listing = {
                id: `ehi-${store.id}-${carId(item, car, name)}`,
                storeId: store.id,
                storeName: store.name,
                city: cityName(city),
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
            for (const { key, listing } of storeListings) {
              if (!listingsByKey[key] || listingsByKey[key].basePrice > listing.basePrice) listingsByKey[key] = listing;
            }
            if (!hasVehicleQuery && storeListings.length) {
              selectedBlankStoreId = store.id;
              break;
            }
          } catch (error) {
            const message = String(error && (error.message || error.stack) || error);
            if (message.includes('401')) {
              return JSON.stringify({ statusKind: 'login-required', message: '一嗨库存报价接口返回 401，请登录一嗨后重试。', sourceUrl, listings: [] });
            }
            queryErrors.push(`${store.name}: ${message}`);
          }
        }
        const listings = Object.values(listingsByKey);
        if (!listings.length && !stockRequests && verifyFailures.length) {
          return JSON.stringify({
            statusKind: 'unavailable',
            message: `一嗨真实接口返回成功，但候选门店不满足取还时间：${verifyFailures.slice(0, 2).join('；')}`,
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
        return JSON.stringify({
          statusKind: listings.length ? 'ready' : 'unavailable',
          message: listings.length ? `已从一嗨 API 读取 ${listings.length} 个真实候选车型。` : '一嗨真实接口返回成功，但当前条件没有可订车型。',
          sourceUrl,
          listings
        });
        """
}

// MARK: - Shared Models

private struct ZucheResponse<Content: Decodable>: Decodable {
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

private struct EhiBridgeRequest: Encodable {
    let origin: GeoPoint
    let originLabel: String
    let originCityCandidates: [String]
    let pickupAt: String
    let returnAt: String
    let pickupTime: String
    let returnTime: String
    let rentalDays: Int
    let radiusKm: Double
    let vehicleQuery: String

    init(request: SearchRequest, timeRange: PlatformQueryTimeRange) {
        origin = request.origin
        originLabel = localizedChineseLocationText(request.originLabel)
        originCityCandidates = CarRentalOptimizer.originCityCandidates(from: request.originLabel)
        pickupAt = request.pickupAt
        returnAt = request.returnAt
        pickupTime = timeRange.pickupTime
        returnTime = timeRange.returnTime
        rentalDays = CarRentalOptimizer.rentalDays(request)
        radiusKm = request.radiusKm
        vehicleQuery = request.vehicleQuery
    }
}

private struct EhiBridgeResponse: Decodable {
    let statusKind: String
    let message: String
    let sourceUrl: String
    let listings: [EhiBridgeListing]
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

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
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
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    guard let pickup = formatter.date(from: request.pickupAt),
          let returnDate = formatter.date(from: request.returnAt)
    else { return 1 }
    let days = Calendar(identifier: .gregorian).dateComponents([.day], from: pickup, to: returnDate).day ?? 1
    return max(1, days)
}
