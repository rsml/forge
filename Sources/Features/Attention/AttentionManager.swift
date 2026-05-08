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

    var currentTabUUID: UUID? { queue.peek() }
    var nextWindowUUID: UUID? { queue.peekSecond() }
    var queueCount: Int { queue.count }

    init(notifier: any NotificationPort, config: ForgeConfigStore) {
        self.notifier = notifier
        self.config = config
        self.hiddenSet = loadHiddenSet(from: config)
    }

    /// Call after initial tmux sync to prune stale UUIDs from a previous project.
    func pruneStaleHiddenEntries(validUUIDs: Set<UUID>) {
        let stale = hiddenSet.subtracting(validUUIDs)
        if !stale.isEmpty {
            hiddenSet.subtract(stale)
            persistHiddenSet()
        }
    }

    func handleEvent(_ event: AttentionEvent) {
        let uuid = event.tabUUID
        guard !hiddenSet.contains(uuid) else { return }
        queue.enqueue(uuid)

        let settings = config.config.stackView
        if settings?.notify == "always" && config.config.notifications?.enabled == true {
            Task { await notifier.send(title: "Terminal needs attention", body: "A terminal is waiting for input", sound: config.config.notifications?.sound) }
        }
        if settings?.bringToForeground == "always" {
            NSApp.activate()
        }
    }

    func markDone(_ tabUUID: UUID) {
        queue.remove(tabUUID)
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
    }

    func isHidden(_ tabUUID: UUID) -> Bool {
        hiddenSet.contains(tabUUID)
    }

    func promoteToFront(_ tabUUID: UUID) {
        queue.remove(tabUUID)
        queue.insertAtFront(tabUUID)
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
