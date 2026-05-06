import AppKit
import ForgeDomain

/// Determines confirmation requirements for close/move operations.
/// Separates decision logic from NSAlert presentation.
enum CloseConfirmation {

    enum CloseTarget {
        case pane(id: String)
        case tab(Tab, in: Project)
        case project(Project)
    }

    struct AlertInfo {
        let message: String
        let info: String
        let action: String
        var style: NSAlert.Style = .warning
    }

    struct CloseDecision {
        let target: CloseTarget
        let alert: AlertInfo?
    }

    /// Determine what to close and whether confirmation is needed.
    @MainActor static func evaluate(
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

    /// Show an NSAlert for the given info. Returns true if user confirmed.
    @MainActor
    static func present(_ info: AlertInfo) -> Bool {
        let alert = NSAlert()
        alert.messageText = info.message
        alert.informativeText = info.info
        alert.addButton(withTitle: info.action)
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = info.style
        return alert.runModal() == .alertFirstButtonReturn
    }
}
