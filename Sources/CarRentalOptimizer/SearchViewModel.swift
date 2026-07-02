import CarRentalDomain
import Foundation
import SwiftUI

enum SearchProgressPhase: Equatable {
    case idle
    case resolvingLocation
    case queryingPlatforms
    case rankingRoutes
    case completed
    case failed

    var title: String {
        switch self {
        case .idle:
            return "待查询"
        case .resolvingLocation:
            return "解析位置"
        case .queryingPlatforms:
            return "读取平台"
        case .rankingRoutes:
            return "计算路线"
        case .completed:
            return "查询完成"
        case .failed:
            return "查询失败"
        }
    }

    var message: String {
        switch self {
        case .idle:
            return "填写条件后开始比较。"
        case .resolvingLocation:
            return "正在把当前位置转换为坐标。"
        case .queryingPlatforms:
            return "正在静默调用一嗨和神州官方接口。"
        case .rankingRoutes:
            return "正在合并租车价格和到店路线成本。"
        case .completed:
            return "已完成本次比较。"
        case .failed:
            return "本次比较未完成，可调整条件后重试。"
        }
    }
}

enum RecommendationSortMode: String, CaseIterable, Identifiable {
    case bestTotal
    case rentalSubtotal
    case distance
    case dataCompleteness

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bestTotal:
            return "总成本"
        case .rentalSubtotal:
            return "租车价"
        case .distance:
            return "距离"
        case .dataCompleteness:
            return "完整度"
        }
    }
}

enum RecommendationPlatformFilter: String, CaseIterable, Identifiable {
    case all
    case ehi
    case carInc

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "全部"
        case .ehi:
            return "一嗨"
        case .carInc:
            return "神州"
        }
    }

    var platform: PlatformId? {
        switch self {
        case .all:
            return nil
        case .ehi:
            return .ehi
        case .carInc:
            return .carInc
        }
    }
}

enum RecommendationVehicleClassFilter: String, CaseIterable, Identifiable {
    case all
    case sedan
    case suv
    case mpv
    case newEnergy
    case unspecified

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "全部"
        case .sedan:
            return "轿车"
        case .suv:
            return "SUV"
        case .mpv:
            return "MPV"
        case .newEnergy:
            return "新能源"
        case .unspecified:
            return "未指定"
        }
    }
}

enum RecommendationBudgetFilter: String, CaseIterable, Identifiable {
    case all
    case upTo1500
    case upTo2000
    case upTo3000

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "不限"
        case .upTo1500:
            return "≤1500"
        case .upTo2000:
            return "≤2000"
        case .upTo3000:
            return "≤3000"
        }
    }

    var maxTotalCost: Double? {
        switch self {
        case .all:
            return nil
        case .upTo1500:
            return 1_500
        case .upTo2000:
            return 2_000
        case .upTo3000:
            return 3_000
        }
    }
}

enum RecommendationDistanceFilter: String, CaseIterable, Identifiable {
    case all
    case within1
    case within3
    case within10

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "不限"
        case .within1:
            return "≤1km"
        case .within3:
            return "≤3km"
        case .within10:
            return "≤10km"
        }
    }

    var maxDistanceKm: Double? {
        switch self {
        case .all:
            return nil
        case .within1:
            return 1
        case .within3:
            return 3
        case .within10:
            return 10
        }
    }
}

struct RecommendationFilterState: Equatable {
    var platform: RecommendationPlatformFilter = .all
    var vehicleClass: RecommendationVehicleClassFilter = .all
    var maxTotalCost: RecommendationBudgetFilter = .all
    var maxDistance: RecommendationDistanceFilter = .all
    var hideIncompleteFees = false
    var deduplicateByStore = false
    var deduplicateByVehicle = false

    static let empty = RecommendationFilterState()

