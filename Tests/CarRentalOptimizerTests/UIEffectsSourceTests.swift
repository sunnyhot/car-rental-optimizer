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

    @Test("Result panel uses signal cards and staged loading")
    func resultPanelUsesSignalCardsAndStagedLoading() throws {
        let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/ResultPanelView.swift", encoding: .utf8)

        #expect(source.contains("StagedSearchLoadingCard"))
        #expect(source.contains("ResultSignalCard"))
        #expect(source.contains("commandCenterTransition(isEnabled: true, index: index)"))
        #expect(source.contains("StatusLightRail(isActive: true"))
        #expect(source.contains("ActionStatusRow("))
        #expect(source.contains("WorkbenchCard("))
    }

    @Test("Detail panel uses decision receipt components")
    func detailPanelUsesDecisionReceiptComponents() throws {
        let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/DetailPanelView.swift", encoding: .utf8)

        #expect(source.contains("DecisionReceiptHeader"))
        #expect(source.contains("RouteDecisionCard"))
        #expect(source.contains("ReceiptActionBar"))
        #expect(source.contains("TaskStatusTile("))
        #expect(source.contains("WorkbenchCard("))
        #expect(source.contains("ActionStatusRow("))
    }
}
