import Foundation
import CarRentalDomain
import Testing
@testable import CarRentalOptimizer

@Suite("SearchViewModel")
@MainActor
struct SearchViewModelTests {
    @Test("Default search does not fabricate mock recommendations when platform pages are empty")
    func defaultSearchDoesNotFabricateMockRecommendationsWhenPlatformPagesAreEmpty() async {
        let viewModel = SearchViewModel()

        await viewModel.runSearch()

        #expect(viewModel.results.isEmpty)
        #expect(viewModel.selectedId.isEmpty)
        #expect(viewModel.status.contains("官方页面"))
        #expect(!viewModel.status.contains("粘贴"))
        #expect(viewModel.platformStatuses.contains { $0.kind == .waitingForEvidence })
    }

    @Test("Search reads platform snapshots instead of waiting for pasted evidence")
    func searchReadsPlatformSnapshotsInsteadOfWaitingForPastedEvidence() async {
        let provider = StubPlatformSnapshotProvider(snapshots: [
            .ehi: PlatformPageSnapshot(
                platform: .ehi,
                title: "一嗨租车",
                url: "https://booking.1hai.cn/",
                text: """
                一嗨租车
                北京通州万达店
                奇瑞 瑞虎8 1.6T 自动
                租车基础价 ¥12880
                平台服务费 ¥42
                保险保障 ¥55
                """
            ),
            .carInc: PlatformPageSnapshot(
                platform: .carInc,
                title: "神州租车",
                url: "https://www.zuche.com/",
                text: "神州租车\n当前时间段暂未开放租车，请调整取还车日期"
            ),
        ])
        let viewModel = SearchViewModel(snapshotProvider: provider)

        await viewModel.runSearch()

        #expect(provider.requestedPlatforms == [.ehi, .carInc])
        #expect(viewModel.results.count == 1)
        #expect(viewModel.results[0].listing.platform == .ehi)
        #expect(viewModel.results[0].listing.store.name == "北京通州万达店")
        #expect(!viewModel.results.contains { $0.listing.platform == .carInc })
        #expect(viewModel.platformStatuses.contains { $0.platform == .carInc && $0.kind == .unavailable })
    }

    @Test("Date application stores day-only future dates")
    func applyDatesStoresDayOnlyFutureDates() {
        let viewModel = SearchViewModel()
        let calendar = Calendar(identifier: .gregorian)
        let pickup = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let returnDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11))!

        viewModel.applyDates(pickup: pickup, returnDate: returnDate)

        #expect(viewModel.request.pickupAt == "2026-09-01")
        #expect(viewModel.request.returnAt == "2026-10-11")
    }
}

@MainActor
private final class StubPlatformSnapshotProvider: PlatformSnapshotProviding {
    private let snapshots: [PlatformId: PlatformPageSnapshot]
    private(set) var requestedPlatforms: [PlatformId] = []

    init(snapshots: [PlatformId: PlatformPageSnapshot] = [:]) {
        self.snapshots = snapshots
    }

    func snapshot(for platform: PlatformId) async throws -> PlatformPageSnapshot {
        requestedPlatforms.append(platform)
        return snapshots[platform] ?? PlatformPageSnapshot(
            platform: platform,
            title: platform.label,
            url: officialPlatformURL(for: platform),
            text: ""
        )
    }
}
