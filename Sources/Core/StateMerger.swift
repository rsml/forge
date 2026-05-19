import Foundation

/// Pure state reconciliation between tmux output and domain models.
/// Extracted from WorkspaceController to enable unit testing.
@MainActor
public enum StateMerger {

    public enum PaneEvent: Equatable, Sendable {
        case bell(tabUUID: UUID)
        case silenceCleared(tabUUID: UUID)
        case commandCompleted(tabUUID: UUID)
        case contentMatch(tabUUID: UUID)
    }

    /// Reconcile live tmux sessions with the workspace's project list.
    /// Updates existing projects in-place, removes dead ones, appends new ones.
    public static func mergeProjects(_ workspace: Workspace, with infos: [ProjectInfo]) {
        let infoById = Dictionary(uniqueKeysWithValues: infos.map { ($0.id, $0) })

        for project in workspace.projects {
            if let info = infoById[project.id] {
                project.name = info.name
                project.tabCount = info.tabCount
                project.attached = info.attached
                project.path = info.path
            }
        }

        let liveIds = Set(infos.map(\.id))
        let oldActiveId = workspace.activeProjectId
        let oldIndex = oldActiveId.flatMap { id in workspace.projects.firstIndex(where: { $0.id == id }) }
        let removedActive = oldActiveId.map { !liveIds.contains($0) } ?? false

        workspace.projects.removeAll { !liveIds.contains($0.id) }

        let existingIds = Set(workspace.projects.map(\.id))
        for info in infos where !existingIds.contains(info.id) {
            workspace.projects.append(Project(id: info.id, name: info.name,
                                              tabCount: info.tabCount,
                                              attached: info.attached, path: info.path))
        }

        if removedActive, !workspace.projects.isEmpty {
            let fallbackIndex: Int
            if let oldIndex {
                fallbackIndex = oldIndex > 0 ? oldIndex - 1 : 0
            } else {
                fallbackIndex = 0
            }
            let target = workspace.projects[min(fallbackIndex, workspace.projects.count - 1)]
            workspace.activeProjectId = target.id
            if let tab = target.tabs.first(where: { $0.active }) ?? target.tabs.first {
                workspace.activeTabId = tab.id
            }
        } else if workspace.activeProjectId == nil, let first = workspace.projects.first {
            workspace.activeProjectId = first.id
        }
    }

    /// Reconcile live tmux windows with a project's tab list.
    /// Returns the active tab ID if this is the active project.
    public static func mergeTabs(project: Project, with infos: [TabInfo],
                                 activeProjectId: String?) -> String? {
        let infoById = Dictionary(uniqueKeysWithValues: infos.map { ($0.id, $0) })

        for tab in project.tabs {
            if let info = infoById[tab.id] {
                tab.index = info.index
                tab.name = info.name
                tab.active = info.active
                tab.layout = info.layout
            }
        }

        let liveIds = Set(infos.map(\.id))
        project.tabs.removeAll { !liveIds.contains($0.id) }

        let existingIds = Set(project.tabs.map(\.id))
        for info in infos where !existingIds.contains(info.id) {
            project.tabs.append(Tab(id: info.id, projectId: info.projectId,
                                    index: info.index, name: info.name, active: info.active))
        }

        if let active = infos.first(where: { $0.active }),
           project.id == activeProjectId {
            return active.id
        }
        return nil
    }

    /// Reconcile live tmux panes with a tab's pane list.
    /// Returns the active pane ID (if any) and attention-relevant events.
    public static func mergePanes(tab: Tab, with infos: [PaneInfo]) -> (activePaneId: String?, events: [PaneEvent]) {
        var events: [PaneEvent] = []
        var updated: [Pane] = []

        for info in infos {
            if let existing = tab.panes.first(where: { $0.id == info.id }) {
                existing.index = info.index
                existing.active = info.active

                // tmux PaneInfo only describes terminal panes. Browser panes
                // are Forge-owned and never appear here; skip the terminal merge.
                guard let ts = existing.terminalState else {
                    updated.append(existing)
                    continue
                }

                let wasRunning = PaneStatus.from(command: ts.currentCommand) == .running
                let nowIdle = PaneStatus.from(command: info.currentCommand) == .idle
                if wasRunning && nowIdle {
                    events.append(.commandCompleted(tabUUID: tab.uuid))
                }

                let wasIdle = PaneStatus.from(command: ts.currentCommand) == .idle
                let nowRunning = PaneStatus.from(command: info.currentCommand) == .running
                if wasIdle && nowRunning {
                    ts.hasBell = false
                }

                ts.previousCommand = ts.currentCommand
                ts.currentCommand = info.currentCommand
                ts.currentPath = info.currentPath
                ts.width = info.width
                ts.height = info.height
                ts.pid = info.pid
                ts.status = ts.hasBell ? .needsAttention : PaneStatus.from(command: info.currentCommand)
                updated.append(existing)
            } else {
                updated.append(Pane(id: info.id, tabId: info.tabId, index: info.index,
                                    active: info.active, currentCommand: info.currentCommand,
                                    currentPath: info.currentPath, width: info.width,
                                    height: info.height, pid: info.pid))
            }
        }

        tab.panes = updated
        let activePaneId = infos.first(where: { $0.active })?.id
        return (activePaneId, events)
    }
}
