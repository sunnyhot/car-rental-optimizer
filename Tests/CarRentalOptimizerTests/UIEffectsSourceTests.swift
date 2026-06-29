import Foundation
import Testing

@Suite("UI effects source contracts")
struct UIEffectsSourceTests {
    @Test("Main view uses command center shell components")
    func mainViewUsesCommandCenterShellComponents() throws {
        let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/MainView.swift", encoding: .utf8)

        #expect(source.contains("WorkbenchBackground()"))
        #expect(source.contains("StatusLightRail(isActive: viewModel.isSearching"))
        #expect(source.contains("TaskStatusTile("))
        #expect(source.contains("tone: .active"))
        #expect(source.contains("tone: .success"))
        #expect(source.contains("tone: .warning"))
    }

    @Test("Search panel uses command console components")
    func searchPanelUsesCommandConsoleComponents() throws {
        let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/SearchPanelView.swift", encoding: .utf8)

        #expect(source.contains("QueryConsoleSection"))
        #expect(source.contains("PlatformSignalToggleButton"))
        #expect(source.contains("CompareCommandButton"))
        #expect(source.contains("ActionStatusRow("))
        #expect(source.contains("StatusLightRail(isActive: viewModel.isSearching"))
        #expect(source.contains("WorkbenchCard("))
    }
}
