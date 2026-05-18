import Foundation

/// Tracks when each tab first requested attention.
/// Pure value type — no framework dependencies.
public struct AttentionTimestamps {
    private var entries: [UUID: Date] = [:]

    public init() {}

    /// Restore from a persisted dictionary (UUID string → timeIntervalSince1970).
    public init(from dict: [String: Double]) {
        for (key, value) in dict {
            if let uuid = UUID(uuidString: key) {
                entries[uuid] = Date(timeIntervalSince1970: value)
            }
        }
    }

    /// Record attention time. No-op if already recorded (first event wins).
    public mutating func record(_ id: UUID, at date: Date = Date()) {
        guard entries[id] == nil else { return }
        entries[id] = date
    }

    /// Remove timestamp (e.g., on markDone).
    public mutating func remove(_ id: UUID) {
        entries.removeValue(forKey: id)
    }

    /// Look up the recorded timestamp.
    public func timestamp(for id: UUID) -> Date? {
        entries[id]
    }

    /// Remove entries not in the valid set.
    public mutating func prune(validUUIDs: some Collection<UUID>) {
        let valid = Set(validUUIDs)
        entries = entries.filter { valid.contains($0.key) }
    }

    /// Serialize for persistence.
    public func toDictionary() -> [String: Double] {
        var dict: [String: Double] = [:]
        for (uuid, date) in entries {
            dict[uuid.uuidString] = date.timeIntervalSince1970
        }
        return dict
    }
}
