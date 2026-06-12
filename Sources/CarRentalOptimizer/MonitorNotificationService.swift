import CarRentalDomain
import Foundation
import UserNotifications

protocol MonitorNotificationSending: AnyObject {
    func sendPriceDropNotification(monitor: PriceMonitor, event: PriceMonitorEvent) async
}

final class NoopMonitorNotificationService: MonitorNotificationSending {
    func sendPriceDropNotification(monitor: PriceMonitor, event: PriceMonitorEvent) async {}
}

final class UserNotificationMonitorService: MonitorNotificationSending {
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func sendPriceDropNotification(monitor: PriceMonitor, event: PriceMonitorEvent) async {
        guard monitor.systemNotificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "租车价格下降"
        content.body = event.message
        content.sound = .default
        content.userInfo = ["monitorID": monitor.id]
        let request = UNNotificationRequest(identifier: event.id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
