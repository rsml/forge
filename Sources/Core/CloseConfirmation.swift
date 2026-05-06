/// Determines confirmation requirements for close/move operations.
/// Pure decision logic — no framework imports.
public enum CloseConfirmation {

    public enum CloseTarget {
        case pane(id: String)
        case tab(Tab, in: Project)
        case project(Project)
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
    }

    /// Determine what to close and whether confirmation is needed.
    @MainActor public static func evaluate(
        project: Project, tab: Tab, activePane: Pane?,
        warnOnCloseProject: Bool, warnOnCloseTab: Bool
    ) -> CloseDecision {
        let hasMultiplePanes = tab.panes.count > 1
        let hasMultipleTabs = project.tabs.count > 1
        let isRunning = activePane?.status == .running

        let target: CloseTarget
        if hasMultiplePanes, let pane = activePane {
            target = .pane(id: pane.id)
        } else if hasMultipleTabs {
            target = .tab(tab, in: project)
        } else {
            target = .project(project)
        }

        let alert: AlertInfo?
        if isRunning {
            let processName = tab.name
            switch target {
            case .pane:
                alert = AlertInfo(message: "Close this pane?",
                                  info: "\"\(processName)\" is running in this pane.",
                                  action: "Close Pane")
            case .tab:
                alert = AlertInfo(message: "Close this tab?",
                                  info: "\"\(processName)\" is running in this tab.",
                                  action: "Close Tab")
            case .project:
                alert = AlertInfo(message: "Close project \"\(project.name)\"?",
                                  info: "\"\(processName)\" is running.",
                                  action: "Close Project")
            }
        } else {
            switch target {
            case .pane:
                alert = nil
            case .tab:
                alert = warnOnCloseTab ? AlertInfo(message: "Close tab \"\(tab.name)\"?",
                                                    info: "This tab will be closed.",
                                                    action: "Close Tab") : nil
            case .project:
                alert = warnOnCloseProject ? AlertInfo(message: "Close project \"\(project.name)\"?",
                                                        info: "This will close all tabs and remove the project from Forge.",
                                                        action: "Close Project") : nil
            }
        }

        return CloseDecision(target: target, alert: alert)
    }
}
