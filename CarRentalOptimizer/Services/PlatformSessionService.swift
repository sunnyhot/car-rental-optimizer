import Foundation
import WebKit

// MARK: - Platform Config

struct PlatformConfig {
    let platform: PlatformId
    let label: String
    let url: URL
    let partitionIdentifier: String
}

private let platformConfigs: [PlatformId: PlatformConfig] = [
    .ehi: PlatformConfig(
        platform: .ehi, label: "一嗨",
        url: URL(string: "https://www.1hai.cn/")!,
        partitionIdentifier: "rental-ehi"
    ),
    .carInc: PlatformConfig(
        platform: .carInc, label: "神州",
        url: URL(string: "https://www.zuche.com/")!,
        partitionIdentifier: "rental-car-inc"
    )
]

func getPlatformConfig(_ platform: PlatformId) -> PlatformConfig? {
    platformConfigs[platform]
}

// MARK: - Auth State

struct PlatformAuthState: Identifiable {
    var id: PlatformId { platform }
    let platform: PlatformId
    let label: String
    let hasCookies: Bool
    let cookieCount: Int
    let url: String
}

// MARK: - Snapshot Types

struct LivePlatformSnapshot {
    let platform: PlatformId
    let title: String
    let url: String
    let text: String
}

struct SnapshotDiagnostics {
    let platform: PlatformId
    let title: String
    let url: String
    let textLength: Int
    let lineCount: Int
    let priceCandidateCount: Int
    let vehicleCandidateCount: Int
    let storeCandidateCount: Int
}

struct SnapshotResult {
    let ok: Bool
    let autoOpened: Bool
    let snapshot: LivePlatformSnapshot?
    let message: String?
}

// MARK: - Platform Session Service

@MainActor
class PlatformSessionService: ObservableObject {
    @Published var authStates: [PlatformAuthState] = []

    private var webViews: [PlatformId: WKWebView] = [:]

    // MARK: - WebView Management

    private func ensureWebView(for platform: PlatformId) -> WKWebView? {
        guard let config = getPlatformConfig(platform) else { return nil }

        if let existing = webViews[platform] {
            return existing
        }

        let websiteDataStore = WKWebsiteDataStore(forIdentifier: UUID())
        let webViewConfig = WKWebViewConfiguration()
        webViewConfig.websiteDataStore = websiteDataStore

        let webView = WKWebView(frame: .zero, configuration: webViewConfig)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.load(URLRequest(url: config.url))

        webViews[platform] = webView
        return webView
    }

    // MARK: - Public API

    func openPlatform(_ platform: PlatformId) async -> PlatformAuthState? {
        guard let config = getPlatformConfig(platform),
              let webView = ensureWebView(for: platform) else { return nil }

        webView.load(URLRequest(url: config.url))
        let state = await getAuthState(for: platform)
        await refreshAuthStates()
        return state
    }

    func readSnapshot(_ platform: PlatformId) async -> SnapshotResult {
        guard let config = getPlatformConfig(platform) else {
            return SnapshotResult(ok: false, autoOpened: false, snapshot: nil, message: "不支持的平台")
        }

        let wasNew = webViews[platform] == nil
        guard let webView = ensureWebView(for: platform) else {
            return SnapshotResult(ok: false, autoOpened: false, snapshot: nil, message: "无法创建 WebView")
        }

        // Wait briefly for page to load
        try? await Task.sleep(nanoseconds: 500_000_000)

        do {
            let result = try await webView.evaluateJavaScript("({ title: document.title || '', url: location.href, text: document.body ? document.body.innerText : '' })") as? [String: Any]

            guard let result = result else {
                return SnapshotResult(ok: false, autoOpened: wasNew, snapshot: nil, message: "页面读取返回空")
            }

            let snapshot = LivePlatformSnapshot(
                platform: platform,
                title: result["title"] as? String ?? "",
                url: result["url"] as? String ?? config.url.absoluteString,
                text: result["text"] as? String ?? ""
            )

            return SnapshotResult(
                ok: true,
                autoOpened: wasNew,
                snapshot: snapshot,
                message: wasNew ? "已自动打开\(config.label)官方窗口。请在该窗口完成城市、日期、车型搜索后再次点击开始比较。" : nil
            )
        } catch {
            return SnapshotResult(
                ok: false,
                autoOpened: wasNew,
                snapshot: nil,
                message: "\(config.label)读取失败：\(error.localizedDescription)"
            )
        }
    }

    func clearPlatform(_ platform: PlatformId) async {
        guard let config = getPlatformConfig(platform),
              let webView = webViews[platform] else { return }

        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let date = Date(timeIntervalSince1970: 0)
        await webView.configuration.websiteDataStore.removeData(ofTypes: dataTypes, modifiedSince: date)
        webView.load(URLRequest(url: config.url))
        await refreshAuthStates()
    }

    func refreshAuthStates() async {
        var states: [PlatformAuthState] = []
        for platform in PlatformId.allCases {
            states.append(await getAuthState(for: platform))
        }
        authStates = states
    }

    private func getAuthState(for platform: PlatformId) async -> PlatformAuthState {
        guard let config = getPlatformConfig(platform) else {
            return PlatformAuthState(platform: platform, label: "未知", hasCookies: false, cookieCount: 0, url: "")
        }

        guard let webView = webViews[platform] else {
            return PlatformAuthState(platform: platform, label: config.label, hasCookies: false, cookieCount: 0, url: config.url.absoluteString)
        }

        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let host = config.url.host ?? ""
        let platformCookies = cookies.filter { $0.domain.contains(host) }

        return PlatformAuthState(
            platform: platform,
            label: config.label,
            hasCookies: !platformCookies.isEmpty,
            cookieCount: platformCookies.count,
            url: config.url.absoluteString
        )
    }

    func getWebView(for platform: PlatformId) -> WKWebView? {
        webViews[platform]
    }
}
