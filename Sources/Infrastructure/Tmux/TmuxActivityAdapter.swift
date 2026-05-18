import Foundation
import ForgeCore

/// `PaneActivityPort` implementation for tmux mode.
///
/// Reads `pane.status == .running` from the in-memory `Workspace` — already
/// kept in sync by the refresh cycle (`StateMerger`). Uses `currentCommand`
/// as the displayed command name. No tmux round-trip; the data is local.
@MainActor
final class TmuxActivityAdapter: PaneActivityPort {
    private weak var workspace: Workspace?

    init(workspace: Workspace) {
        self.workspace = workspace
    }

    nonisolated func query(paneIds: [String]) async -> [PaneActivity] {
        await MainActor.run {
            guard let workspace else {
                return paneIds.map { PaneActivity(paneId: $0, isActive: false, command: nil) }
            }
            var byId: [String: Pane] = [:]
            for project in workspace.projects {
                for tab in project.tabs {
                    for pane in tab.panes { byId[pane.id] = pane }
                }
            }
            return paneIds.map { id in
                guard let pane = byId[id] else {
                    return PaneActivity(paneId: id, isActive: false, command: nil)
                }
                let isActive = pane.status == .running
                let command = isActive && !pane.currentCommand.isEmpty ? pane.currentCommand : nil
                return PaneActivity(paneId: id, isActive: isActive, command: command)
            }
        }
    }
}
