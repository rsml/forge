import Foundation
import ForgeCore

/// `PaneActivityPort` implementation for native PTY mode.
///
/// Wraps `DaemonAdapter.isActive(paneIds:)` which races a 200ms timeout
/// against the daemon RPC. On any failure (socket error, timeout, garbage
/// response), this adapter fails open — every pane reports as idle — so a
/// flaky daemon cannot block a close operation.
///
/// Browser panes are answered locally from the in-memory workspace — the
/// daemon owns shell PTYs only, it has no concept of a loaded web page.
/// A browser pane with any loaded URL counts as active, with the page title
/// (or host, or full URL) serving as the displayed "command name" in the
/// close-confirmation alert.
@MainActor
final class DaemonActivityAdapter: PaneActivityPort {
    private let daemon: DaemonAdapter
    private weak var workspace: Workspace?

    init(daemon: DaemonAdapter, workspace: Workspace) {
        self.daemon = daemon
        self.workspace = workspace
    }

    nonisolated func query(paneIds: [String]) async -> [PaneActivity] {
        guard !paneIds.isEmpty else { return [] }

        // Resolve browser panes locally (no daemon round-trip) and let the
        // daemon answer terminal panes. The merge below preserves caller
        // ordering by paneIds where possible.
        let (browserResults, terminalIds) = await MainActor.run {
            BrowserActivityResolver.partition(paneIds: paneIds, workspace: self.workspace)
        }

        guard !terminalIds.isEmpty else { return browserResults }

        do {
            let results = try await daemon.isActive(paneIds: terminalIds)
            let terminalActivities = results.map {
                PaneActivity(paneId: $0.paneId, isActive: $0.isActive, command: $0.command)
            }
            return browserResults + terminalActivities
        } catch {
            await MainActor.run {
                ForgeLog.log("[daemon] activity query failed: \(error) — fail-open")
            }
            let idleTerminals = terminalIds.map {
                PaneActivity(paneId: $0, isActive: false, command: nil)
            }
            return browserResults + idleTerminals
        }
    }
}
