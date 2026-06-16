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

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var request = AppDefaults.searchRequest
    @Published var results: [Recommendation] = []
    @Published var recommendationSortMode: RecommendationSortMode = .bestTotal
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
    @Published var originSuggestions: [AddressSuggestion] = []
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
    private let now: () -> Date
    private var hasRequestedInitialLocation = false
    private var originSuggestionRequestID = 0
    private var resolvedOriginLabel: String?
    private var latestSuccessfulResults: [Recommendation] = []
    private var latestSuccessfulSelectedId = ""

    init() {
        self.searchProvider = LiveRentalSearchService()
        self.geocoder = AppleAddressGeocoder()
        self.mapService = AppleMapService()
        self.currentLocationProvider = AppleCurrentLocationProvider()
        self.addressSuggestionProvider = AppleAddressSuggestionProvider()
        self.resolvedOriginLabel = AppDefaults.searchRequest.originLabel
        self.now = Date.init
    }

    init(snapshotProvider: PlatformSnapshotProviding) {
        self.searchProvider = SnapshotRentalSearchService(snapshotProvider: snapshotProvider)
        self.geocoder = CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin)
        self.mapService = EstimatedMapService()
        self.currentLocationProvider = UnavailableCurrentLocationProvider()
        self.addressSuggestionProvider = EmptyAddressSuggestionProvider()
        self.resolvedOriginLabel = AppDefaults.searchRequest.originLabel
        self.now = Date.init
    }

    init(
        searchProvider: RentalSearchProviding,
        geocoder: AddressGeocoding,
        mapService: MapService,
        currentLocationProvider: CurrentLocationProviding = UnavailableCurrentLocationProvider(),
        addressSuggestionProvider: AddressSuggestionProviding = EmptyAddressSuggestionProvider(),
        now: @escaping () -> Date = Date.init
    ) {
        self.searchProvider = searchProvider
        self.geocoder = geocoder
        self.mapService = mapService
        self.currentLocationProvider = currentLocationProvider
        self.addressSuggestionProvider = addressSuggestionProvider
        self.resolvedOriginLabel = AppDefaults.searchRequest.originLabel
        self.now = now
    }

    var selected: Recommendation? {
        results.first { $0.id == selectedId } ?? results.first
    }

    var displayedResults: [Recommendation] {
        switch recommendationSortMode {
        case .bestTotal:
            return results
        case .rentalSubtotal:
            return results.sorted {
                if $0.rentalTotal != $1.rentalTotal {
                    return $0.rentalTotal < $1.rentalTotal
                }
                return $0.bestTotal < $1.bestTotal
            }
        case .distance:
            return results.sorted {
                if $0.listing.store.distanceKm != $1.listing.store.distanceKm {
                    return $0.listing.store.distanceKm < $1.listing.store.distanceKm
                }
                return $0.bestTotal < $1.bestTotal
            }
        case .dataCompleteness:
            return results.sorted {
                if $0.listing.dataCompleteness != $1.listing.dataCompleteness {
                    return $0.listing.dataCompleteness > $1.listing.dataCompleteness
                }
                return $0.bestTotal < $1.bestTotal
            }
        }
    }

    var hasBlockingPreflightIssues: Bool {
        preflightIssues.contains { $0.severity == .blocking }
    }

    func refreshPreflightIssues() {
        preflightIssues = validateSearchPreflight(request).issues
    }

    func runSearch() async {
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
        let evidenceResults = await searchProvider.search(request: liveRequest)
        platformStatuses = evidenceResults.map(\.status)

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
        await runSearch()
    }

    func selectResult(_ id: String) {
        selectedId = id
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

    func applyDates(pickup: Date, returnDate: Date) {
        let normalized = AppDateRules.normalizedRange(pickup: pickup, returnDate: returnDate)
        request.pickupAt = AppDateRules.formatRequestDate(normalized.pickup)
        request.returnAt = AppDateRules.formatRequestDate(normalized.returnDate)
        refreshPreflightIssues()
    }

    func refreshCurrentLocationIfNeeded() async {
        guard !hasRequestedInitialLocation else { return }
        hasRequestedInitialLocation = true
        await refreshCurrentLocation()
    }

    func refreshCurrentLocation() async {
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
            originSuggestions = []
            originStatus = "已定位当前位置。"
            refreshPreflightIssues()
        } catch {
            originStatus = error.localizedDescription
        }
    }

    func updateOriginInput(_ value: String) async {
        request.originLabel = value
        resolvedOriginLabel = nil
        refreshPreflightIssues()
        originSuggestionRequestID += 1
        let requestID = originSuggestionRequestID

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            originSuggestions = []
            isLoadingOriginSuggestions = false
            isOriginSuggestionPanelVisible = false
            originStatus = "输入地址后会联想候选位置。"
            return
        }

        originSuggestions = []
        isLoadingOriginSuggestions = true
        isOriginSuggestionPanelVisible = true

        do {
            let suggestions = try await addressSuggestionProvider.suggestions(for: trimmed, near: request.origin)
            guard requestID == originSuggestionRequestID else { return }
            isLoadingOriginSuggestions = false
            originSuggestions = suggestions
            isOriginSuggestionPanelVisible = !suggestions.isEmpty
            originStatus = originSuggestions.isEmpty ? "没有找到匹配地址，可继续输入。" : "选择一个候选位置。"
        } catch {
            guard requestID == originSuggestionRequestID else { return }
            isLoadingOriginSuggestions = false
            originSuggestions = []
            isOriginSuggestionPanelVisible = false
            originStatus = "地址联想失败：\(error.localizedDescription)"
        }
    }

    func selectOriginSuggestion(_ suggestion: AddressSuggestion) async {
        originSuggestionRequestID += 1
        request.originLabel = suggestion.displayName
        request.origin = suggestion.point
        resolvedOriginLabel = request.originLabel
        originSuggestions = []
        isLoadingOriginSuggestions = false
        isOriginSuggestionPanelVisible = false
        originStatus = "已选择候选位置。"
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
