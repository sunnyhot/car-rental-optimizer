import SwiftUI

struct MainView: View {
    @EnvironmentObject private var viewModel: SearchViewModel
    @EnvironmentObject private var monitorViewModel: MonitorCenterViewModel
    @StateObject private var navigationModel = AppNavigationModel()

    var body: some View {
        AppShellView(navigationModel: navigationModel)
            .onReceive(NotificationCenter.default.publisher(for: .openMonitorCenter)) { _ in
                navigationModel.showMonitoring()
            }
            .onReceive(NotificationCenter.default.publisher(for: .retryLatestSearch)) { _ in
                navigationModel.showComparison()
                Task { await viewModel.retrySearch() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .runDueMonitorChecks)) { _ in
                Task { await monitorViewModel.runDueChecks() }
            }
    }
}
