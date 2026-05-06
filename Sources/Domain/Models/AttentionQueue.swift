import Foundation

/// A FIFO queue of window UUIDs awaiting attention.
/// Pure value type with no framework dependencies.
public struct AttentionQueue {
    private var items: [UUID] = []

    public init() {}

    /// Adds `id` to the back of the queue. No-op if already present.
    public mutating func enqueue(_ id: UUID) {
        // O(n) membership check — acceptable for expected queue sizes (tens of items)
        guard !items.contains(id) else { return }
        items.append(id)
    }

    /// Removes and returns the front item, or `nil` if empty.
    public mutating func dequeue() -> UUID? {
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    /// Inserts `id` at the front of the queue. No-op if already present.
    public mutating func insertAtFront(_ id: UUID) {
        // O(n) membership check — acceptable for expected queue sizes (tens of items)
        guard !items.contains(id) else { return }
        items.insert(id, at: 0)
    }

    /// Moves `id` from its current position to the back of the queue.
    /// No-op if `id` is not present.
    public mutating func moveToBack(_ id: UUID) {
        guard let index = items.firstIndex(of: id) else { return }
        items.remove(at: index)
        items.append(id)
    }

    /// Removes `id` from the queue entirely. No-op if not present.
    public mutating func remove(_ id: UUID) {
        items.removeAll { $0 == id }
    }

    /// Returns the front item without removing it, or `nil` if empty.
    public func peek() -> UUID? {
        items.first
    }

    /// Returns the second item without removing it, or `nil` if fewer than two items.
    public func peekSecond() -> UUID? {
        guard items.count >= 2 else { return nil }
        return items[1]
    }

    /// Returns `true` if the queue contains `id`.
    public func contains(_ id: UUID) -> Bool {
        items.contains(id)
    }

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }
}
