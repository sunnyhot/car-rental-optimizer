import CarRentalDomain
import SwiftUI
import WebKit

struct PlatformLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pageTitle: String
    @State private var currentURL: String
    @State private var reloadToken = 0
    @State private var savingSession = false
    @State private var sessionSaveFailed = false

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
                    message: "登录官网后重新比较，读取当前方案的确认页应付总额。"
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
        .alert("登录状态未能保存", isPresented: $sessionSaveFailed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请检查本机存储权限后重试。本次未把保存失败当作登录完成。")
        }
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
                guard !savingSession else { return }
                savingSession = true
                Task { @MainActor in
                    defer { savingSession = false }
                    await PlatformSessionPersistence.shared.start()
                    guard await PlatformSessionPersistence.shared.flush() else { sessionSaveFailed = true; return }
                    dismiss()
                    onCompleted()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(WorkbenchStyle.decisionBlue)
            .disabled(savingSession)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var platformInfoRow: some View {
        ActionStatusRow(
            icon: "yensign.circle.fill",
            title: "费用补全",
            message: "登录完成后读取神州确认页的应付总额与已返回明细，不提交订单。金额对应平台默认方案；另选保障或优惠后需重新核价。",
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
                    await PlatformSessionPersistence.shared.start()
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
