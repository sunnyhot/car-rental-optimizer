import SwiftUI
import WebKit

struct EhiLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pageTitle = "一嗨登录"
    @State private var currentURL = EhiLoginSession.loginURL.absoluteString
    @State private var reloadToken = 0

    let onCompleted: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "person.badge.key.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.accent)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pageTitle.isEmpty ? "一嗨登录" : pageTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.ink)
                    Text(currentURL)
                        .font(.caption2)
                        .foregroundStyle(WorkbenchStyle.muted)
                        .lineLimit(1)
                }

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
                        await EhiCookieVault.save(from: WKWebsiteDataStore.default().httpCookieStore)
                        EhiLoginSession.notifyDidChange()
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

            EhiLoginWebView(pageTitle: $pageTitle, currentURL: $currentURL, reloadToken: reloadToken)
                .frame(minWidth: 760, minHeight: 620)
        }
        .frame(minWidth: 760, minHeight: 680)
    }
}

private struct EhiLoginWebView: NSViewRepresentable {
    @Binding var pageTitle: String
    @Binding var currentURL: String
    let reloadToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(pageTitle: $pageTitle, currentURL: $currentURL)
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
        context.coordinator.loadLoginPage(
            in: webView,
            resetChallengeData: false,
            resetAutoRefreshGuard: false,
            restoreSavedSession: true
        )
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.pageTitle = $pageTitle
        context.coordinator.currentURL = $currentURL
        context.coordinator.webView = nsView
        if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            context.coordinator.loadLoginPage(
                in: nsView,
                resetChallengeData: true,
                resetAutoRefreshGuard: true,
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
        var lastReloadToken = 0
        weak var webView: WKWebView?
        private var hasAutoRefreshedCaptchaError = false

        init(pageTitle: Binding<String>, currentURL: Binding<String>) {
            self.pageTitle = pageTitle
            self.currentURL = currentURL
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            update(from: webView)
            inspectCaptchaError(in: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            update(from: webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == EhiLoginSession.captchaValidationObserverMessageName, let webView else { return }
            recoverFromCaptchaError(in: webView)
        }

        func loadLoginPage(
            in webView: WKWebView,
            resetChallengeData: Bool,
            resetAutoRefreshGuard: Bool,
            restoreSavedSession: Bool
        ) {
            if resetAutoRefreshGuard {
                hasAutoRefreshedCaptchaError = false
            }

            let load = { [weak self, weak webView] in
                guard let self, let webView else { return }
                Task { @MainActor in
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
                EhiCookieVault.discardSavedSession()
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
            webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self, weak webView] result, _ in
                guard let self, let webView, let text = result as? String else { return }
                guard EhiLoginSession.containsCaptchaValidationError(text) else { return }
                self.recoverFromCaptchaError(in: webView)
            }
        }

        private func recoverFromCaptchaError(in webView: WKWebView) {
            guard !hasAutoRefreshedCaptchaError else { return }
            hasAutoRefreshedCaptchaError = true
            loadLoginPage(
                in: webView,
                resetChallengeData: true,
                resetAutoRefreshGuard: false,
                restoreSavedSession: false
            )
        }
    }
}
