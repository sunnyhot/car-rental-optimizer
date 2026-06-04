import CarRentalDomain
import Foundation
import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var request = AppDefaults.searchRequest
    @Published var results: [Recommendation] = []
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
    @Published var originSuggestions: [AddressSuggestion] = []
    @Published var originStatus = "正在获取当前位置。"
    @Published var status = "待查询：静默 API 准备就绪。"

    private let searchProvider: RentalSearchProviding
    private let geocoder: AddressGeocoding
    private let mapService: MapService
    private let currentLocationProvider: CurrentLocationProviding
    private let addressSuggestionProvider: AddressSuggestionProviding
    private var hasRequestedInitialLocation = false
    private var resolvedOriginLabel: String?

    init() {
        self.searchProvider = LiveRentalSearchService()
        self.geocoder = AppleAddressGeocoder()
        self.mapService = AppleMapService()
        self.currentLocationProvider = AppleCurrentLocationProvider()
        self.addressSuggestionProvider = AppleAddressSuggestionProvider()
        self.resolvedOriginLabel = AppDefaults.searchRequest.originLabel
    }

    init(snapshotProvider: PlatformSnapshotProviding) {
        self.searchProvider = SnapshotRentalSearchService(snapshotProvider: snapshotProvider)
        self.geocoder = CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin)
        self.mapService = EstimatedMapService()
        self.currentLocationProvider = UnavailableCurrentLocationProvider()
        self.addressSuggestionProvider = EmptyAddressSuggestionProvider()
        self.resolvedOriginLabel = AppDefaults.searchRequest.originLabel
    }

    init(
        searchProvider: RentalSearchProviding,
        geocoder: AddressGeocoding,
        mapService: MapService,
        currentLocationProvider: CurrentLocationProviding = UnavailableCurrentLocationProvider(),
        addressSuggestionProvider: AddressSuggestionProviding = EmptyAddressSuggestionProvider()
    ) {
        self.searchProvider = searchProvider
        self.geocoder = geocoder
        self.mapService = mapService
        self.currentLocationProvider = currentLocationProvider
        self.addressSuggestionProvider = addressSuggestionProvider
        self.resolvedOriginLabel = AppDefaults.searchRequest.originLabel
    }

    var selected: Recommendation? {
        results.first { $0.id == selectedId } ?? results.first
    }

    func runSearch() async {
        isSearching = true
        results = []
        selectedId = ""
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
            platformStatuses = request.platforms.map {
                PlatformEvidenceStatus(platform: $0, kind: .parseFailed, message: "地址解析失败，暂未调用\($0.label)。", sourceUrl: officialPlatformURL(for: $0))
            }
            return
        }

        let evidenceResults = await searchProvider.search(request: liveRequest)
        platformStatuses = evidenceResults.map(\.status)

        let listings = evidenceResults.flatMap(\.listings)
        guard !listings.isEmpty else {
            status = formatNoAPIListingsStatus(evidenceResults)
            return
        }

        let recommendations = await rankRentalListings(
            request: liveRequest,
            listings: listings,
            mapService: mapService
        )

        results = recommendations
        selectedId = recommendations.first?.id ?? ""
        status = formatSearchCompletionStatus(request: liveRequest, resultCount: recommendations.count)
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
    }

    func refreshCurrentLocationIfNeeded() async {
        guard !hasRequestedInitialLocation else { return }
        hasRequestedInitialLocation = true
        await refreshCurrentLocation()
    }

    func refreshCurrentLocation() async {
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
        } catch {
            originStatus = error.localizedDescription
        }
    }

    func updateOriginInput(_ value: String) async {
        request.originLabel = value
        resolvedOriginLabel = nil

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            originSuggestions = []
            isLoadingOriginSuggestions = false
            originStatus = "输入地址后会联想候选位置。"
            return
        }

        isLoadingOriginSuggestions = true
        defer {
            isLoadingOriginSuggestions = false
        }

        do {
            originSuggestions = try await addressSuggestionProvider.suggestions(for: trimmed, near: request.origin)
            originStatus = originSuggestions.isEmpty ? "没有找到匹配地址，可继续输入。" : "选择一个候选位置。"
        } catch {
            originSuggestions = []
            originStatus = "地址联想失败：\(error.localizedDescription)"
        }
    }

    func selectOriginSuggestion(_ suggestion: AddressSuggestion) async {
        request.originLabel = suggestion.displayName
        request.origin = suggestion.point
        resolvedOriginLabel = request.originLabel
        originSuggestions = []
        originStatus = "已选择候选位置。"
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