    var isActive: Bool {
        self != .empty
    }
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var request = AppDefaults.searchRequest
    @Published var results: [Recommendation] = []
    @Published var recommendationSortMode: RecommendationSortMode = .bestTotal
    @Published var recommendationFilter = RecommendationFilterState()
    @Published var platformStatuses: [PlatformEvidenceStatus] = AppDefaults.searchRequest.platforms.map {
        PlatformEvidenceStatus(
            platform: $0,
            kind: .waitingForEvidence,
            message: "等待静默调用\($0.label) API。",
            sourceUrl: officialPlatformURL(for: $0)
        )
    }
    @Published var selectedId = ""
    @Published var isSearching = false
    @Published var isLocatingOrigin = false
    @Published var isLoadingOriginSuggestions = false
    @Published var isOriginSuggestionPanelVisible = false
    @Published var originSuggestions: [OriginSuggestion] = []
    @Published var originStatus = "正在获取当前位置。"
    @Published var status = "待查询：静默 API 准备就绪。"
    @Published var searchProgressPhase: SearchProgressPhase = .idle
    @Published var preflightIssues: [SearchPreflightIssue] = []
    @Published var searchDiagnosticSummary: SearchDiagnosticSummary = .empty
    @Published var isShowingStaleResults = false
    @Published var retainedResultsNotice: RetainedResultsNotice?
    @Published var lastSuccessfulSearchAt: Date?

    private let searchProvider: RentalSearchProviding
    private let geocoder: AddressGeocoding
    private let mapService: MapService
    private let currentLocationProvider: CurrentLocationProviding
    private let addressSuggestionProvider: AddressSuggestionProviding
    private let railStationSuggestionProvider: RailStationSuggestionProviding
    private let initialLocationRetryDelayNanoseconds: UInt64
    private let now: () -> Date
    private var hasRequestedInitialLocation = false
    private var originSuggestionRequestID = 0
    private var resolvedOriginLabel: String?
    private var requiresOriginCandidateSelection = false
    private var latestSuccessfulResults: [Recommendation] = []
    private var latestSuccessfulSelectedId = ""
    private var latestEvidenceRequest: SearchRequest?
    private var latestEvidenceResultsByPlatform: [PlatformId: PlatformEvidenceResult] = [:]

    init() {
        self.searchProvider = LiveRentalSearchService()
        self.geocoder = AppleAddressGeocoder()
        self.mapService = AppleMapService()
        self.currentLocationProvider = AppleCurrentLocationProvider()
        self.addressSuggestionProvider = AppleAddressSuggestionProvider()
        self.railStationSuggestionProvider = AppleRailStationSuggestionProvider()
        self.initialLocationRetryDelayNanoseconds = defaultInitialLocationRetryDelayNanoseconds
        self.resolvedOriginLabel = AppDefaults.searchRequest.originLabel
        self.now = Date.init
    }

