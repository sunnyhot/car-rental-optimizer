import SwiftUI
import WebKit

struct EhiLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pageTitle = "一嗨登录"
    @State private var currentURL = EhiLoginSession.loginURL.absoluteString

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

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("登录完成，重新比较") {
                    EhiLoginSession.notifyDidChange()
                    dismiss()
                    onCompleted()
                }
                .buttonStyle(.borderedProminent)
                .tint(WorkbenchStyle.accent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(WorkbenchStyle.surface)
            .subtleDividerOverlay()

            EhiLoginWebView(pageTitle: $pageTitle, currentURL: $currentURL)
                .frame(minWidth: 760, minHeight: 620)
        }
        .frame(minWidth: 760, minHeight: 680)
    }
}

private struct EhiLoginWebView: NSViewRepresentable {
    @Binding var pageTitle: String
    @Binding var currentURL: String

    func makeCoordinator() -> Coordinator {
        Coordinator(pageTitle: $pageTitle, currentURL: $currentURL)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: EhiLoginSession.loginURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.pageTitle = $pageTitle
        context.coordinator.currentURL = $currentURL
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var pageTitle: Binding<String>
        var currentURL: Binding<String>

        init(pageTitle: Binding<String>, currentURL: Binding<String>) {
            self.pageTitle = pageTitle
            self.currentURL = currentURL
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            update(from: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            update(from: webView)
        }

        private func update(from webView: WKWebView) {
            pageTitle.wrappedValue = webView.title ?? "一嗨登录"
            currentURL.wrappedValue = webView.url?.absoluteString ?? EhiLoginSession.loginURL.absoluteString
        }
    }
}
