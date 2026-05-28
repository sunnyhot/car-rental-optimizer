import SwiftUI

@main
struct CarRentalOptimizerApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(SearchViewModel())
                .frame(minWidth: 1120, minHeight: 720)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
