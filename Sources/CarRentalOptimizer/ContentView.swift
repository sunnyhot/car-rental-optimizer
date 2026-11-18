import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject private var viewModel: SearchViewModel
    @StateObject private var monitorViewModel: MonitorCenterViewModel
    @StateObject private var comparisonViewModel: ComparisonWorkspaceViewModel

    init() {
        let vehicleInsightService = VehicleInsightService()
        _viewModel = StateObject(
            wrappedValue: SearchViewModel(vehicleInsightService: vehicleInsightService)
        )
        _comparisonViewModel = StateObject(
            wrappedValue: ComparisonWorkspaceViewModel(vehicleInsightService: vehicleInsightService)
        )
        let store: JSONMonitorStore
        do {
            store = AppInfo.isUIValidation
                ? JSONMonitorStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("CarRentalOptimizer-UIValidation-\(UUID().uuidString)"))
                : try JSONMonitorStore.live()
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
        let monitorViewModel = AppLifecycleDelegate.monitorViewModel ?? MonitorCenterViewModel(store: store, scheduler: scheduler)
        AppLifecycleDelegate.monitorViewModel = monitorViewModel
        _monitorViewModel = StateObject(wrappedValue: monitorViewModel)
    }

    var body: some View {
        MainView()
            .environmentObject(viewModel)
            .environmentObject(monitorViewModel)
            .environmentObject(comparisonViewModel)
            .task {
                guard !AppInfo.isUIValidation else { return }
                async let restoreSession: Void = PlatformSessionPersistence.shared.start()
                viewModel.startInitialCurrentLocationRefresh()
                try? await monitorViewModel.reload()
                await restoreSession
                // Background polling is opt-in; loading a window must not query saved monitors.
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
