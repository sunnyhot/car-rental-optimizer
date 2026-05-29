import SwiftUI

@MainActor
@main
struct CarRentalOptimizerApp: App {
    private let updaterManager = UpdaterManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1320, height: 860)
        .commands {
            // "关于" menu item
            CommandGroup(replacing: .appInfo) {
                Button("关于租车总成本比较") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "租车总成本比较",
                            .applicationVersion: AppInfo.version,
                        ]
                    )
                }
            }

            // Sparkle "检查更新" menu item — inserted right after "关于"
            updaterManager.commands
        }
    }
}
