import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SearchViewModel()

    var body: some View {
        MainView()
            .environmentObject(viewModel)
            .frame(minWidth: 1120, minHeight: 720)
    }
}

#Preview("Content View") {
    ContentView()
}
