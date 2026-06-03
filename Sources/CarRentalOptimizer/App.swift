import SwiftUI

@MainActor
@main
struct CarRentalOptimizerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1320, height: 860)
        .commands {
            // "关于" menu item
            CommandGroup(replacing: .appInfo) {
                Button("关于\(AppInfo.appName)") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: AppInfo.appName,
                            .applicationVersion: AppInfo.version,
                        ]
                    )
                }
            }
        }
    }
}
