import Foundation
import Observation
import AppKit
import ForgeCore

@Observable @MainActor
final class AttentionManager: AttentionPort {
    private var queue = AttentionQueue()
    private(set) var hiddenSet: Set<UUID> = []
    private let notifier: any NotificationPort
    private let config: ForgeConfigStore
    var timestamps = AttentionTimestamps()

    var currentTabUUID: UUID? { queue.peek() }
    var nextWindowUUID: UUID? { queue.peekSecond() }
    var queueCount: Int { queue.count }

    init(notifier: any NotificationPort, config: ForgeConfigStore) {
        self.notifier = notifier
        self.config = config
        self.hiddenSet = loadHiddenSet(from: config)
        self.timestamps = loadTimestamps(from: config)
    }

    /// Call after initial workspace load to prune stale UUIDs from a previous project.
    func pruneStaleHiddenEntries(validUUIDs: Set<UUID>) {
        let stale = hiddenSet.subtracting(validUUIDs)
        if !stale.isEmpty {
            hiddenSet.subtract(stale)
            persistHiddenSet()
        }
        timestamps.prune(validUUIDs: validUUIDs)
        persistTimestamps()
    }

    func handleEvent(_ event: AttentionEvent) {
        let uuid = event.tabUUID
        guard !hiddenSet.contains(uuid) else { return }
        timestamps.record(uuid)
        queue.enqueue(uuid)

        if config.config.stackView?.bringToForeground == "always" {
            NSApp.activate()
        }
    }

    func markDone(_ tabUUID: UUID) {
        queue.remove(tabUUID)
        timestamps.remove(tabUUID)
        persistTimestamps()
    }

    func hide(_ tabUUID: UUID) {
        queue.remove(tabUUID)
        hiddenSet.insert(tabUUID)
        persistHiddenSet()
    }

    func moveToBack(_ tabUUID: UUID) {
        queue.moveToBack(tabUUID)
    }

    func unhide(_ tabUUID: UUID) {
        hiddenSet.remove(tabUUID)
        persistHiddenSet()
    }

    func removeTab(_ tabUUID: UUID) {
        queue.remove(tabUUID)
        hiddenSet.remove(tabUUID)
        timestamps.remove(tabUUID)
    }

    func isHidden(_ tabUUID: UUID) -> Bool {
        hiddenSet.contains(tabUUID)
    }

    func promoteToFront(_ tabUUID: UUID) {
        queue.remove(tabUUID)
        queue.insertAtFront(tabUUID)
    }

    func seedQueue(ordered: [UUID]) {
        queue.replaceAll(ordered)
    }

    func pruneResolved(activeAttentionUUIDs: Set<UUID>) {
        let front = queue.peek()
        let toRemove = queue.allItems.filter { $0 != front && !activeAttentionUUIDs.contains($0) }
        for uuid in toRemove {
            queue.remove(uuid)
            timestamps.remove(uuid)
        }
        if !toRemove.isEmpty { persistTimestamps() }
    }

    private func persistTimestamps() {
        let dict = timestamps.toDictionary()
        config.update { config in
            if config.stackView == nil {
                config.stackView = ForgeConfig.StackViewSettings()
            }
            config.stackView?.attentionTimestamps = dict
        }
    }

    private func loadTimestamps(from config: ForgeConfigStore) -> AttentionTimestamps {
        guard let dict = config.config.stackView?.attentionTimestamps else {
            return AttentionTimestamps()
        }
        return AttentionTimestamps(from: dict)
    }

    private func persistHiddenSet() {
        // Capture hiddenSet as a local value to avoid @Observable accessor
        // issues inside the inout ForgeConfig closure.
        let uuids = hiddenSet.map(\.uuidString)
        config.update { config in
            if config.stackView == nil {
                config.stackView = ForgeConfig.StackViewSettings()
            }
            config.stackView?.hiddenTabUUIDs = uuids
        }
    }

    private func loadHiddenSet(from config: ForgeConfigStore) -> Set<UUID> {
        Set((config.config.stackView?.hiddenTabUUIDs ?? []).compactMap(UUID.init))
    }
}
