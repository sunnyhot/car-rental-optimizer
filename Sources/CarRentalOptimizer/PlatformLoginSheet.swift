import CarRentalDomain
import SwiftUI
import WebKit

struct PlatformLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pageTitle: String
    @State private var currentURL: String
    @State private var reloadToken = 0
    @State private var zucheLoginMode: ZucheLoginMode

    let platform: PlatformId
    let onCompleted: () -> Void

    init(platform: PlatformId, onCompleted: @escaping () -> Void) {
        self.platform = platform
        self.onCompleted = onCompleted
        _pageTitle = State(initialValue: "\(platform.label)登录")
        _currentURL = State(initialValue: officialPlatformLoginURL(for: platform, zucheLoginMode: .official))
        _zucheLoginMode = State(initialValue: .official)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "person.badge.key.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.accent)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pageTitle.isEmpty ? "\(platform.label)登录" : pageTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.ink)
                    Text(currentURL)
                        .font(.caption2)
                        .foregroundStyle(WorkbenchStyle.muted)
                        .lineLimit(1)
                }

                Spacer()

                if platform == .carInc {
                    Picker("神州登录方式", selection: $zucheLoginMode) {
                        ForEach(ZucheLoginMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 226)
                    .help("默认使用神州官网登录；如果官网登录异常，可切换到移动端短信或密码登录页。")
                }

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
                .tint(WorkbenchStyle.accent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(WorkbenchStyle.surface)
            .subtleDividerOverlay()

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "yensign.circle.fill")
                    .foregroundStyle(WorkbenchStyle.accent)
                Text("神州基础服务费来自官方确认页费用接口；登录后点击完成，程序会重新比较并补全这部分费用。")
                    .font(.caption)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(WorkbenchStyle.accentSoft.opacity(0.7))
            .subtleDividerOverlay()

            PlatformLoginWebView(
                platform: platform,
                pageTitle: $pageTitle,
                currentURL: $currentURL,
                zucheLoginMode: zucheLoginMode,
                reloadToken: reloadToken
            )
            .frame(minWidth: 760, minHeight: 620)
        }
        .frame(minWidth: 760, minHeight: 680)
        .onChange(of: zucheLoginMode) { _, _ in
            currentURL = officialPlatformLoginURL(for: platform, zucheLoginMode: zucheLoginMode)
            reloadToken += 1
        }
    }
}

private struct PlatformLoginWebView: NSViewRepresentable {
    let platform: PlatformId
    @Binding var pageTitle: String
    @Binding var currentURL: String
    let zucheLoginMode: ZucheLoginMode
    let reloadToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(
            platform: platform,
            pageTitle: $pageTitle,
            currentURL: $currentURL,
            zucheLoginMode: zucheLoginMode
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = platformLoginUserAgent(for: platform, zucheLoginMode: zucheLoginMode)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.lastReloadToken = reloadToken
        context.coordinator.loadLoginPage(in: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.pageTitle = $pageTitle
        context.coordinator.currentURL = $currentURL
        context.coordinator.zucheLoginMode = zucheLoginMode
        context.coordinator.webView = nsView
        nsView.customUserAgent = platformLoginUserAgent(for: platform, zucheLoginMode: zucheLoginMode)
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
        var zucheLoginMode: ZucheLoginMode
        var lastReloadToken = 0
        weak var webView: WKWebView?

        init(
            platform: PlatformId,
            pageTitle: Binding<String>,
            currentURL: Binding<String>,
            zucheLoginMode: ZucheLoginMode
        ) {
            self.platform = platform
            self.pageTitle = pageTitle
            self.currentURL = currentURL
            self.zucheLoginMode = zucheLoginMode
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            update(from: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            update(from: webView)
        }

        func loadLoginPage(in webView: WKWebView) {
            Task { @MainActor in
                let loginURL = officialPlatformLoginURL(for: platform, zucheLoginMode: zucheLoginMode)
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
            currentURL.wrappedValue = webView.url?.absoluteString ?? officialPlatformLoginURL(
                for: platform,
                zucheLoginMode: zucheLoginMode
            )
        }
    }
}

func officialPlatformLoginURL(for platform: PlatformId) -> String {
    officialPlatformLoginURL(for: platform, zucheLoginMode: .official)
}

func officialPlatformLoginURL(for platform: PlatformId, zucheLoginMode: ZucheLoginMode) -> String {
    switch platform {
    case .ehi:
        return EhiLoginSession.loginURL.absoluteString
    case .carInc:
        return zucheLoginMode.url.absoluteString
    }
}

func platformLoginUserAgent(for platform: PlatformId) -> String {
    platformLoginUserAgent(for: platform, zucheLoginMode: .official)
}

func platformLoginUserAgent(for platform: PlatformId, zucheLoginMode: ZucheLoginMode) -> String {
    switch platform {
    case .ehi:
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    case .carInc:
        return zucheLoginMode.userAgent
    }
}
