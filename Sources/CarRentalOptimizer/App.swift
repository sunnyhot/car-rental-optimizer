import SwiftUI

@MainActor
@main
struct CarRentalOptimizerApp: App {
    @StateObject private var updateChecker = UpdateChecker()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .alert(item: $updateChecker.alert) { updateAlert($0) }
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

            CommandGroup(after: .appInfo) {
                Button(updateMenuTitle) {
                    Task { await updateChecker.checkForUpdates() }
                }
                .keyboardShortcut("u", modifiers: [.command])
                .disabled(updateChecker.isChecking || updateChecker.isInstalling)
            }
        }
    }

    private var updateMenuTitle: String {
        if updateChecker.isInstalling {
            return "正在自动升级…"
        }
        if updateChecker.isChecking {
            return "正在检查更新…"
        }
        return "检查更新…"
    }

    private func updateAlert(_ alert: UpdateAlert) -> Alert {
        switch alert.kind {
        case .updateAvailable:
            return Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: .default(Text("自动升级")) {
                    Task { await updateChecker.installAvailableUpdate() }
                },
                secondaryButton: .cancel(Text("稍后"))
            )
        case .installFailed:
            return Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: .default(Text("打开下载页")) {
                    updateChecker.openReleasePage(alert.releaseURL)
                },
                secondaryButton: .cancel(Text("好"))
            )
        case .upToDate, .failed:
            return Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("好"))
            )
        }
    }
}
