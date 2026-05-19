import Foundation
import ForgeCore

/// `PaneActivityPort` implementation for tmux mode.
///
/// Reads `pane.terminalState.status == .running` from the in-memory `Workspace` — already
/// kept in sync by the refresh cycle (`StateMerger`). Uses `currentCommand`
/// as the displayed command name. No tmux round-trip; the data is local.
///
/// Browser panes are answered via `BrowserActivityResolver` — a loaded URL
/// counts as active, with the page title (or host) as the command name.
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

            let (browsers, terminalIds) = BrowserActivityResolver.partition(
                paneIds: paneIds, workspace: workspace
            )

            var byId: [String: Pane] = [:]
            for project in workspace.projects {
                for tab in project.tabs {
                    for pane in tab.panes { byId[pane.id] = pane }
                }
            }
            let terminals: [PaneActivity] = terminalIds.map { id in
                guard let pane = byId[id], let ts = pane.terminalState else {
                    return PaneActivity(paneId: id, isActive: false, command: nil)
                }
                let isActive = ts.status == .running
                let command = isActive && !ts.currentCommand.isEmpty ? ts.currentCommand : nil
                return PaneActivity(paneId: id, isActive: isActive, command: command)
            }
            return browsers + terminals
        }
    }
}
