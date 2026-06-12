import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: SearchViewModel
    @StateObject private var monitorViewModel: MonitorCenterViewModel

    init() {
        _viewModel = StateObject(wrappedValue: SearchViewModel())
        let store: JSONMonitorStore
        do {
            store = try JSONMonitorStore.live()
        } catch {
            store = JSONMonitorStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("CarRentalOptimizer-MonitorFallback", isDirectory: true)
            )
        }
        let scheduler = MonitorScheduler(
            store: store,
            searchProvider: LiveRentalSearchService(),
            mapService: AppleMapService(),
            notificationService: UserNotificationMonitorService()
        )
        let monitorViewModel = MonitorCenterViewModel(store: store, scheduler: scheduler)
        AppLifecycleDelegate.monitorViewModel = monitorViewModel
        _monitorViewModel = StateObject(wrappedValue: monitorViewModel)
    }

    var body: some View {
        MainView()
            .environmentObject(viewModel)
            .environmentObject(monitorViewModel)
            .task {
                try? await monitorViewModel.reload()
                await monitorViewModel.runDueChecks()
            }
            .frame(
                minWidth: AppWindowLayout.minimumWidth,
                minHeight: AppWindowLayout.minimumHeight
            )
            .background(
                WindowSizeConstraintView(minimumContentSize: AppWindowLayout.minimumContentSize)
                    .frame(width: 0, height: 0)
            )
    }
}

#Preview("Content View") {
    ContentView()
}
