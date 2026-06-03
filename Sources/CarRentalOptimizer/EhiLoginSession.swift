import Foundation

enum EhiLoginSession {
    static let loginURL = URL(string: "https://booking.1hai.cn/order/firstStep")!
    static let didChangeNotification = Notification.Name("EhiLoginSessionDidChange")

    static func notifyDidChange(center: NotificationCenter = .default) {
        center.post(name: didChangeNotification, object: nil)
    }
}
