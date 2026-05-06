import Foundation

/// Abstracts system notification delivery so adapters can be swapped or mocked.
public protocol NotificationPort: Sendable {
    /// Request user permission to display notifications.
    /// Returns `true` if permission was granted.
    func requestPermission() async -> Bool

    /// Deliver a notification with the given title, body, and optional sound name.
    func send(title: String, body: String, sound: String?) async
}
