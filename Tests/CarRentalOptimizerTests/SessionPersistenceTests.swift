import Foundation
import Testing
import WebKit
@testable import CarRentalOptimizer

@MainActor
private final class WebViewNavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func loadLocalHTML(in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            _ = webView.loadHTMLString("<html><body>Cookie observer fixture</body></html>", baseURL: URL(string: "http://127.0.0.1")!)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(with: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(with: error)
    }

    private func fail(with error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private final class RawCookieStoreObserver: NSObject, WKHTTPCookieStoreObserver {
    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private var count = 0

    nonisolated var callbackCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

@Suite("Session persistence", .serialized) @MainActor
struct SessionPersistenceTests {
    @Test func restoreMustNotOverwriteANewerBrowserCookie() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("ehi.json")
        let old = try cookie("session", value: "old", domain: ".1hai.cn")
        let current = try cookie("session", value: "fresh", domain: ".1hai.cn")
        try JSONEncoder().encode(EhiCookieVault.persistableCookies(from: [old])).write(to: file)
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let store = dataStore.httpCookieStore
        await set(current, in: store)
        await EhiCookieVault.restore(into: store, fileURL: file)
        let values = await all(in: store)
        #expect(values.first { $0.name == "session" }?.value == "fresh")
        withExtendedLifetime(dataStore) {}
    }

    @Test func cookiesRespectDomainPathAndSecureBoundaries() throws {
        let cookies = [
            try cookie("shared", value: "v", domain: ".zuche.com"),
            try cookie("mobile", value: "v", domain: "m.zuche.com"),
            try cookie("desktop", value: "v", domain: "www.zuche.com"),
            try cookie("passport", value: "v", domain: "passport.zuche.com"),
            try cookie("api", value: "v", domain: "m.zuche.com", path: "/api"),
            try cookie("not-prefix", value: "v", domain: "m.zuche.com", path: "/ap")
        ]
        let url = try #require(URL(string: "https://m.zuche.com/api/gw.do"))
        #expect(Set(cookiesForRequest(cookies, url: url).map(\.name)) == ["shared", "mobile", "api"])
        #expect(cookiesForRequest(cookies, url: URL(string: "https://evilzuche.com/api/gw.do")!).isEmpty)
        #expect(cookiesForRequest(cookies, url: URL(string: "http://m.zuche.com/api/gw.do")!).isEmpty)
    }

    @Test func rotationsAutomaticallyPersistAndRestoreAfterRestart() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ehiFile = folder.appendingPathComponent("ehi.json"), zucheFile = folder.appendingPathComponent("zuche.json")
        let old = try cookie("session", value: "old", domain: ".1hai.cn")
        let rotated = try cookie("session", value: "rotated", domain: ".1hai.cn")
        let oldData = try JSONEncoder().encode(EhiCookieVault.persistableCookies(from: [old]))
        try oldData.write(to: ehiFile)
        let firstDataStore = WKWebsiteDataStore.nonPersistent()
        let (firstWebView, firstNavigationDelegate) = try await loadedWebView(for: firstDataStore)
        let store = firstDataStore.httpCookieStore
        let coordinator = PlatformSessionPersistence(store: store, ehiFile: ehiFile, zucheFile: zucheFile)
        await coordinator.start()
        let revision = coordinator.saveRevision
        await set(rotated, in: store)
        await waitForSave(coordinator, after: revision)
        let saved = try JSONDecoder().decode([PersistedEhiCookie].self, from: Data(contentsOf: ehiFile))
        #expect(saved.first?.value == "rotated")
        // A stale backup must not be replayed by another query in this process.
        try oldData.write(to: ehiFile)
        await coordinator.start()
        #expect(await all(in: store).first { $0.name == "session" }?.value == "rotated")
        #expect(await coordinator.flush())
        coordinator.stop()
        let secondDataStore = WKWebsiteDataStore.nonPersistent()
        let secondWebView = webView(for: secondDataStore)
        let restarted = PlatformSessionPersistence(store: secondDataStore.httpCookieStore, ehiFile: ehiFile, zucheFile: zucheFile)
        await restarted.start()
        #expect(await all(in: secondDataStore.httpCookieStore).first { $0.name == "session" }?.value == "rotated")
        let permissions = try FileManager.default.attributesOfItem(atPath: ehiFile.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        restarted.stop()
        withExtendedLifetime((firstDataStore, secondDataStore, firstWebView, secondWebView, firstNavigationDelegate)) {}
    }

    @Test func authenticatedResponseUpdatesAreSavedAndLogoutDoesNotResurrectThem() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let (webView, navigationDelegate) = try await loadedWebView(for: dataStore)
        let ehiFile = folder.appendingPathComponent("ehi.json"), zucheFile = folder.appendingPathComponent("zuche.json")
        let coordinator = PlatformSessionPersistence(store: dataStore.httpCookieStore, ehiFile: ehiFile, zucheFile: zucheFile)
        await coordinator.start()
        let url = URL(string: "https://m.zuche.com/api/gw.do")!
        let responseCookie = try cookie("auth", value: "new", domain: ".zuche.com", path: "/account")
        await coordinator.applyAuthenticatedResponseCookies([responseCookie], for: url)
        var saved = try JSONDecoder().decode([PersistedZucheCookie].self, from: Data(contentsOf: zucheFile))
        #expect(saved.first?.value == "new")
        let revision = coordinator.saveRevision
        await withCheckedContinuation { continuation in dataStore.httpCookieStore.delete(responseCookie) { continuation.resume() } }
        await waitForSave(coordinator, after: revision)
        saved = try JSONDecoder().decode([PersistedZucheCookie].self, from: Data(contentsOf: zucheFile))
        #expect(saved.isEmpty)
        await coordinator.start()
        #expect(await all(in: dataStore.httpCookieStore).isEmpty)
        coordinator.stop()
        withExtendedLifetime((dataStore, webView, navigationDelegate)) {}
    }

    @Test func diagnoseRawCookieObserverDeliveryAcrossDataStoreKinds() async throws {
        await runRawObserverProbe(
            kind: "nonPersistent",
            probe: try cookie("observer_probe", value: "nonPersistent", domain: ".example.com")
        )
        let persistentIdentifier = UUID()
        await runRawObserverProbe(
            kind: "isolatedPersistent",
            persistentIdentifier: persistentIdentifier,
            probe: try cookie("observer_probe", value: "isolatedPersistent", domain: ".example.com")
        )
        try await WKWebsiteDataStore.remove(forIdentifier: persistentIdentifier)
    }

    @Test func failedPersistenceIsReportedInsteadOfPretendingSuccess() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dataStore = WKWebsiteDataStore.nonPersistent()
        #expect(await EhiCookieVault.save(from: dataStore.httpCookieStore, fileURL: folder, allowEmpty: true) == false)
        withExtendedLifetime(dataStore) {}
    }

    @Test func redirectDoesNotForwardManuallyScopedCookies() {
        let policy = ZucheSessionRedirectPolicy()
        let original = URL(string: "https://m.zuche.com/api/gw.do")!
        let task = URLSession.shared.dataTask(with: original)
        var redirected = URLRequest(url: URL(string: "https://outside.invalid/")!)
        redirected.setValue("session=fixture", forHTTPHeaderField: "Cookie")
        let response = HTTPURLResponse(url: original, statusCode: 302, httpVersion: nil, headerFields: ["Location": redirected.url!.absoluteString])!
        var allowed = true
        policy.urlSession(.shared, task: task, willPerformHTTPRedirection: response, newRequest: redirected) { allowed = $0 != nil }
        #expect(!allowed)
        task.cancel()
    }

    private func webView(for dataStore: WKWebsiteDataStore) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        return WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
    }

    private func loadedWebView(for dataStore: WKWebsiteDataStore) async throws -> (WKWebView, WebViewNavigationDelegate) {
        let webView = webView(for: dataStore)
        let delegate = WebViewNavigationDelegate()
        webView.navigationDelegate = delegate
        try await delegate.loadLocalHTML(in: webView)
        return (webView, delegate)
    }

    private func waitForSave(_ coordinator: PlatformSessionPersistence, after revision: Int) async {
        for _ in 0..<100 {
            if coordinator.saveRevision > revision { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Cookie observer did not persist the update")
    }

    private func runRawObserverProbe(kind: String, persistentIdentifier: UUID? = nil, probe: HTTPCookie) async {
        let dataStore = persistentIdentifier.map { WKWebsiteDataStore(forIdentifier: $0) } ?? .nonPersistent()
        let observer = RawCookieStoreObserver()
        let store = dataStore.httpCookieStore
        store.add(observer)
        await set(probe, in: store)
        for _ in 0..<100 where observer.callbackCount == 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let values = await all(in: store).filter { $0.name == "observer_probe" }.map(\.value)
        let callbacks = observer.callbackCount
        print("RAW_OBSERVER_AB kind=\(kind) callbacks=\(callbacks) storedValues=\(values)")
        #expect(values == [kind], "RAW_OBSERVER_AB \(kind) did not store its probe cookie")
        #expect(callbacks > 0, "RAW_OBSERVER_AB \(kind) delivered no raw observer callback")
        store.remove(observer)
        if persistentIdentifier == nil {
            await removeAllData(from: dataStore)
        }
        withExtendedLifetime((dataStore, observer)) {}
    }

    private func removeAllData(from dataStore: WKWebsiteDataStore) async {
        await withCheckedContinuation { continuation in
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
                continuation.resume()
            }
        }
    }

    private func cookie(_ name: String, value: String, domain: String, path: String = "/") throws -> HTTPCookie {
        try #require(HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: path, .secure: "TRUE"]))
    }

    private func set(_ cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in store.setCookie(cookie) { continuation.resume() } }
    }

    private func all(in store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in store.getAllCookies { continuation.resume(returning: $0) } }
    }
}
