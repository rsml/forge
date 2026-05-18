/// Determines confirmation requirements for close operations.
/// Pure decision logic — no framework imports.
///
/// Target picking continues to be driven by `activePane`:
///   - multi-pane tab + activePane present → `.pane`
///   - single-pane tab in a multi-tab project → `.tab`
///   - last tab in the project           → `.project`
///
/// Alert construction is driven by `activities` (the foreground-process
/// snapshot for every pane in the resolved target) together with the
/// per-target `TabConfirmMode` settings. Pane closes use implicit
/// `.whenActive` semantics — no setting controls them.
public enum CloseConfirmation {

    public enum CloseTarget {
        case pane(id: String)
        case tab(Tab, in: Project)
        case project(Project)
    }

    public enum TabConfirmMode: String, Codable {
        case never, whenActive, always
    }

    public struct AlertInfo {
        public let message: String
        public let info: String
        public let action: String

        public init(message: String, info: String, action: String) {
            self.message = message
            self.info = info
            self.action = action
        }
    }

    public struct CloseDecision {
        public let target: CloseTarget
        public let alert: AlertInfo?

        public init(target: CloseTarget, alert: AlertInfo?) {
            self.target = target
            self.alert = alert
        }
    }

    /// Decide what to close and whether to prompt.
    @MainActor public static func evaluate(
        project: Project,
        tab: Tab,
        activePane: Pane?,
        activities: [PaneActivity],
        confirmCloseTab: TabConfirmMode,
        confirmCloseProject: TabConfirmMode
    ) -> CloseDecision {
        let target = resolveTarget(project: project, tab: tab, activePane: activePane)
        let activesInTarget = activesIn(target: target, project: project, tab: tab, activities: activities)
        let alert = buildAlert(
            target: target, project: project,
            activesInTarget: activesInTarget,
            confirmCloseTab: confirmCloseTab,
            confirmCloseProject: confirmCloseProject
        )
        return CloseDecision(target: target, alert: alert)
    }

    // MARK: - Target picking (unchanged semantics)

    @MainActor private static func resolveTarget(
        project: Project, tab: Tab, activePane: Pane?
    ) -> CloseTarget {
        let hasMultiplePanes = tab.panes.count > 1
        let hasMultipleTabs = project.tabs.count > 1
        if hasMultiplePanes, let pane = activePane {
            return .pane(id: pane.id)
        } else if hasMultipleTabs {
            return .tab(tab, in: project)
        } else {
            return .project(project)
        }
    }

    // MARK: - Active-pane scope (which panes the target controls)

    @MainActor private static func activesIn(
        target: CloseTarget, project: Project, tab: Tab, activities: [PaneActivity]
    ) -> [PaneActivity] {
        let targetPaneIds: Set<String>
        switch target {
        case .pane(let id):
            targetPaneIds = [id]
        case .tab:
            targetPaneIds = Set(tab.panes.map(\.id))
        case .project:
            targetPaneIds = Set(project.tabs.flatMap { $0.panes.map(\.id) })
        }

        // Index lookup so we can deterministically pick the "first" active pane.
        var indexById: [String: Int] = [:]
        for proj in [project] {
            for t in proj.tabs {
                for p in t.panes {
                    indexById[p.id] = p.index
                }
            }
        }
        // The target may also contain panes not enumerated above (shouldn't
        // happen in practice, but be defensive). Default to Int.max so they
        // sort last.
        return activities
            .filter { $0.isActive && targetPaneIds.contains($0.paneId) }
            .sorted { (indexById[$0.paneId] ?? Int.max) < (indexById[$1.paneId] ?? Int.max) }
    }

    // MARK: - Alert construction

    @MainActor private static func buildAlert(
        target: CloseTarget, project: Project,
        activesInTarget: [PaneActivity],
        confirmCloseTab: TabConfirmMode,
        confirmCloseProject: TabConfirmMode
    ) -> AlertInfo? {
        switch target {
        case .pane:
            // Pane close = implicit .whenActive. No setting consulted.
            guard !activesInTarget.isEmpty else { return nil }
            return activeCopy(target: target, project: project, actives: activesInTarget)

        case .tab:
            return alertForMode(
                mode: confirmCloseTab,
                target: target, project: project,
                actives: activesInTarget
            )

        case .project:
            return alertForMode(
                mode: confirmCloseProject,
                target: target, project: project,
                actives: activesInTarget
            )
        }
    }

    @MainActor private static func alertForMode(
        mode: TabConfirmMode,
        target: CloseTarget, project: Project,
        actives: [PaneActivity]
    ) -> AlertInfo? {
        switch mode {
        case .never:
            return nil
        case .whenActive:
            guard !actives.isEmpty else { return nil }
            return activeCopy(target: target, project: project, actives: actives)
        case .always:
            if actives.isEmpty {
                return idleCopy(target: target, project: project)
            }
            return activeCopy(target: target, project: project, actives: actives)
        }
    }

    // MARK: - Copy

    @MainActor private static func activeCopy(
        target: CloseTarget, project: Project, actives: [PaneActivity]
    ) -> AlertInfo {
        // Caller guarantees actives.first exists.
        let first = actives.first!
        let cmd = first.command ?? "a process"
        let cmdPhrase = "\"\(cmd)\""
        let extras = actives.count - 1
        let suffix = extras > 0
            ? " (and \(extras) other process\(extras == 1 ? "" : "es"))"
            : ""

        let message: String
        let action: String
        switch target {
        case .pane:
            message = "Closing this pane will terminate \(cmdPhrase)\(suffix)."
            action = "Close Pane"
        case .tab:
            message = "Closing this tab will terminate \(cmdPhrase)\(suffix)."
            action = "Close Tab"
        case .project:
            message = "Closing \"\(project.name)\" will terminate \(cmdPhrase)\(suffix)."
            action = "Close Project"
        }
        return AlertInfo(message: message, info: "", action: action)
    }

    @MainActor private static func idleCopy(
        target: CloseTarget, project: Project
    ) -> AlertInfo {
        switch target {
        case .pane:
            // Pane close has implicit .whenActive — no idle copy is ever shown.
            // Returning a defensive fallback keeps the function total.
            return AlertInfo(
                message: "Closing this pane will close it permanently.",
                info: "", action: "Close Pane"
            )
        case .tab:
            return AlertInfo(
                message: "Closing this tab will close it permanently.",
                info: "", action: "Close Tab"
            )
        case .project:
            return AlertInfo(
                message: "Closing \"\(project.name)\" will close all tabs and remove the project from Forge.",
                info: "", action: "Close Project"
            )
        }
    }
}
