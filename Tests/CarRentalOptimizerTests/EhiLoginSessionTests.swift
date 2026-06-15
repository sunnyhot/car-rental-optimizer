import Foundation
import Testing
import WebKit
@testable import CarRentalOptimizer

@Suite("Ehi login session")
struct EhiLoginSessionTests {
    @Test("Login entry opens the booking site used by the silent API bridge")
    func loginEntryUsesBookingSite() {
        #expect(EhiLoginSession.loginURL.absoluteString == "https://booking.1hai.cn/order/firstStep")
    }

    @Test("Login request bypasses cached captcha shell while staying on official path")
    func loginRequestBypassesCachedCaptchaShell() {
        let now = Date(timeIntervalSince1970: 1_780_203_600)
        let request = EhiLoginSession.makeLoginRequest(now: now)
        let url = request.url

        #expect(url?.host == "booking.1hai.cn")
        #expect(url?.path == "/order/firstStep")
        #expect(url?.query?.contains("_loginRefresh=1780203600000") == true)
        #expect(request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(request.httpShouldHandleCookies)
    }

    @Test("Captcha validation exception is detected from page text")
    func captchaValidationExceptionIsDetectedFromPageText() {
        #expect(EhiLoginSession.containsCaptchaValidationError("验证码校验异常，请刷新页面后重试"))
        #expect(!EhiLoginSession.containsCaptchaValidationError("手机号登录"))
    }

    @Test("Captcha observer reports validation errors inserted after page load")
    func captchaObserverReportsDynamicValidationError() {
        let source = EhiLoginSession.captchaValidationObserverSource(messageName: "testCaptchaObserver")

        #expect(source.contains("const messageName = \"testCaptchaObserver\";"))
        #expect(source.contains("new MutationObserver(notifyIfNeeded)"))
        #expect(source.contains("childList: true"))
        #expect(source.contains("subtree: true"))
        #expect(source.contains("characterData: true"))
        #expect(source.contains("handlers[messageName].postMessage(String(text).trim())"))
    }

    @Test("Only eHi website data records are reset")
    func onlyEhiWebsiteDataRecordsAreReset() {
        #expect(EhiLoginSession.isEhiWebsiteDataRecordName("booking.1hai.cn"))
        #expect(EhiLoginSession.isEhiWebsiteDataRecordName("www.1hai.cn"))
        #expect(!EhiLoginSession.isEhiWebsiteDataRecordName("m.zuche.com"))
    }

    @Test("Login completion announces that the shared WebKit session changed")
    func loginCompletionPostsSessionChangedNotification() async {
        var received = false
        let observer = NotificationCenter.default.addObserver(
            forName: EhiLoginSession.didChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            received = true
        }

        EhiLoginSession.notifyDidChange()
        NotificationCenter.default.removeObserver(observer)

        #expect(received)
    }

    @Test("Ehi cookie vault keeps one-hai session cookies and ignores other platforms")
    func ehiCookieVaultKeepsEhiSessionCookiesOnly() throws {
        let ehiCookie = try #require(HTTPCookie(properties: [
            .domain: ".1hai.cn",
            .path: "/",
            .name: "SESSION",
            .value: "session-value",
            .secure: "TRUE",
            HTTPCookiePropertyKey("HttpOnly"): "TRUE"
        ]))
        let carIncCookie = try #require(HTTPCookie(properties: [
            .domain: "m.zuche.com",
            .path: "/",
            .name: "SESSION",
            .value: "wrong-platform"
        ]))

        let persisted = EhiCookieVault.persistableCookies(from: [ehiCookie, carIncCookie])
        let restored = EhiCookieVault.restoredCookies(from: persisted)

        #expect(persisted.count == 1)
        #expect(persisted.first?.name == "SESSION")
        #expect(persisted.first?.expiresDate == nil)
        #expect(restored.first?.domain == ".1hai.cn")
        #expect(restored.first?.value == "session-value")
    }

    @Test("Ehi cookie vault drops expired cookies before restoring")
    func ehiCookieVaultDropsExpiredCookiesBeforeRestoring() throws {
        let now = Date(timeIntervalSince1970: 1_780_203_600)
        let expired = try #require(HTTPCookie(properties: [
            .domain: "booking.1hai.cn",
            .path: "/",
            .name: "OLD_TOKEN",
            .value: "expired",
            .expires: now.addingTimeInterval(-60)
        ]))
        let valid = try #require(HTTPCookie(properties: [
            .domain: "booking.1hai.cn",
            .path: "/",
            .name: "NEW_TOKEN",
            .value: "valid",
            .expires: now.addingTimeInterval(3600)
        ]))

        let persisted = EhiCookieVault.persistableCookies(from: [expired, valid], now: now)
        let restored = EhiCookieVault.restoredCookies(from: persisted, now: now)

        #expect(persisted.map(\.name) == ["NEW_TOKEN"])
        #expect(restored.map(\.name) == ["NEW_TOKEN"])
    }

    @Test("Captcha recovery removes persisted eHi cookies")
    func captchaRecoveryRemovesPersistedEhiCookies() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehi-session-\(UUID().uuidString).json")
        try "stale-session".write(to: fileURL, atomically: true, encoding: .utf8)

        EhiCookieVault.discardSavedSession(fileURL: fileURL)

        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("Captcha recovery removes eHi cookies from WebKit store")
    @MainActor
    func captchaRecoveryRemovesEhiCookiesFromWebKitStore() async throws {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let ehiCookie = try #require(HTTPCookie(properties: [
            .domain: ".1hai.cn",
            .path: "/",
            .name: "CAPTCHA_CHALLENGE",
            .value: "stale",
            .secure: "TRUE"
        ]))

        await setCookie(ehiCookie, in: dataStore.httpCookieStore)

        await withCheckedContinuation { continuation in
            EhiLoginSession.resetLoginChallengeData(dataStore: dataStore) {
                continuation.resume()
            }
        }

        let cookies = await allCookies(in: dataStore.httpCookieStore)
        #expect(cookies.filter(EhiCookieVault.isEhiCookie).isEmpty)
    }
}

@MainActor
private func allCookies(in store: WKHTTPCookieStore) async -> [HTTPCookie] {
    await withCheckedContinuation { continuation in
        store.getAllCookies { cookies in
            continuation.resume(returning: cookies)
        }
    }
}

@MainActor
private func setCookie(_ cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        store.setCookie(cookie) {
            continuation.resume()
        }
    }
}
