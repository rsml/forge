import Foundation

/// Manages the ordered queue of windows that need user attention.
@MainActor
public protocol AttentionPort: AnyObject {
    /// Process an incoming attention event (bell, command completion, etc.).
    func handleEvent(_ event: AttentionEvent)

    /// Mark the given tab as handled and advance the queue.
    func markDone(_ tabUUID: UUID)

    /// Suppress the tab from the active queue without removing it entirely.
    func hide(_ tabUUID: UUID)

    /// Move the tab to the back of the queue.
    func moveToBack(_ tabUUID: UUID)

    /// Restore a previously hidden tab back into the queue.
    func unhide(_ tabUUID: UUID)

    /// Remove the tab from all tracking (e.g. tab was closed).
    func removeTab(_ tabUUID: UUID)

    /// The UUID of the tab currently at the front of the attention queue.
    var currentTabUUID: UUID? { get }

    /// Total number of windows in the active (non-hidden) queue.
    var queueCount: Int { get }

    /// Returns `true` if the tab is anywhere in the attention queue.
    func needsAttention(_ tabUUID: UUID) -> Bool

    /// Returns `true` if the tab has been hidden from the queue.
    func isHidden(_ tabUUID: UUID) -> Bool
}
