import Testing
@testable import CarRentalOptimizer

@Suite("App window layout")
struct AppWindowLayoutTests {
    @Test("Minimum window width covers navigation and the three-column workbench")
    func minimumWindowWidthCoversNavigationAndWorkbench() {
        let requiredWidth = AppWindowLayout.navigationRailWidth
            + AppWindowLayout.searchPanelMinimumWidth
            + AppWindowLayout.resultsPanelMinimumWidth
            + AppWindowLayout.detailPanelMinimumWidth
            + AppWindowLayout.splitHandleReserveWidth

        #expect(AppWindowLayout.navigationRailWidth == 56)
        #expect(AppWindowLayout.minimumWidth >= requiredWidth)
        #expect(AppWindowLayout.minimumWidth == 1280)
        #expect(AppWindowLayout.defaultWidth >= AppWindowLayout.minimumWidth)
    }

    @Test("Minimum window height keeps the fixed search action visible")
    func minimumWindowHeightKeepsSearchActionVisible() {
        #expect(AppWindowLayout.minimumHeight >= 760)
        #expect(AppWindowLayout.defaultHeight >= AppWindowLayout.minimumHeight)
    }
}
