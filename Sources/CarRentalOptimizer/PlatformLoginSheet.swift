import CarRentalDomain
import SwiftUI
import WebKit

struct PlatformLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pageTitle: String
    @State private var currentURL: String
    @State private var reloadToken = 0

    let platform: PlatformId
    let onCompleted: () -> Void

    init(platform: PlatformId, onCompleted: @escaping () -> Void) {
        self.platform = platform
        self.onCompleted = onCompleted
        _pageTitle = State(initialValue: "\(platform.label)登录")
        _currentURL = State(initialValue: officialPlatformLoginURL(for: platform))
    }

    var body: some View {
        WorkbenchSheetShell(
            title: pageTitle.isEmpty ? "\(platform.label)登录" : pageTitle,
            subtitle: currentURL,
            icon: "person.badge.key.fill",
            tone: .active
        ) {
            VStack(spacing: 0) {
                platformActionBar
                BlueprintWebLocationBar(
                    platformName: platform.label,
                    currentURL: currentURL,
                    message: "登录官网后可重新比较并尝试补全确认页基础服务费。"
                )
                platformInfoRow

                PlatformLoginWebView(
                    platform: platform,
                    pageTitle: $pageTitle,
                    currentURL: $currentURL,
                    reloadToken: reloadToken
                )
                .frame(minWidth: 760, minHeight: 620)
            }
        }
        .frame(minWidth: 760, minHeight: 680)
    }

    private var platformActionBar: some View {
        BlueprintSheetActionBar {
            Spacer()

            Button {
                reloadToken += 1
            } label: {
                Label("刷新登录页", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button("取消") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("登录完成，重新比较") {
                Task { @MainActor in
                    if platform == .carInc {
                        await ZucheCookieVault.save(from: WKWebsiteDataStore.default().httpCookieStore)
                    }
                    dismiss()
                    onCompleted()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(WorkbenchStyle.decisionBlue)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var platformInfoRow: some View {
        ActionStatusRow(
            icon: "yensign.circle.fill",
            title: "费用补全",
            message: "神州基础服务费来自官方确认页费用接口；登录官网后点击完成，程序会重新比较并尝试补全这部分费用。",
            tone: .active
        )
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(WorkbenchStyle.commandBlue.opacity(0.08))
        .subtleDividerOverlay()
    }
}

private struct PlatformLoginWebView: NSViewRepresentable {
    let platform: PlatformId
    @Binding var pageTitle: String
    @Binding var currentURL: String
    let reloadToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(
            platform: platform,
            pageTitle: $pageTitle,
            currentURL: $currentURL
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = platformLoginUserAgent(for: platform)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.lastReloadToken = reloadToken
        context.coordinator.loadLoginPage(in: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.pageTitle = $pageTitle
        context.coordinator.currentURL = $currentURL
        context.coordinator.webView = nsView
        nsView.customUserAgent = platformLoginUserAgent(for: platform)
        if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            context.coordinator.loadLoginPage(in: nsView)
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.navigationDelegate = nil
        coordinator.webView = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let platform: PlatformId
        var pageTitle: Binding<String>
        var currentURL: Binding<String>
        var lastReloadToken = 0
        weak var webView: WKWebView?

        init(
            platform: PlatformId,
            pageTitle: Binding<String>,
            currentURL: Binding<String>
        ) {
            self.platform = platform
            self.pageTitle = pageTitle
            self.currentURL = currentURL
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            update(from: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            update(from: webView)
        }

        func loadLoginPage(in webView: WKWebView) {
            Task { @MainActor in
                let loginURL = officialPlatformLoginURL(for: platform)
                pageTitle.wrappedValue = "\(platform.label)登录"
                currentURL.wrappedValue = loginURL
                webView.stopLoading()
                if platform == .carInc {
                    await ZucheCookieVault.restore(into: webView.configuration.websiteDataStore.httpCookieStore)
                }
                if let url = URL(string: loginURL) {
                    webView.load(URLRequest(url: url))
                }
            }
        }

        private func update(from webView: WKWebView) {
            pageTitle.wrappedValue = webView.title ?? "\(platform.label)登录"
            currentURL.wrappedValue = webView.url?.absoluteString ?? officialPlatformLoginURL(for: platform)
        }
    }
}

func officialPlatformLoginURL(for platform: PlatformId) -> String {
    switch platform {
    case .ehi:
        return EhiLoginSession.loginURL.absoluteString
    case .carInc:
        return ZucheLoginSession.loginURL.absoluteString
    }
}

func platformLoginUserAgent(for platform: PlatformId) -> String {
    switch platform {
    case .ehi:
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    case .carInc:
        return ZucheLoginSession.desktopUserAgent
    }
}
