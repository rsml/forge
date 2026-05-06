import AppKit
import Foundation
import UserNotifications
import ForgeDomain

/// Concrete implementation of `NotificationPort` that delivers macOS notifications.
///
/// Uses `NSWorkspace` notifications when running as a bare executable (no bundle ID),
/// and `UNUserNotificationCenter` when running as a proper .app bundle.
final class MacNotificationAdapter: NotificationPort, @unchecked Sendable {

    private var hasBundle: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    func requestPermission() async -> Bool {
        guard hasBundle else { return true }  // no permission needed without UNUserNotificationCenter
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func send(title: String, body: String, sound: String?) async {
        if hasBundle {
            await sendViaUNUserNotification(title: title, body: body, sound: sound)
        } else {
            await sendViaDistributedNotification(title: title, body: body, sound: sound)
        }
    }

    // MARK: - UNUserNotificationCenter path (requires .app bundle)

    private func sendViaUNUserNotification(title: String, body: String, sound: String?) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = resolveUNSound(sound)

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func resolveUNSound(_ sound: String?) -> UNNotificationSound {
        guard let sound, !sound.isEmpty, sound != "default" else { return .default }
        return UNNotificationSound(named: UNNotificationSoundName(rawValue: sound))
    }

    // MARK: - Fallback path for bare SPM executables (no bundle)

    @MainActor
    private func sendViaDistributedNotification(title: String, body: String, sound: String?) {
        // Play sound
        playSound(sound)

        // Post a system notification via NSApp — shows as a banner if the app has focus
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.soundName = resolveSoundName(sound)
        NSUserNotificationCenter.default.deliver(notification)
    }

    @MainActor
    private func playSound(_ sound: String?) {
        let name = resolveSoundName(sound)
        if let nsSound = NSSound(named: NSSound.Name(name)) {
            nsSound.play()
        } else {
            NSSound.beep()
        }
    }

    private func resolveSoundName(_ sound: String?) -> String {
        guard let sound, !sound.isEmpty, sound != "default" else { return "Ping" }
        // Strip file extension if present
        if sound.hasSuffix(".aiff") || sound.hasSuffix(".wav") {
            return (sound as NSString).deletingPathExtension
        }
        return sound
    }
}
