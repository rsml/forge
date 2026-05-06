import AppKit
import Foundation
import UserNotifications
import ForgeDomain

/// Concrete implementation of `NotificationPort` that delivers macOS notifications.
///
/// Always shows an in-app toast banner. Additionally uses `UNUserNotificationCenter`
/// when running as a proper .app bundle (for background notifications).
final class MacNotificationAdapter: NotificationPort, @unchecked Sendable {

    private var hasBundle: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    func requestPermission() async -> Bool {
        guard hasBundle else { return true }
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func send(title: String, body: String, sound: String?) async {
        // Always show in-app toast
        await MainActor.run {
            NotificationToastState.shared.show(title: title, message: body)
        }

        // Play sound
        await MainActor.run { playSound(sound) }

        // Also send system notification if we have a bundle
        if hasBundle {
            _ = await requestPermission()
            await sendViaUNUserNotification(title: title, body: body, sound: sound)
        }
    }

    // MARK: - Sound

    @MainActor
    func playSound(_ sound: String?) {
        let name = resolveSoundName(sound)
        if let nsSound = NSSound(named: NSSound.Name(name)) {
            nsSound.play()
        } else if let sound, sound.hasSuffix(".aiff") || sound.hasSuffix(".wav") {
            // Try loading custom file by path
            if let nsSound = NSSound(contentsOfFile: sound, byReference: true) {
                nsSound.play()
            } else {
                NSSound.beep()
            }
        } else {
            NSSound.beep()
        }
    }

    // MARK: - UNUserNotificationCenter (requires .app bundle)

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

    private func resolveSoundName(_ sound: String?) -> String {
        guard let sound, !sound.isEmpty, sound != "default", sound != "Default" else { return "Ping" }
        if sound.hasSuffix(".aiff") || sound.hasSuffix(".wav") {
            return (sound as NSString).deletingPathExtension
        }
        return sound
    }
}
