/// Determines confirmation requirements for close operations.
/// Pure decision logic — no framework imports.
///
/// The caller picks the *level* (pane, tab, project) by passing the
/// appropriate `CloseTarget`. This module does *not* auto-cascade: a pane
/// close stays a pane prompt even if it happens to be the only pane in
/// the only tab in the only project. The cascade is real (everything
/// closes), but the prompt speaks at the granularity the user acted on.
///
/// Each level has its own `TabConfirmMode` setting (`confirmClosePane`,
/// `confirmCloseTab`, `confirmCloseProject`).
public enum CloseConfirmation {

    public enum CloseTarget {
        case pane(id: String)
        case tab(Tab, in: Project)
        case project(Project)
    }

    public enum TabConfirmMode: String, Codable {
        case never, whenActive, always
    }

    public struct AlertInfo: Equatable {
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

    /// Decide whether to prompt for the given target.
    ///
    /// `activities` is the foreground-process snapshot for every pane *in scope*
    /// of the target (the daemon may return more — anything outside scope is
    /// ignored). Modes are consulted by target type: `.pane` consults
    /// `confirmClosePane`, etc.
    @MainActor public static func evaluate(
        target: CloseTarget,
        activities: [PaneActivity],
        confirmClosePane: TabConfirmMode,
        confirmCloseTab: TabConfirmMode,
        confirmCloseProject: TabConfirmMode
    ) -> CloseDecision {
        let mode = modeFor(target: target,
                           pane: confirmClosePane,
                           tab: confirmCloseTab,
                           project: confirmCloseProject)
        let actives = activesIn(target: target, activities: activities)
        let alert = buildAlert(target: target, actives: actives, mode: mode)
        return CloseDecision(target: target, alert: alert)
    }

    // MARK: - Mode selection

    @MainActor private static func modeFor(
        target: CloseTarget,
        pane: TabConfirmMode, tab: TabConfirmMode, project: TabConfirmMode
    ) -> TabConfirmMode {
        switch target {
        case .pane: return pane
        case .tab: return tab
        case .project: return project
        }
    }

    // MARK: - Activity scoping

    /// Filter activities down to those that belong to the target's scope, and
    /// sort them in stable display order (by pane index — across tabs for
    /// project targets, since each pane has a tab-local index, prefer
    /// (tabIndex, paneIndex)).
    @MainActor private static func activesIn(
        target: CloseTarget,
        activities: [PaneActivity]
    ) -> [PaneActivity] {
        let scopedIds: Set<String>
        var sortKey: [String: (Int, Int)] = [:]
        switch target {
        case .pane(let id):
            scopedIds = [id]
        case .tab(let tab, _):
            scopedIds = Set(tab.panes.map(\.id))
            for p in tab.panes { sortKey[p.id] = (tab.index, p.index) }
        case .project(let project):
            scopedIds = Set(project.tabs.flatMap { $0.panes.map(\.id) })
            for t in project.tabs {
                for p in t.panes { sortKey[p.id] = (t.index, p.index) }
            }
        }
        return activities
            .filter { $0.isActive && scopedIds.contains($0.paneId) }
            .sorted { lhs, rhs in
                let l = sortKey[lhs.paneId] ?? (.max, .max)
                let r = sortKey[rhs.paneId] ?? (.max, .max)
                return l < r
            }
    }

    // MARK: - Alert construction

    @MainActor private static func buildAlert(
        target: CloseTarget,
        actives: [PaneActivity],
        mode: TabConfirmMode
    ) -> AlertInfo? {
        switch mode {
        case .never:
            return nil
        case .whenActive:
            guard !actives.isEmpty else { return nil }
            return activeCopy(target: target, actives: actives)
        case .always:
            if actives.isEmpty { return idleCopy(target: target) }
            return activeCopy(target: target, actives: actives)
        }
    }

    /// Multi-active aware. One active → name it inline. Two or more → state
    /// the count in the message, list the names in the informative text
    /// (Apple HIG: details belong in info, not in message).
    @MainActor private static func activeCopy(
        target: CloseTarget, actives: [PaneActivity]
    ) -> AlertInfo {
        let names = actives.map { $0.command ?? "a process" }
        let levelName = levelPhrase(target: target)
        let action = actionLabel(target: target)

        if names.count == 1 {
            return AlertInfo(
                message: "Closing \(levelName) will terminate \"\(names[0])\".",
                info: "",
                action: action
            )
        }

        let message = "Closing \(levelName) will terminate \(names.count) running processes."
        return AlertInfo(message: message, info: nameList(names), action: action)
    }

    @MainActor private static func idleCopy(target: CloseTarget) -> AlertInfo {
        switch target {
        case .pane:
            // Pane close with `.always` mode and no active process: rare but
            // possible. Keep the function total.
            return AlertInfo(
                message: "Closing this pane will close it permanently.",
                info: "", action: "Close Pane"
            )
        case .tab:
            return AlertInfo(
                message: "Closing this tab will close it permanently.",
                info: "", action: "Close Tab"
            )
        case .project(let project):
            return AlertInfo(
                message: "Closing \"\(project.name)\" will close all tabs and remove the project from Forge.",
                info: "", action: "Close Project"
            )
        }
    }

    // MARK: - Copy helpers

    @MainActor private static func levelPhrase(target: CloseTarget) -> String {
        switch target {
        case .pane: return "this pane"
        case .tab: return "this tab"
        case .project(let project): return "\"\(project.name)\""
        }
    }

    @MainActor private static func actionLabel(target: CloseTarget) -> String {
        switch target {
        case .pane: return "Close Pane"
        case .tab: return "Close Tab"
        case .project: return "Close Project"
        }
    }

    /// Render a list of names for the informative text. Cap visible list at
    /// 5; anything beyond rolls up into "and N more".
    private static let maxVisibleNames = 5

    private static func nameList(_ names: [String]) -> String {
        guard names.count > maxVisibleNames else {
            return names.joined(separator: ", ")
        }
        let shown = names.prefix(maxVisibleNames).joined(separator: ", ")
        let extra = names.count - maxVisibleNames
        return "\(shown), and \(extra) more"
    }
}
