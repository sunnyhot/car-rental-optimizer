import Foundation
import Testing
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
}
