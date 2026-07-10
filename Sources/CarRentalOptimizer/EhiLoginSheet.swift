import SwiftUI
import WebKit

struct EhiLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pageTitle = "一嗨登录"
    @State private var currentURL = EhiLoginSession.loginURL.absoluteString
    @State private var reloadToken = 0
    @State private var resetToken = 0
    @State private var captchaWarning: String?

    let onCompleted: () -> Void

    var body: some View {
        WorkbenchSheetShell(
            title: pageTitle.isEmpty ? "一嗨登录" : pageTitle,
            subtitle: currentURL,
            icon: "person.badge.key.fill",
            tone: .active
        ) {
            VStack(spacing: 0) {
                loginActionBar
                BlueprintWebLocationBar(
                    platformName: "一嗨",
                    currentURL: currentURL,
                    message: "登录状态仅保存在本机，用于重新读取官方库存报价。",
                    tone: captchaWarning == nil ? .active : .warning
                )
                captchaWarningView

                EhiLoginWebView(
                    pageTitle: $pageTitle,
                    currentURL: $currentURL,
                    captchaWarning: $captchaWarning,
                    reloadToken: reloadToken,
                    resetToken: resetToken
                )
                .frame(minWidth: 760, minHeight: 620)
            }
        }
        .frame(minWidth: 760, minHeight: 680)
    }

    private var loginActionBar: some View {
        BlueprintSheetActionBar {
            Spacer()

            Button {
                let action = EhiLoginSession.refreshAction(forCaptchaWarning: captchaWarning)
                captchaWarning = nil
                switch action {
                case .reload:
                    reloadToken += 1
                case .resetChallenge:
                    resetToken += 1
                }
            } label: {
                Label(captchaWarning == nil ? "刷新登录页" : "重置并刷新登录页", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button("取消") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("登录完成，重新比较") {
                Task { @MainActor in
                    await EhiCookieVault.save(from: WKWebsiteDataStore.default().httpCookieStore)
                    EhiLoginSession.notifyDidChange()
                    dismiss()
                    onCompleted()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(WorkbenchStyle.decisionBlue)
            .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var captchaWarningView: some View {
        if let captchaWarning {
            HStack(alignment: .top, spacing: 10) {
                ActionStatusRow(
                    icon: "exclamationmark.triangle.fill",
                    title: captchaWarning,
                    message: "已停止自动刷新登录页，避免打断验证码输入。点「重置并刷新登录页」会清理一嗨验证状态并重新获取验证码。",
                    tone: .warning
                )
                .layoutPriority(1)

                Button("重置验证状态") {
                    self.captchaWarning = nil
                    resetToken += 1
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(WorkbenchStyle.amberAlert.opacity(0.10))
            .subtleDividerOverlay()
        }
    }
}

private struct EhiLoginWebView: NSViewRepresentable {
    @Binding var pageTitle: String
    @Binding var currentURL: String
    @Binding var captchaWarning: String?
    let reloadToken: Int
    let resetToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(pageTitle: $pageTitle, currentURL: $currentURL, captchaWarning: $captchaWarning)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.addUserScript(EhiLoginSession.makeCaptchaValidationObserverScript())
        configuration.userContentController.add(
            context.coordinator,
            name: EhiLoginSession.captchaValidationObserverMessageName
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.lastReloadToken = reloadToken
        context.coordinator.lastResetToken = resetToken
        context.coordinator.loadLoginPage(
            in: webView,
            resetChallengeData: false,
            restoreSavedSession: true
        )
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.pageTitle = $pageTitle
        context.coordinator.currentURL = $currentURL
        context.coordinator.captchaWarning = $captchaWarning
        context.coordinator.webView = nsView
        if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            context.coordinator.loadLoginPage(
                in: nsView,
                resetChallengeData: false,
                restoreSavedSession: true
            )
        }
        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            context.coordinator.loadLoginPage(
                in: nsView,
                resetChallengeData: true,
                restoreSavedSession: false
            )
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(
            forName: EhiLoginSession.captchaValidationObserverMessageName
        )
        nsView.navigationDelegate = nil
        coordinator.webView = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var pageTitle: Binding<String>
        var currentURL: Binding<String>
        var captchaWarning: Binding<String?>
        var lastReloadToken = 0
        var lastResetToken = 0
        weak var webView: WKWebView?

        init(pageTitle: Binding<String>, currentURL: Binding<String>, captchaWarning: Binding<String?>) {
            self.pageTitle = pageTitle
            self.currentURL = currentURL
            self.captchaWarning = captchaWarning
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            update(from: webView)
            inspectCaptchaError(in: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            update(from: webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == EhiLoginSession.captchaValidationObserverMessageName else { return }
            showCaptchaWarning(message.body as? String)
        }

        func loadLoginPage(
            in webView: WKWebView,
            resetChallengeData: Bool,
            restoreSavedSession: Bool
        ) {
            let load = { [weak self, weak webView] in
                guard let self, let webView else { return }
                Task { @MainActor in
                    self.captchaWarning.wrappedValue = nil
                    self.pageTitle.wrappedValue = "一嗨登录"
                    self.currentURL.wrappedValue = EhiLoginSession.loginURL.absoluteString
                    webView.stopLoading()
                    if restoreSavedSession {
                        await EhiCookieVault.restore(into: webView.configuration.websiteDataStore.httpCookieStore)
                    }
                    webView.load(EhiLoginSession.makeLoginRequest())
                }
            }

            if resetChallengeData {
                EhiLoginSession.resetLoginChallengeData(completion: load)
            } else {
                load()
            }
        }

        private func update(from webView: WKWebView) {
            pageTitle.wrappedValue = webView.title ?? "一嗨登录"
            currentURL.wrappedValue = webView.url?.absoluteString ?? EhiLoginSession.loginURL.absoluteString
        }

        private func inspectCaptchaError(in webView: WKWebView) {
            webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] result, _ in
                guard let self, let text = result as? String else { return }
                guard EhiLoginSession.containsCaptchaValidationError(text) else { return }
                self.showCaptchaWarning(text)
            }
        }

        private func showCaptchaWarning(_ rawText: String?) {
            let message = warningMessage(from: rawText)
            Task { @MainActor in
                captchaWarning.wrappedValue = message
            }
        }

        private func warningMessage(from rawText: String?) -> String {
            guard let rawText else {
                return "一嗨验证码校验异常，请刷新或重置验证状态后重试。"
            }
            let lines = rawText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return lines.first(where: EhiLoginSession.containsCaptchaValidationError)
                ?? "一嗨验证码校验异常，请刷新或重置验证状态后重试。"
        }
    }
}
