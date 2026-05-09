import Foundation

/// Abstracts system notification delivery so adapters can be swapped or mocked.
public protocol NotificationPort: Sendable {
    /// Request user permission to display notifications.
    /// Returns `true` if permission was granted.
    func requestPermission() async -> Bool

    /// Deliver a notification with the given title, body, and optional sound name.
    /// `tabUUID` identifies the originating tab so the notification can navigate on tap.
    func send(title: String, body: String, sound: String?, tabUUID: UUID?) async
}
