import Foundation
import UserNotifications
import ForgeDomain

/// Concrete implementation of `NotificationPort` backed by `UNUserNotificationCenter`.
///
/// `@unchecked Sendable` because `UNUserNotificationCenter` is thread-safe but not
/// formally annotated as `Sendable`.
final class MacNotificationAdapter: NotificationPort, @unchecked Sendable {

    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func send(title: String, body: String, sound: String?) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        if let sound {
            if sound == "default" || sound.isEmpty {
                content.sound = .default
            } else if sound.hasSuffix(".aiff") || sound.hasSuffix(".wav") {
                // Custom sound file — must be in the app's Library/Sounds directory.
                content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: sound))
            } else {
                // System sound name (e.g. "Basso", "Ping").
                content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: sound))
            }
        } else {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // deliver immediately
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}
