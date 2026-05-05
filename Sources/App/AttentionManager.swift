import Foundation
import Observation
import AppKit
import ForgeDomain

@Observable @MainActor
final class AttentionManager: AttentionPort {
    private var queue = AttentionQueue()
    private(set) var hiddenSet: Set<UUID> = []
    private let notifier: any NotificationPort
    private let config: ForgeConfigStore

    var currentWindowUUID: UUID? { queue.peek() }
    var queueCount: Int { queue.count }

    init(notifier: any NotificationPort, config: ForgeConfigStore) {
        self.notifier = notifier
        self.config = config
        self.hiddenSet = loadHiddenSet(from: config)
    }

    /// Call after initial tmux sync to prune stale UUIDs from a previous session.
    func pruneStaleHiddenEntries(validUUIDs: Set<UUID>) {
        let stale = hiddenSet.subtracting(validUUIDs)
        if !stale.isEmpty {
            hiddenSet.subtract(stale)
            persistHiddenSet()
        }
    }

    func handleEvent(_ event: AttentionEvent) {
        let uuid = event.windowUUID
        guard !hiddenSet.contains(uuid) else { return }
        queue.enqueue(uuid)

        let settings = config.config.stackView
        if settings?.notify == "always" {
            Task { await notifier.send(title: "Terminal needs attention", body: "A terminal is waiting for input", sound: settings?.notificationSound) }
        }
        if settings?.bringToForeground == "always" {
            NSApp.activate()
        }
    }

    func markDone(_ windowUUID: UUID) {
        queue.remove(windowUUID)
    }

    func hide(_ windowUUID: UUID) {
        queue.remove(windowUUID)
        hiddenSet.insert(windowUUID)
        persistHiddenSet()
    }

    func moveToBack(_ windowUUID: UUID) {
        queue.moveToBack(windowUUID)
    }

    func unhide(_ windowUUID: UUID) {
        hiddenSet.remove(windowUUID)
        persistHiddenSet()
    }

    func removeWindow(_ windowUUID: UUID) {
        queue.remove(windowUUID)
        hiddenSet.remove(windowUUID)
    }

    func needsAttention(_ windowUUID: UUID) -> Bool {
        queue.contains(windowUUID)
    }

    func isHidden(_ windowUUID: UUID) -> Bool {
        hiddenSet.contains(windowUUID)
    }

    func promoteToFront(_ windowUUID: UUID) {
        queue.remove(windowUUID)
        queue.insertAtFront(windowUUID)
    }

    private func persistHiddenSet() {
        // Capture hiddenSet as a local value to avoid @Observable accessor
        // issues inside the inout ForgeConfig closure.
        let uuids = hiddenSet.map(\.uuidString)
        config.update { config in
            if config.stackView == nil {
                config.stackView = ForgeConfig.StackViewSettings()
            }
            config.stackView?.hiddenWindowUUIDs = uuids
        }
    }

    private func loadHiddenSet(from config: ForgeConfigStore) -> Set<UUID> {
        Set((config.config.stackView?.hiddenWindowUUIDs ?? []).compactMap(UUID.init))
    }
}
