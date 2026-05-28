import Foundation
import SwiftUI

@MainActor
class SearchViewModel: ObservableObject {
    // MARK: - Published State

    @Published var request: SearchRequest = SearchRequest(
        origin: GeoPoint(lat: 39.9169, lng: 116.6462),
        originLabel: "北京通州",
        pickupAt: "2026-06-05T09:00",
        returnAt: "2026-06-07T18:00",
        returnMode: .sameStore,
        radiusKm: 100,
        vehicleQuery: "瑞虎8",
        platforms: [.ehi, .carInc]
    )

    @Published var results: [Recommendation] = []
    @Published var selectedId: String = ""
    @Published var isSearching: Bool = false
    @Published var status: String = "点击「开始比较」进行查询。"
    @Published var snapshotDiagnostics: [SnapshotDiagnostics] = []

    let platformSession = PlatformSessionService()

    // MARK: - Computed

    var selected: Recommendation? {
        results.first { $0.id == selectedId } ?? results.first
    }

    // MARK: - Actions

    func runSearch() async {
        isSearching = true
        results = []
        selectedId = ""
        snapshotDiagnostics = []
        status = "正在使用 Mock 数据计算打车/公共交通成本..."

        do {
            let adapters: [RentalAdapter] = [EhiMockAdapter(), CarIncMockAdapter()]
            let activeAdapters = adapters.filter { request.platforms.contains($0.platform) }

            var allListings: [RentalListing] = []
            for adapter in activeAdapters {
                let listings = await adapter.search(request: request)
                allListings.append(contentsOf: listings)
            }

            if allListings.isEmpty {
                status = "没有找到候选车辆。请调整搜索条件。"
                return
            }

            let nextResults = await rankRentalListings(request: request, listings: allListings, mapService: MockMapService())
            results = nextResults
            selectedId = nextResults.first?.id ?? ""
            status = formatSearchCompletionStatus(request: request, resultCount: nextResults.count)
        }

        isSearching = false
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

    func openPlatform(_ platform: PlatformId) async {
        _ = await platformSession.openPlatform(platform)
        await platformSession.refreshAuthStates()
        if let config = getPlatformConfig(platform) {
            status = "已打开\(config.label)官方页面。请登录，并在该窗口里按城市/日期/车型完成搜索。"
        }
    }

    func clearPlatform(_ platform: PlatformId) async {
        await platformSession.clearPlatform(platform)
        if let config = getPlatformConfig(platform) {
            status = "\(config.label)登录态已清除。"
        }
    }
}
