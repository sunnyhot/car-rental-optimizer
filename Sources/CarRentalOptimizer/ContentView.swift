import SwiftUI

struct ContentView: View {
    @StateObject private var browserStore: PlatformBrowserStore
    @StateObject private var viewModel: SearchViewModel

    init() {
        let browserStore = PlatformBrowserStore()
        _browserStore = StateObject(wrappedValue: browserStore)
        _viewModel = StateObject(wrappedValue: SearchViewModel(snapshotProvider: browserStore))
    }

    var body: some View {
        MainView()
            .environmentObject(viewModel)
            .environmentObject(browserStore)
            .frame(minWidth: 1120, minHeight: 720)
    }
}

#Preview("Content View") {
    ContentView()
}
