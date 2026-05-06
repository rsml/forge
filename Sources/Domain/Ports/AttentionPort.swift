import Foundation

/// Manages the ordered queue of windows that need user attention.
@MainActor
public protocol AttentionPort: AnyObject {
    /// Process an incoming attention event (bell, command completion, etc.).
    func handleEvent(_ event: AttentionEvent)

    /// Mark the given window as handled and advance the queue.
    func markDone(_ windowUUID: UUID)

    /// Suppress the window from the active queue without removing it entirely.
    func hide(_ windowUUID: UUID)

    /// Move the window to the back of the queue.
    func moveToBack(_ windowUUID: UUID)

    /// Restore a previously hidden window back into the queue.
    func unhide(_ windowUUID: UUID)

    /// Remove the window from all tracking (e.g. window was closed).
    func removeWindow(_ windowUUID: UUID)

    /// The UUID of the window currently at the front of the attention queue.
    var currentWindowUUID: UUID? { get }

    /// Total number of windows in the active (non-hidden) queue.
    var queueCount: Int { get }

    /// Returns `true` if the window is anywhere in the attention queue.
    func needsAttention(_ windowUUID: UUID) -> Bool

    /// Returns `true` if the window has been hidden from the queue.
    func isHidden(_ windowUUID: UUID) -> Bool
}
