import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Ehi login session")
struct EhiLoginSessionTests {
    @Test("Login entry opens the booking site used by the silent API bridge")
    func loginEntryUsesBookingSite() {
        #expect(EhiLoginSession.loginURL.absoluteString == "https://booking.1hai.cn/order/firstStep")
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
