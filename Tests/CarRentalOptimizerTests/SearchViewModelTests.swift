import Testing
@testable import CarRentalOptimizer

@Suite("SearchViewModel")
@MainActor
struct SearchViewModelTests {
    @Test("Default search returns ranked recommendations")
    func defaultSearchReturnsRankedRecommendations() async {
        let viewModel = SearchViewModel()

        await viewModel.runSearch()

        #expect(!viewModel.results.isEmpty)
        #expect(viewModel.selectedId == viewModel.results.first?.listing.id)
        #expect(viewModel.status.contains("找到"))
    }
}
