import CarRentalDomain
import Foundation
import WebKit

struct PlatformBrowserState: Equatable {
    let platform: PlatformId
    var title: String
    var url: String
    var isLoading: Bool
    var message: String
}

@MainActor
final class PlatformBrowserStore: NSObject, ObservableObject, PlatformSnapshotProviding {
    @Published var selectedPlatform: PlatformId = .ehi
    @Published private(set) var states: [PlatformId: PlatformBrowserState]

    private var webViews: [PlatformId: WKWebView] = [:]
    private var delegates: [PlatformId: PlatformNavigationDelegate] = [:]
    private var loadedPlatforms = Set<PlatformId>()

    override init() {
        states = Dictionary(uniqueKeysWithValues: PlatformId.allCases.map {
            ($0, PlatformBrowserState(
                platform: $0,
                title: $0.label,
                url: officialPlatformURL(for: $0),
                isLoading: false,
                message: "未打开官方页面。"
            ))
        })
        super.init()
    }

    func select(_ platform: PlatformId) {
        selectedPlatform = platform
        _ = webView(for: platform)
    }

    func webView(for platform: PlatformId) -> WKWebView {
        if let webView = webViews[platform] {
            return webView
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        let delegate = PlatformNavigationDelegate(
            platform: platform,
            onStateChange: { [weak self, weak webView] platform, isLoading, message in
                guard let self, let webView else { return }
                self.updateState(
                    platform: platform,
                    webView: webView,
                    isLoading: isLoading,
                    message: message
                )
            }
        )
        delegates[platform] = delegate
        webView.navigationDelegate = delegate
        webViews[platform] = webView
        return webView
    }

    func loadHome(_ platform: PlatformId) {
        guard let url = URL(string: officialPlatformURL(for: platform)) else { return }
        loadedPlatforms.insert(platform)
        webView(for: platform).load(URLRequest(url: url))
    }

    func reload(_ platform: PlatformId) {
        webView(for: platform).reload()
    }

    func goBack(_ platform: PlatformId) {
        let webView = webView(for: platform)
        if webView.canGoBack {
            webView.goBack()
        }
    }

    func goForward(_ platform: PlatformId) {
        let webView = webView(for: platform)
        if webView.canGoForward {
            webView.goForward()
        }
    }

    func state(for platform: PlatformId) -> PlatformBrowserState {
        states[platform] ?? PlatformBrowserState(
            platform: platform,
            title: platform.label,
            url: officialPlatformURL(for: platform),
            isLoading: false,
            message: "等待官方页面加载。"
        )
    }

    func snapshot(for platform: PlatformId) async throws -> PlatformPageSnapshot {
        guard loadedPlatforms.contains(platform) else {
            return PlatformPageSnapshot(
                platform: platform,
                title: platform.label,
                url: officialPlatformURL(for: platform),
                text: ""
            )
        }

        let webView = webView(for: platform)
        let script = """
        (() => ({
            title: document.title || "",
            url: location.href,
            text: document.body ? document.body.innerText : ""
        }))()
        """
        let result = try await webView.evaluateJavaScript(script) as Any
        let snapshot = parseSnapshotResult(result, platform: platform, fallbackURL: webView.url)
        updateState(
            platform: platform,
            webView: webView,
            isLoading: webView.isLoading,
            message: snapshot.text.isEmpty ? "当前官方页面没有可读取文本。" : "已读取当前官方页面。"
        )
        return snapshot
    }

    private func parseSnapshotResult(_ result: Any, platform: PlatformId, fallbackURL: URL?) -> PlatformPageSnapshot {
        let dictionary = result as? [String: Any]
        return PlatformPageSnapshot(
            platform: platform,
            title: dictionary?["title"] as? String ?? platform.label,
            url: dictionary?["url"] as? String ?? fallbackURL?.absoluteString ?? officialPlatformURL(for: platform),
            text: dictionary?["text"] as? String ?? ""
        )
    }

    private func updateState(platform: PlatformId, webView: WKWebView, isLoading: Bool, message: String) {
        states[platform] = PlatformBrowserState(
            platform: platform,
            title: webView.title?.isEmpty == false ? webView.title ?? platform.label : platform.label,
            url: webView.url?.absoluteString ?? officialPlatformURL(for: platform),
            isLoading: isLoading,
            message: message
        )
    }
}

private final class PlatformNavigationDelegate: NSObject, WKNavigationDelegate {
    let platform: PlatformId
    let onStateChange: @MainActor (PlatformId, Bool, String) -> Void

    init(platform: PlatformId, onStateChange: @escaping @MainActor (PlatformId, Bool, String) -> Void) {
        self.platform = platform
        self.onStateChange = onStateChange
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in
            onStateChange(platform, true, "正在加载官方页面。")
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            onStateChange(platform, false, "官方页面已加载。")
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            onStateChange(platform, false, "官方页面加载失败：\(error.localizedDescription)")
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            onStateChange(platform, false, "官方页面加载失败：\(error.localizedDescription)")
        }
    }
}
