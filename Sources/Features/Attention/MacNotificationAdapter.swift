import AppKit
import Foundation
import UserNotifications
import ForgeCore

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let uuidString = userInfo["tabUUID"] as? String,
              let uuid = UUID(uuidString: uuidString) else { return }
        await MainActor.run {
            NotificationCenter.default.post(name: .forgeNavigateToTab, object: nil, userInfo: ["tabUUID": uuid])
        }
    }
}

/// Concrete implementation of `NotificationPort` that delivers macOS notifications.
///
/// Shows native macOS banners when running as a .app bundle with permission granted.
/// Falls back to in-app toast when system notifications are unavailable.
final class MacNotificationAdapter: NotificationPort, @unchecked Sendable {
    private let toastState: NotificationToastState

    /// Static so it survives temporary adapter instances — UNUserNotificationCenter.delegate is weak.
    private static let notificationDelegate = NotificationDelegate()

    init(toastState: NotificationToastState) {
        self.toastState = toastState
    }

    private var hasBundle: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    func requestPermission() async -> Bool {
        guard hasBundle else {
            ForgeLog.log("[attention] requestPermission: no bundle identifier, skipping")
            return false
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = Self.notificationDelegate
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            ForgeLog.log("[attention] requestPermission: granted=\(granted)")
            return granted
        } catch {
            ForgeLog.log("[attention] requestPermission error: \(error)")
            return false
        }
    }

    func send(title: String, body: String, sound: String?, tabUUID: UUID? = nil) async {
        var sentSystemNotification = false

        if hasBundle {
            let granted = await requestPermission()
            if granted {
                sentSystemNotification = await sendViaUNUserNotification(
                    title: title, body: body, sound: sound, tabUUID: tabUUID
                )
            }
        }

        if !sentSystemNotification {
            ForgeLog.log("[attention] falling back to in-app toast")
            await MainActor.run { toastState.show(title: title, message: body) }
            await MainActor.run { playSound(sound) }
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

    /// Returns `true` if the notification was successfully queued.
    private func sendViaUNUserNotification(title: String, body: String, sound: String?, tabUUID: UUID? = nil) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = resolveUNSound(sound)
        if let tabUUID {
            content.userInfo = ["tabUUID": tabUUID.uuidString]
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            ForgeLog.log("[attention] system notification sent: \(title)")
            return true
        } catch {
            ForgeLog.log("[attention] system notification failed: \(error)")
            return false
        }
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
