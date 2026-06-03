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
    @Published var status = "待查询：静默 API 准备就绪。"

    private let searchProvider: RentalSearchProviding
    private let geocoder: AddressGeocoding
    private let mapService: MapService

    init() {
        self.searchProvider = LiveRentalSearchService()
        self.geocoder = AppleAddressGeocoder()
        self.mapService = AppleMapService()
    }

    init(snapshotProvider: PlatformSnapshotProviding) {
        self.searchProvider = SnapshotRentalSearchService(snapshotProvider: snapshotProvider)
        self.geocoder = CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin)
        self.mapService = EstimatedMapService()
    }

    init(searchProvider: RentalSearchProviding, geocoder: AddressGeocoding, mapService: MapService) {
        self.searchProvider = searchProvider
        self.geocoder = geocoder
        self.mapService = mapService
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
            liveRequest.origin = try await geocoder.geocode(request.originLabel)
            request.origin = liveRequest.origin
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
