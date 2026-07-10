import Foundation
import Testing

@Suite("UI effects source contracts")
struct UIEffectsSourceTests {
    @Test("Main view routes app commands through the primary workspace shell")
    func mainViewRoutesCommandsThroughWorkspaceShell() throws {
        let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/MainView.swift", encoding: .utf8)
        let shell = try String(contentsOfFile: "Sources/CarRentalOptimizer/AppShellView.swift", encoding: .utf8)

        #expect(source.contains("AppNavigationModel"))
        #expect(source.contains("AppShellView(navigationModel:"))
        #expect(source.contains("navigationModel.showMonitoring()"))
        #expect(source.contains("navigationModel.showComparison()"))
        #expect(!source.contains("showingMonitorCenter"))
        #expect(shell.contains("PrimaryNavigationRail"))
        #expect(shell.contains("BlueprintStatusBar"))
        #expect(shell.contains("MonitorCenterView()"))
    }

    @Test("Main shell uses Route Blueprint status components")
    func mainShellUsesRouteBlueprintStatusComponents() throws {
        let main = try String(contentsOfFile: "Sources/CarRentalOptimizer/MainView.swift", encoding: .utf8)
        let shell = try String(contentsOfFile: "Sources/CarRentalOptimizer/AppShellView.swift", encoding: .utf8)

        #expect(main.contains("AppShellView(navigationModel:"))
        #expect(shell.contains("WorkbenchBackground()"))
        #expect(shell.contains("BlueprintStatusBar"))
        #expect(shell.contains("StatusLightRail("))
        #expect(shell.contains("TaskStatusTile("))
        #expect(shell.contains("tone: .active"))
        #expect(shell.contains("tone: .success"))
        #expect(shell.contains("tone: .warning"))
    }

    @Test("Search panel uses command console components")
    func searchPanelUsesCommandConsoleComponents() throws {
        let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/SearchPanelView.swift", encoding: .utf8)

        #expect(source.contains("QueryConsoleSection(step: \"01\""))
        #expect(source.contains("QueryConsoleSection(step: \"02\""))
        #expect(source.contains("QueryConsoleSection(step: \"03\""))
        #expect(source.contains("QueryConsoleSection(step: \"04\""))
        #expect(source.contains("BlueprintSectionHeader("))
        #expect(source.contains("BlueprintRouteTrail("))
        #expect(source.contains("PlatformSignalToggleButton"))
        #expect(source.contains("CompareCommandButton"))
        #expect(source.contains("VehicleSuggestionField("))
        #expect(source.contains("OriginSuggestionDropdown"))
    }

    @Test("Origin suggestion dropdown distinguishes stations from addresses")
    func originSuggestionDropdownDistinguishesStationsFromAddresses() throws {
        let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/SearchPanelView.swift", encoding: .utf8)

        #expect(source.contains("OriginSuggestionDropdown"))
        #expect(source.contains("suggestion.kind.systemImage"))
        #expect(source.contains("suggestion.kind.label"))
        #expect(source.contains("suggestion.fallbackNote"))
    }

    @Test("Result panel uses Route Blueprint decision signals")
    func resultPanelUsesRouteBlueprintDecisionSignals() throws {
        let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/ResultPanelView.swift", encoding: .utf8)

        #expect(source.contains("StagedSearchLoadingCard"))
        #expect(source.contains("ResultSignalCard"))
        #expect(source.contains("BlueprintStatePanel("))
        #expect(source.contains("BlueprintMetricTile("))
        #expect(source.contains("candidate-card-selection"))
        #expect(source.contains("commandCenterTransition(isEnabled: true, index: index)"))
        #expect(source.contains("comparisonViewModel.toggle(result)"))
        #expect(source.contains("QuoteCredibilityBadge"))
        #expect(source.contains("ActionStatusRow("))
        #expect(source.contains("hasExpandableVehicleMatches"))
    }

    @Test("Result cards expose vehicle name copy action")
    func resultCardsExposeVehicleNameCopyAction() throws {
        let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/ResultPanelView.swift", encoding: .utf8)

        #expect(source.contains("copyVehicleName()"))
        #expect(source.contains("NSPasteboard.general"))
        #expect(source.contains("doc.on.doc"))
        #expect(source.contains("复制车型"))
        #expect(source.contains("已复制车型"))
    }