    init(snapshotProvider: PlatformSnapshotProviding) {
        self.searchProvider = SnapshotRentalSearchService(snapshotProvider: snapshotProvider)
        self.geocoder = CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin)
        self.mapService = EstimatedMapService()
        self.currentLocationProvider = UnavailableCurrentLocationProvider()
        self.addressSuggestionProvider = EmptyAddressSuggestionProvider()
        self.railStationSuggestionProvider = EmptyRailStationSuggestionProvider()
        self.initialLocationRetryDelayNanoseconds = 0
        self.resolvedOriginLabel = AppDefaults.searchRequest.originLabel
        self.now = Date.init
    }

    init(
        searchProvider: RentalSearchProviding,
        geocoder: AddressGeocoding,
        mapService: MapService,
        currentLocationProvider: CurrentLocationProviding = UnavailableCurrentLocationProvider(),
        addressSuggestionProvider: AddressSuggestionProviding = EmptyAddressSuggestionProvider(),
        railStationSuggestionProvider: RailStationSuggestionProviding = EmptyRailStationSuggestionProvider(),
        initialLocationRetryDelayNanoseconds: UInt64 = defaultInitialLocationRetryDelayNanoseconds,
        now: @escaping () -> Date = Date.init
    ) {
        self.searchProvider = searchProvider
        self.geocoder = geocoder
        self.mapService = mapService
        self.currentLocationProvider = currentLocationProvider
        self.addressSuggestionProvider = addressSuggestionProvider
        self.railStationSuggestionProvider = railStationSuggestionProvider
        self.initialLocationRetryDelayNanoseconds = initialLocationRetryDelayNanoseconds
        self.resolvedOriginLabel = AppDefaults.searchRequest.originLabel
        self.now = now
    }

    var selected: Recommendation? {
        displayedResults.first { $0.id == selectedId } ?? displayedResults.first
    }

    var displayedResults: [Recommendation] {
        let filtered = filteredRecommendations(results)
        return sortedRecommendations(filtered)
    }

    var filteredResultCount: Int {
        displayedResults.count
    }

    var hasActiveRecommendationFilters: Bool {
        recommendationFilter.isActive
    }

    private func sortedRecommendations(_ recommendations: [Recommendation]) -> [Recommendation] {
        switch recommendationSortMode {
        case .bestTotal:
            return recommendations
        case .rentalSubtotal:
            return recommendations.sorted {
                if $0.rentalTotal != $1.rentalTotal {
                    return $0.rentalTotal < $1.rentalTotal
                }
                return $0.bestTotal < $1.bestTotal
            }
        case .distance:
            return recommendations.sorted {
                if $0.listing.store.distanceKm != $1.listing.store.distanceKm {
                    return $0.listing.store.distanceKm < $1.listing.store.distanceKm
                }
                return $0.bestTotal < $1.bestTotal
            }
        case .dataCompleteness:
            return recommendations.sorted {
                if $0.listing.dataCompleteness != $1.listing.dataCompleteness {
                    return $0.listing.dataCompleteness > $1.listing.dataCompleteness
                }
                return $0.bestTotal < $1.bestTotal
            }
        }
    }

    private func filteredRecommendations(_ recommendations: [Recommendation]) -> [Recommendation] {
        var filtered = recommendations.filter(matchesRecommendationFilter)
        if recommendationFilter.deduplicateByStore {
            filtered = deduplicateRecommendations(filtered, key: storeDeduplicationKey)
        }
        if recommendationFilter.deduplicateByVehicle {
            filtered = deduplicateRecommendations(filtered, key: vehicleDeduplicationKey)
        }
        return filtered
    }

    private func matchesRecommendationFilter(_ recommendation: Recommendation) -> Bool {
        if let platform = recommendationFilter.platform.platform, recommendation.listing.platform != platform {
            return false
        }

        switch recommendationFilter.vehicleClass {
        case .all:
            break
        case .sedan, .suv, .mpv, .newEnergy, .unspecified:
            guard detectedVehicleClass(for: recommendation) == recommendationFilter.vehicleClass else { return false }
        }

        if let maxTotalCost = recommendationFilter.maxTotalCost.maxTotalCost, recommendation.bestTotal > maxTotalCost {
            return false
        }

        if let maxDistanceKm = recommendationFilter.maxDistance.maxDistanceKm, recommendation.listing.store.distanceKm > maxDistanceKm {
            return false
        }

        if recommendationFilter.hideIncompleteFees, hasIncompleteFees(recommendation) {
            return false
        }

        return true
    }

    private func deduplicateRecommendations(
        _ recommendations: [Recommendation],
        key: (Recommendation) -> String
    ) -> [Recommendation] {
        var orderedKeys: [String] = []
        var bestByKey: [String: Recommendation] = [:]
        for recommendation in recommendations {
            let key = key(recommendation)
            if let current = bestByKey[key] {
                if isLowerCost(recommendation, than: current) {
                    bestByKey[key] = recommendation
                }
            } else {
                orderedKeys.append(key)
                bestByKey[key] = recommendation
            }
        }
        return orderedKeys.compactMap { bestByKey[$0] }
    }

    private func isLowerCost(_ lhs: Recommendation, than rhs: Recommendation) -> Bool {
        if lhs.bestTotal != rhs.bestTotal {
            return lhs.bestTotal < rhs.bestTotal
        }
        if lhs.rentalTotal != rhs.rentalTotal {
            return lhs.rentalTotal < rhs.rentalTotal
        }
        if lhs.listing.store.distanceKm != rhs.listing.store.distanceKm {
            return lhs.listing.store.distanceKm < rhs.listing.store.distanceKm
        }
        return lhs.id < rhs.id
    }

    private func storeDeduplicationKey(_ recommendation: Recommendation) -> String {
        let store = recommendation.listing.store
        let stableStoreKey = store.id.isEmpty ? "\(store.name)|\(store.address)" : store.id
        return "\(recommendation.listing.platform.rawValue)|\(normalizedRecommendationKey(stableStoreKey))"
    }

    private func vehicleDeduplicationKey(_ recommendation: Recommendation) -> String {
        normalizedRecommendationKey(recommendation.listing.vehicleName)
    }

    private func detectedVehicleClass(for recommendation: Recommendation) -> RecommendationVehicleClassFilter {
        let listing = recommendation.listing
        let combined = "\(listing.vehicleClass) \(listing.vehicleName) \(recommendation.match.label)"
        let normalized = combined.lowercased()

        if listing.vehicleName.contains("未指定")
            || listing.vehicleClass.contains("未指定")
            || recommendation.match.kind == .notSpecified {
            return .unspecified
        }

        if normalized.contains("新能源")
            || normalized.contains("纯电")
            || normalized.contains("电动")
            || normalized.contains("插电")
            || normalized.contains("混动")
            || normalized.contains(" ev")
            || normalized.hasSuffix("ev")
            || normalized.contains("dm-i") {
            return .newEnergy
        }

        if normalized.contains("suv") || normalized.contains("越野") {
            return .suv
        }

        if normalized.contains("mpv")
            || normalized.contains("商务")
            || normalized.contains("gl8")
            || normalized.contains("奥德赛")
            || normalized.contains("艾力绅") {
            return .mpv
        }

        if normalized.contains("轿车")
            || normalized.contains("紧凑型车")
            || normalized.contains("中型车")
            || normalized.contains("中大型车")
            || normalized.contains("大型车")
            || normalized.contains("小型车")
            || normalized.contains("三厢")
            || normalized.contains("两厢")
            || normalized.contains("sedan")
            || normalized.contains("朗逸")
            || normalized.contains("轩逸")
            || normalized.contains("科鲁泽")
            || normalized.contains("卡罗拉")
            || normalized.contains("速腾")
            || normalized.contains("宝来")
            || normalized.contains("迈腾")
            || normalized.contains("帕萨特")
            || normalized.contains("凯美瑞")
            || normalized.contains("雅阁")
            || normalized.contains("天籁") {
            return .sedan
        }

        return .unspecified
    }

    private func normalizedRecommendationKey(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    private func hasIncompleteFees(_ recommendation: Recommendation) -> Bool {
        let warnings = recommendation.listing.warnings + recommendation.warnings
        return recommendation.listing.dataCompleteness < 0.9 || warnings.contains(.partialPrice)
    }

    var hasBlockingPreflightIssues: Bool {
        preflightIssues.contains { $0.severity == .blocking }
    }

    func refreshPreflightIssues() {
        preflightIssues = validateSearchPreflight(request).issues
    }

    func runSearch() async {
        await performSearch(retryingFailedPlatformsOnly: false)
    }

    private func performSearch(retryingFailedPlatformsOnly: Bool) async {
        dismissOriginSuggestions()
        refreshPreflightIssues()
        if hasBlockingPreflightIssues {
            searchProgressPhase = .failed
            if let blockingIssue = preflightIssues.first(where: { $0.severity == .blocking }) {
                status = "\(blockingIssue.title)：\(blockingIssue.message)"
            } else {
                status = "搜索条件不完整。"
            }
            searchDiagnosticSummary = .empty
            return
        }

        isSearching = true
        isShowingStaleResults = false
        retainedResultsNotice = nil
        results = []
        selectedId = ""
        searchProgressPhase = .resolvingLocation
        status = "正在解析当前位置，并静默调用平台 API..."

        defer {
            isSearching = false
        }

        var liveRequest = request
        do {
            if resolvedOriginLabel == request.originLabel {
                liveRequest.origin = request.origin
            } else {
                liveRequest.origin = try await geocoder.geocode(request.originLabel)
                request.origin = liveRequest.origin
                resolvedOriginLabel = request.originLabel
            }
        } catch {
            status = "当前位置解析失败：\(error.localizedDescription)"
            searchProgressPhase = .failed
            platformStatuses = request.platforms.map {
                PlatformEvidenceStatus(platform: $0, kind: .parseFailed, message: "地址解析失败，暂未调用\($0.label)。", sourceUrl: officialPlatformURL(for: $0))
            }
            searchDiagnosticSummary = SearchDiagnosticSummary.make(
                evidenceResults: platformStatuses.map {
                    PlatformEvidenceResult(platform: $0.platform, status: $0, listings: [])
                },
                recommendations: []
            )
            restoreLatestSuccessfulResultsIfAvailable()
            return
        }

        searchProgressPhase = .queryingPlatforms
        let evidenceResults = await searchEvidenceResults(
            request: liveRequest,
            retryingFailedPlatformsOnly: retryingFailedPlatformsOnly
        )
        recordEvidenceResults(evidenceResults, request: liveRequest)
        platformStatuses = displayPlatformStatuses(from: evidenceResults)

        let listings = evidenceResults.flatMap(\.listings)
        guard !listings.isEmpty else {
            status = formatNoAPIListingsStatus(evidenceResults)
            searchDiagnosticSummary = SearchDiagnosticSummary.make(evidenceResults: evidenceResults, recommendations: [])
            searchProgressPhase = .completed
            restoreLatestSuccessfulResultsIfAvailable()
            return
        }

        searchProgressPhase = .rankingRoutes
        let recommendations = await rankRentalListings(
            request: liveRequest,
            listings: listings,
            mapService: mapService
        )

        results = recommendations
        selectedId = recommendations.first?.id ?? ""
        recordSuccessfulResults(recommendations)
        searchDiagnosticSummary = SearchDiagnosticSummary.make(evidenceResults: evidenceResults, recommendations: recommendations)
        status = formatSearchCompletionStatus(request: liveRequest, resultCount: recommendations.count)
        searchProgressPhase = .completed
    }

    func retrySearch() async {
        await performSearch(retryingFailedPlatformsOnly: true)
    }

    func selectResult(_ id: String) {
        selectedId = id
    }

    func clearRecommendationFilters() {
        recommendationFilter = .empty
    }

    func togglePlatform(_ platform: PlatformId) {
        if request.platforms.contains(platform) {
            if request.platforms.count > 1 {
                request.platforms.removeAll { $0 == platform }
            }
        } else {
            request.platforms.append(platform)
        }

        if !results.isEmpty {
            status = "搜索条件已变更，点击「开始比较」重新计算总成本。"
        }
        refreshPreflightIssues()
    }

    func platformStatus(for platform: PlatformId) -> PlatformEvidenceStatus {
        platformStatuses.first { $0.platform == platform } ?? PlatformEvidenceStatus(
            platform: platform,
            kind: .waitingForEvidence,
            message: "等待静默调用\(platform.label) API。",
            sourceUrl: officialPlatformURL(for: platform)
        )
    }

    private func displayPlatformStatuses(from evidenceResults: [PlatformEvidenceResult]) -> [PlatformEvidenceStatus] {
        evidenceResults.map { result in
            guard result.status.kind == .ready,
                  result.listings.contains(where: { $0.platform == result.platform && $0.warnings.contains(.loginRequired) }) else {
                return result.status
            }

            return PlatformEvidenceStatus(
                platform: result.platform,
                kind: .loginRequired,
                message: loginRequiredMessage(for: result.platform),
                sourceUrl: result.status.sourceUrl
            )
        }
    }

    private func searchEvidenceResults(
        request liveRequest: SearchRequest,
        retryingFailedPlatformsOnly: Bool
    ) async -> [PlatformEvidenceResult] {
        guard retryingFailedPlatformsOnly,
              latestEvidenceRequest == liveRequest
        else {
            return await searchProvider.search(request: liveRequest)
        }

        let previousResults = liveRequest.platforms.compactMap { latestEvidenceResultsByPlatform[$0] }
        let platformsToRetry = platformsNeedingRetry(from: previousResults, request: liveRequest)
        guard !platformsToRetry.isEmpty,
              platformsToRetry.count < liveRequest.platforms.count
        else {
            return await searchProvider.search(request: liveRequest)
        }

        var retryRequest = liveRequest
        retryRequest.platforms = platformsToRetry
        let retriedResults = await searchProvider.search(request: retryRequest)
        return mergeEvidenceResults(previous: previousResults, updates: retriedResults, platforms: liveRequest.platforms)
    }

    private func platformsNeedingRetry(
        from evidenceResults: [PlatformEvidenceResult],
        request: SearchRequest
    ) -> [PlatformId] {
        let resultsByPlatform = evidenceResultsByPlatform(evidenceResults)
        return request.platforms.filter { platform in
            guard let result = resultsByPlatform[platform] else { return true }
            return result.listings.isEmpty
        }
    }

    private func mergeEvidenceResults(
        previous: [PlatformEvidenceResult],
        updates: [PlatformEvidenceResult],
        platforms: [PlatformId]
    ) -> [PlatformEvidenceResult] {
        var resultsByPlatform = evidenceResultsByPlatform(previous)
        for update in updates {
            resultsByPlatform[update.platform] = update
        }
        return platforms.compactMap { resultsByPlatform[$0] }
    }

    private func recordEvidenceResults(_ evidenceResults: [PlatformEvidenceResult], request: SearchRequest) {
        latestEvidenceRequest = request
        latestEvidenceResultsByPlatform = evidenceResultsByPlatform(evidenceResults)
    }

    private func evidenceResultsByPlatform(_ evidenceResults: [PlatformEvidenceResult]) -> [PlatformId: PlatformEvidenceResult] {
        var resultsByPlatform: [PlatformId: PlatformEvidenceResult] = [:]
        for evidenceResult in evidenceResults {
            resultsByPlatform[evidenceResult.platform] = evidenceResult
        }
        return resultsByPlatform
    }

    private func loginRequiredMessage(for platform: PlatformId) -> String {
        switch platform {
        case .ehi:
            return "一嗨已返回部分信息；登录一嗨后可确认完整报价并重新比较。"
        case .carInc:
            return "神州已返回车辆租赁费；登录神州后可补全确认页基础服务费并重新比较。"
        }
    }

    func applyDates(pickup: Date, returnDate: Date) {
        let normalized = AppDateRules.normalizedRange(pickup: pickup, returnDate: returnDate)
        request.pickupAt = AppDateRules.formatRequestDate(normalized.pickup)
        request.returnAt = AppDateRules.formatRequestDate(normalized.returnDate)
        refreshPreflightIssues()
    }

    func refreshCurrentLocationIfNeeded() async {
        guard !hasRequestedInitialLocation else { return }
        hasRequestedInitialLocation = true
        await refreshInitialCurrentLocationWithRetry()
    }

    func startInitialCurrentLocationRefresh() {
        guard !hasRequestedInitialLocation else { return }
        hasRequestedInitialLocation = true
        Task { [weak self] in
            await self?.refreshInitialCurrentLocationWithRetry()
        }
    }

    func refreshCurrentLocation() async {
        _ = await refreshCurrentLocationOutcome()
    }

    private func refreshInitialCurrentLocationWithRetry() async {
        let outcome = await refreshCurrentLocationOutcome()
        guard outcome.shouldRetry else { return }

        originStatus = "正在重新获取当前位置。"
        if initialLocationRetryDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: initialLocationRetryDelayNanoseconds)
        }
        guard !Task.isCancelled else { return }
        _ = await refreshCurrentLocationOutcome()
    }

    private func refreshCurrentLocationOutcome() async -> CurrentLocationRefreshOutcome {
        dismissOriginSuggestions()
        isLocatingOrigin = true
        originStatus = "正在获取当前位置。"
        defer {
            isLocatingOrigin = false
        }

        do {
            let location = try await currentLocationProvider.currentLocation()
            request.originLabel = location.label
            request.origin = location.point
            resolvedOriginLabel = location.label
            requiresOriginCandidateSelection = false
            originSuggestions = []
            originStatus = "已定位当前位置。"
            refreshPreflightIssues()
            return .success
        } catch {
            let normalizedError = CurrentLocationError.normalized(error)
            originStatus = normalizedError.localizedDescription
            return CurrentLocationError.isRetryable(normalizedError) ? .retryableFailure : .blockedFailure
        }
    }

    func updateOriginInput(_ value: String) async {
        request.originLabel = value
        resolvedOriginLabel = nil
        requiresOriginCandidateSelection = false
        refreshPreflightIssues()
        originSuggestionRequestID += 1
        let requestID = originSuggestionRequestID

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            originSuggestions = []
            isLoadingOriginSuggestions = false
            isOriginSuggestionPanelVisible = false
            originStatus = "输入地址、城市或车站后会联想候选位置。"
            return
        }

        originSuggestions = []
        requiresOriginCandidateSelection = isKnownCityLevelOrigin(trimmed)
        isLoadingOriginSuggestions = true
        isOriginSuggestionPanelVisible = true
        refreshPreflightIssues()

        let railResult = await loadRailStationSuggestions(for: trimmed)
        let addressResult = await loadAddressSuggestions(for: trimmed)
        guard requestID == originSuggestionRequestID else { return }

        isLoadingOriginSuggestions = false
        let railSuggestions = (try? railResult.get()) ?? []
        let addressSuggestions = (try? addressResult.get()) ?? []
        originSuggestions = mergeOriginSuggestions(railStations: railSuggestions, addresses: addressSuggestions)
        requiresOriginCandidateSelection = isKnownCityLevelOrigin(trimmed) || !railSuggestions.isEmpty
        refreshPreflightIssues()

        isOriginSuggestionPanelVisible = !originSuggestions.isEmpty
        if !originSuggestions.isEmpty {
            originStatus = "选择一个候选位置。"
        } else if railResult.isFailure && addressResult.isFailure {
            originStatus = "位置联想失败，请输入更具体的车站或地址。"
        } else {
            originStatus = "没有找到匹配位置，可继续输入。"
        }
    }

    private func loadRailStationSuggestions(for query: String) async -> Result<[RailStationSuggestion], Error> {
        do {
            return .success(try await railStationSuggestionProvider.stationSuggestions(for: query, near: request.origin))
        } catch {
            return .failure(error)
        }
    }

    private func loadAddressSuggestions(for query: String) async -> Result<[AddressSuggestion], Error> {
        do {
            return .success(try await addressSuggestionProvider.suggestions(for: query, near: request.origin))
        } catch {
            return .failure(error)
        }
    }

    func selectOriginSuggestion(_ suggestion: OriginSuggestion) async {
        originSuggestionRequestID += 1
        request.originLabel = suggestion.displayName
        request.origin = suggestion.point
        resolvedOriginLabel = request.originLabel
        requiresOriginCandidateSelection = false
        originSuggestions = []
        isLoadingOriginSuggestions = false
        isOriginSuggestionPanelVisible = false
        originStatus = suggestion.fallbackNote ?? "已选择候选位置。"
        refreshPreflightIssues()
    }

    func dismissOriginSuggestions() {
        originSuggestionRequestID += 1
        originSuggestions = []
        isLoadingOriginSuggestions = false
        isOriginSuggestionPanelVisible = false
    }

    private func recordSuccessfulResults(_ recommendations: [Recommendation]) {
        latestSuccessfulResults = recommendations
        latestSuccessfulSelectedId = recommendations.first?.id ?? ""
        lastSuccessfulSearchAt = now()
        isShowingStaleResults = false
        retainedResultsNotice = nil
    }

    private func restoreLatestSuccessfulResultsIfAvailable() {
        guard !latestSuccessfulResults.isEmpty, let lastSuccessfulSearchAt else {
            results = []
            selectedId = ""
            isShowingStaleResults = false
            retainedResultsNotice = nil
            return
        }

        results = latestSuccessfulResults
        selectedId = latestSuccessfulSelectedId
        isShowingStaleResults = true
        retainedResultsNotice = RetainedResultsNotice.make(lastSuccessfulSearchAt: lastSuccessfulSearchAt)
    }
}

private let defaultInitialLocationRetryDelayNanoseconds: UInt64 = 500_000_000

private enum CurrentLocationRefreshOutcome {
    case success
    case retryableFailure
    case blockedFailure

    var shouldRetry: Bool {
        self == .retryableFailure
    }
}

private extension Result {
    var isFailure: Bool {
        if case .failure = self {
            return true
        }
        return false
    }
}

private struct UnavailableCurrentLocationProvider: CurrentLocationProviding {
    func currentLocation() async throws -> ResolvedLocation {
        throw CurrentLocationError.unavailable
    }
}

private struct EmptyAddressSuggestionProvider: AddressSuggestionProviding {
    func suggestions(for query: String, near origin: GeoPoint?) async throws -> [AddressSuggestion] {
        []
    }
}

func officialPlatformURL(for platform: PlatformId) -> String {
    switch platform {
    case .ehi:
        return "https://www.1hai.cn/"
    case .carInc:
        return "https://www.zuche.com/"
    }
}

private func formatNoAPIListingsStatus(_ evidenceResults: [PlatformEvidenceResult]) -> String {
    let messages = evidenceResults.map(\.status.message)
    return messages.joined(separator: "；")
}
