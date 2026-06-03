import Testing
@testable import CarRentalOptimizer

@Suite("App window layout")
struct AppWindowLayoutTests {
    @Test("Minimum window width covers the three-column workbench")
    func minimumWindowWidthCoversThreeColumnWorkbench() {
        let requiredWidth = AppWindowLayout.searchPanelMinimumWidth
            + AppWindowLayout.resultsPanelMinimumWidth
            + AppWindowLayout.detailPanelMinimumWidth
            + AppWindowLayout.splitHandleReserveWidth

        #expect(AppWindowLayout.minimumWidth >= requiredWidth)
        #expect(AppWindowLayout.defaultWidth >= AppWindowLayout.minimumWidth)
    }

    @Test("Minimum window height keeps the fixed search action visible")
    func minimumWindowHeightKeepsSearchActionVisible() {
        #expect(AppWindowLayout.minimumHeight >= 760)
        #expect(AppWindowLayout.defaultHeight >= AppWindowLayout.minimumHeight)
    }
}
