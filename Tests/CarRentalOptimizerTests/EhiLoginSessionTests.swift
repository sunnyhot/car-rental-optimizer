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

    @Test("Initial login sheet load restores saved session without clearing login cookies")
    func initialLoginSheetLoadRestoresSavedSessionWithoutClearingLoginCookies() throws {
        let source = try ehiLoginSheetSource()
        let marker = "context.coordinator.lastReloadToken = reloadToken"
        let markerRange = try #require(source.range(of: marker))
        let initialLoadBlock = String(source[markerRange.upperBound...].prefix(500))

        #expect(initialLoadBlock.contains("resetChallengeData: false"))
        #expect(initialLoadBlock.contains("restoreSavedSession: true"))
        #expect(!initialLoadBlock.contains("discardSavedSession: true"))
    }

    @Test("Captcha validation warning is surfaced without automatic reload")
    func captchaValidationWarningIsSurfacedWithoutAutomaticReload() throws {
        let source = try ehiLoginSheetSource()

        #expect(source.contains("showCaptchaWarning"))
        #expect(!source.contains("recoverFromCaptchaError"))
        #expect(!source.contains("hasAutoRefreshedCaptchaError"))
        #expect(!source.contains("EhiCookieVault.discardSavedSession()"))
    }

    @Test("Login sheet refresh preserves saved session and challenge reset is explicit")
    func loginSheetRefreshPreservesSavedSessionAndChallengeResetIsExplicit() throws {
        let source = try ehiLoginSheetSource()
        let reloadMarker = "if context.coordinator.lastReloadToken != reloadToken"
        let reloadRange = try #require(source.range(of: reloadMarker))
        let reloadBlock = String(source[reloadRange.upperBound...].prefix(500))

        #expect(reloadBlock.contains("resetChallengeData: false"))
        #expect(reloadBlock.contains("restoreSavedSession: true"))

        let resetMarker = "if context.coordinator.lastResetToken != resetToken"
        let resetRange = try #require(source.range(of: resetMarker))
        let resetBlock = String(source[resetRange.upperBound...].prefix(500))

        #expect(resetBlock.contains("resetChallengeData: true"))
        #expect(resetBlock.contains("restoreSavedSession: false"))
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

    @Test("Ehi cookie vault keeps an existing saved session when a login page has no eHi cookies")
    @MainActor
    func ehiCookieVaultKeepsExistingSavedSessionWhenCurrentStoreIsEmpty() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehi-session-\(UUID().uuidString).json")
        let populatedStore = WKWebsiteDataStore.nonPersistent()
        let emptyStore = WKWebsiteDataStore.nonPersistent()
        let ehiCookie = try #require(HTTPCookie(properties: [
            .domain: ".1hai.cn",
            .path: "/",
            .name: "SESSION",
            .value: "session-value",
            .secure: "TRUE"
        ]))

        await setCookie(ehiCookie, in: populatedStore.httpCookieStore)
        await EhiCookieVault.save(from: populatedStore.httpCookieStore, fileURL: fileURL)
        await EhiCookieVault.save(from: emptyStore.httpCookieStore, fileURL: fileURL)

        let restoreStore = WKWebsiteDataStore.nonPersistent()
        await EhiCookieVault.restore(into: restoreStore.httpCookieStore, fileURL: fileURL)
        let restored = await allCookies(in: restoreStore.httpCookieStore)

        #expect(restored.map(\.name) == ["SESSION"])
    }

    @Test("Zuche cookie vault keeps CAR Inc session cookies and ignores other platforms")
    func zucheCookieVaultKeepsCarIncSessionCookiesOnly() throws {
        let zucheCookie = try #require(HTTPCookie(properties: [
            .domain: ".zuche.com",
            .path: "/",
            .name: "SESSION",
            .value: "zuche-session",
            .secure: "TRUE",
            HTTPCookiePropertyKey("HttpOnly"): "TRUE"
        ]))
        let ehiCookie = try #require(HTTPCookie(properties: [
            .domain: "booking.1hai.cn",
            .path: "/",
            .name: "SESSION",
            .value: "wrong-platform"
        ]))

        let persisted = ZucheCookieVault.persistableCookies(from: [zucheCookie, ehiCookie])
        let restored = ZucheCookieVault.restoredCookies(from: persisted)

        #expect(persisted.count == 1)
        #expect(persisted.first?.name == "SESSION")
        #expect(persisted.first?.expiresDate == nil)
        #expect(restored.first?.domain == ".zuche.com")
        #expect(restored.first?.value == "zuche-session")
    }

    @Test("Zuche cookie vault keeps an existing saved session when login completion has no CAR Inc cookies")
    @MainActor
    func zucheCookieVaultKeepsExistingSavedSessionWhenCurrentStoreIsEmpty() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("zuche-session-\(UUID().uuidString).json")
        let populatedStore = WKWebsiteDataStore.nonPersistent()
        let emptyStore = WKWebsiteDataStore.nonPersistent()
        let zucheCookie = try #require(HTTPCookie(properties: [
            .domain: ".zuche.com",
            .path: "/",
            .name: "SESSION",
            .value: "zuche-session",
            .secure: "TRUE"
        ]))

        await setCookie(zucheCookie, in: populatedStore.httpCookieStore)
        await ZucheCookieVault.save(from: populatedStore.httpCookieStore, fileURL: fileURL)
        await ZucheCookieVault.save(from: emptyStore.httpCookieStore, fileURL: fileURL)

        let restoreStore = WKWebsiteDataStore.nonPersistent()
        await ZucheCookieVault.restore(into: restoreStore.httpCookieStore, fileURL: fileURL)
        let restored = await allCookies(in: restoreStore.httpCookieStore)

        #expect(restored.map(\.name) == ["SESSION"])
    }

    @Test("CAR Inc login sheet restores and saves the local session vault")
    func carIncLoginSheetRestoresAndSavesLocalSessionVault() throws {
        let source = try platformLoginSheetSource()

        #expect(source.contains("await ZucheCookieVault.save(from: WKWebsiteDataStore.default().httpCookieStore)"))
        #expect(source.contains("await ZucheCookieVault.restore(into: webView.configuration.websiteDataStore.httpCookieStore)"))
    }

    @Test("CAR Inc login sheet opens the official desktop login page")
    func carIncLoginSheetOpensOfficialDesktopLoginPage() throws {
        let source = try platformLoginSheetSource()

        #expect(officialPlatformLoginURL(for: .carInc) == "https://passport.zuche.com/memberManage/xtoploginMember.do?act=loginSys")
        #expect(source.contains("_currentURL = State(initialValue: officialPlatformLoginURL(for: platform))"))
        #expect(source.contains("platformLoginUserAgent(for: platform)"))
        #expect(ZucheLoginSession.loginURL == ZucheLoginSession.officialLoginURL)
        #expect(ZucheLoginSession.desktopUserAgent.contains("Macintosh; Intel Mac OS X"))
        #expect(!ZucheLoginSession.desktopUserAgent.contains("Mobile/15E148"))
    }

    @Test("CAR Inc login sheet does not expose mobile H5 login modes")
    func carIncLoginSheetDoesNotExposeMobileH5LoginModes() throws {
        let source = try platformLoginSheetSource()
        let sessionSource = try zucheLoginSessionSource()

        #expect(sessionSource.contains("officialLoginURL"))
        #expect(!sessionSource.contains("smsLoginURL"))
        #expect(!sessionSource.contains("passwordLoginURL"))
        #expect(!sessionSource.contains("mobileUserAgent"))
        #expect(!sessionSource.contains("ZucheLoginMode"))
        #expect(!source.contains("Picker(\"神州登录方式\""))
        #expect(!source.contains("短信登录"))
        #expect(!source.contains("密码登录"))
        #expect(!source.contains("html5/version652/user/login.html"))
    }

    @Test("CAR Inc SMS login page is left on the unmodified official submit flow")
    func carIncSMSLoginPageIsLeftOnUnmodifiedOfficialSubmitFlow() throws {
        let source = try platformLoginSheetSource()

        #expect(!source.contains("ZucheLoginSession.makeCompatibilityScript()"))
        #expect(!source.contains("configuration.userContentController.addUserScript"))
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

private func ehiLoginSheetSource() throws -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    let repositoryRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = repositoryRoot
        .appendingPathComponent("Sources/CarRentalOptimizer/EhiLoginSheet.swift")
    return try String(contentsOf: sourceURL, encoding: .utf8)
}

private func platformLoginSheetSource() throws -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    let repositoryRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = repositoryRoot
        .appendingPathComponent("Sources/CarRentalOptimizer/PlatformLoginSheet.swift")
    return try String(contentsOf: sourceURL, encoding: .utf8)
}

private func zucheLoginSessionSource() throws -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    let repositoryRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = repositoryRoot
        .appendingPathComponent("Sources/CarRentalOptimizer/ZucheLoginSession.swift")
    return try String(contentsOf: sourceURL, encoding: .utf8)
}
