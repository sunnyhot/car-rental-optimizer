import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("SearchViewModel")
@MainActor
struct SearchViewModelTests {
    @Test("Default search does not fabricate mock recommendations")
    func defaultSearchDoesNotFabricateMockRecommendations() async {
        let viewModel = SearchViewModel()

        await viewModel.runSearch()

        #expect(viewModel.results.isEmpty)
        #expect(viewModel.selectedId.isEmpty)
        #expect(viewModel.status.contains("官方页面"))
        #expect(viewModel.platformStatuses.contains { $0.kind == .waitingForEvidence })
    }

    @Test("Search ranks only parsed official evidence")
    func searchRanksOnlyParsedOfficialEvidence() async {
        let viewModel = SearchViewModel()
        viewModel.updateEvidenceText(
            """
            一嗨租车
            北京通州万达店
            奇瑞 瑞虎8 1.6T 自动
            租车基础价 ¥12880
            平台服务费 ¥42
            保险保障 ¥55
            """,
            for: .ehi
        )
        viewModel.updateEvidenceText("神州租车\n当前时间段暂未开放租车，请调整取还车日期", for: .carInc)

        await viewModel.runSearch()

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
