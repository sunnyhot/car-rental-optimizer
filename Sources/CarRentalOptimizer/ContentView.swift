import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: SearchViewModel

    init() {
        _viewModel = StateObject(wrappedValue: SearchViewModel())
    }

    var body: some View {
        MainView()
            .environmentObject(viewModel)
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