    @Test("Result panel exposes compact vehicle insight line")
    func resultPanelExposesCompactVehicleInsightLine() throws {
        let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/ResultPanelView.swift", encoding: .utf8)

        #expect(source.contains("VehicleInsightLine("))
        #expect(source.contains("VehicleInsightLocalInferencer.localInsight(for: recommendation.listing)"))
        #expect(source.contains(".lineLimit(1)"))
    }

    @Test("Vehicle placeholder labels are hidden from result and detail surfaces")
    func vehiclePlaceholderLabelsAreHiddenFromResultAndDetailSurfaces() throws {
        let presentation = try String(contentsOfFile: "Sources/CarRentalOptimizer/VehiclePresentation.swift", encoding: .utf8)
        let resultPanel = try String(contentsOfFile: "Sources/CarRentalOptimizer/ResultPanelView.swift", encoding: .utf8)
        let detailPanel = try String(contentsOfFile: "Sources/CarRentalOptimizer/DetailPanelView.swift", encoding: .utf8)

        #expect(presentation.contains("kind != .notSpecified"))
        #expect(presentation.contains("trimmed != \"未指定车型\""))
        #expect(resultPanel.contains("displayName(with: recommendation.match)"))
        #expect(resultPanel.contains("recommendation.match.displayLabel"))
        #expect(detailPanel.contains("badge: recommendation.match.displayLabel"))
        #expect(detailPanel.contains("recommendation.listing.displayNameWithClass"))
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

    @Test("Detail panel exposes vehicle insight section with specs and configuration reference")
    func detailPanelExposesVehicleInsightSectionWithSpecsAndConfigurationReference() throws {
        let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/DetailPanelView.swift", encoding: .utf8)

        #expect(source.contains("VehicleInsightSection("))
        #expect(source.contains("viewModel.selectedVehicleInsight"))
        #expect(source.contains("车型介绍"))
        #expect(source.contains("基础参数"))
        #expect(source.contains("配置参考"))
        #expect(source.contains("formattedConfigurationFacts"))
        #expect(source.contains("下单前以平台确认页为准"))
    }

    @Test("Monitor center uses command surfaces")
    func monitorCenterUsesCommandSurfaces() throws {
        let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/MonitorCenterView.swift", encoding: .utf8)

        #expect(source.contains("MonitorCommandSurface"))
        #expect(source.contains("MonitorEventPulseRow"))
        #expect(source.contains("TaskStatusTile("))
        #expect(source.contains("ActionStatusRow("))
        #expect(source.contains("WorkbenchCard("))
    }

    @Test("Sheets use shared workbench chrome")
    func sheetsUseSharedWorkbenchChrome() throws {
        let createMonitor = try String(contentsOfFile: "Sources/CarRentalOptimizer/CreateMonitorSheet.swift", encoding: .utf8)
        let ehi = try String(contentsOfFile: "Sources/CarRentalOptimizer/EhiLoginSheet.swift", encoding: .utf8)
        let platform = try String(contentsOfFile: "Sources/CarRentalOptimizer/PlatformLoginSheet.swift", encoding: .utf8)

        #expect(createMonitor.contains("WorkbenchSheetShell("))
        #expect(createMonitor.contains("WorkbenchCard("))
        #expect(createMonitor.contains("ActionStatusRow("))
        #expect(ehi.contains("WorkbenchSheetShell("))
        #expect(ehi.contains("ActionStatusRow("))
        #expect(platform.contains("WorkbenchSheetShell("))
        #expect(platform.contains("ActionStatusRow("))
    }

    @Test("Search workspace exposes multi-select and the in-place comparison matrix")
    func searchWorkspaceExposesComparison() throws {
        let result = try String(contentsOfFile: "Sources/CarRentalOptimizer/ResultPanelView.swift", encoding: .utf8)
        let shell = try String(contentsOfFile: "Sources/CarRentalOptimizer/AppShellView.swift", encoding: .utf8)
        let matrix = try String(contentsOfFile: "Sources/CarRentalOptimizer/ComparisonMatrixView.swift", encoding: .utf8)

        #expect(result.contains("comparisonViewModel.toggle(result)"))
        #expect(result.contains("ComparisonSelectionBar("))
        #expect(shell.contains("comparisonViewModel.isComparing"))
        #expect(shell.contains("ComparisonMatrixView()"))
        #expect(matrix.contains("只看差异"))
        #expect(matrix.contains("设为当前方案"))
        #expect(matrix.contains("打开官方页面"))
    }
}
