import Foundation
import UserNotifications

/// Manages local notifications for session events.
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    func scheduleLocal(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // fire immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[Notification] Failed: \(error)")
            }
        }
    }
}
