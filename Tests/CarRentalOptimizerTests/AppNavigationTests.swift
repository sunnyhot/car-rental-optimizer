import Testing
@testable import CarRentalOptimizer

@MainActor
@Suite("App navigation")
struct AppNavigationTests {
    @Test("App starts in the comparison workspace")
    func appStartsInComparisonWorkspace() {
        let model = AppNavigationModel()

        #expect(model.selectedWorkspace == .comparison)
    }

    @Test("Navigation commands switch between main workspaces")
    func commandsSwitchWorkspaces() {
        let model = AppNavigationModel()

        model.showMonitoring()
        #expect(model.selectedWorkspace == .monitoring)

        model.showComparison()
        #expect(model.selectedWorkspace == .comparison)
    }

    @Test("Workspace metadata is stable and user facing")
    func workspaceMetadataIsStable() {
        #expect(AppWorkspace.allCases.map(\.title) == ["比价工作台", "价格监控"])
        #expect(AppWorkspace.comparison.systemImage == "point.3.connected.trianglepath.dotted")
        #expect(AppWorkspace.monitoring.systemImage == "chart.xyaxis.line")
    }
}
