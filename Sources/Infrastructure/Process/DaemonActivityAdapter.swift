import Foundation
import ForgeCore

/// `PaneActivityPort` implementation for native PTY mode.
///
/// Wraps `DaemonAdapter.isActive(paneIds:)` which races a 200ms timeout
/// against the daemon RPC. On any failure (socket error, timeout, garbage
/// response), this adapter fails open — every pane reports as idle — so a
/// flaky daemon cannot block a close operation.
@MainActor
final class DaemonActivityAdapter: PaneActivityPort {
    private let daemon: DaemonAdapter

    init(daemon: DaemonAdapter) {
        self.daemon = daemon
    }

    nonisolated func query(paneIds: [String]) async -> [PaneActivity] {
        guard !paneIds.isEmpty else { return [] }
        do {
            let results = try await daemon.isActive(paneIds: paneIds)
            return results.map {
                PaneActivity(paneId: $0.paneId, isActive: $0.isActive, command: $0.command)
            }
        } catch {
            await MainActor.run {
                ForgeLog.log("[daemon] activity query failed: \(error) — fail-open")
            }
            return paneIds.map { PaneActivity(paneId: $0, isActive: false, command: nil) }
        }
    }
}
