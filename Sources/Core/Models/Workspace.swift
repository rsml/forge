import Foundation
import Observation

@Observable
@MainActor
public final class Workspace {
    public var projects: [Project] = []
    public var activeProjectId: String?
    public var activeTabId: String?
    public var activePaneId: String?
    public var connected: Bool = false

    public init() {}

    public var activeProject: Project? {
        projects.first { $0.id == activeProjectId }
    }

    public func project(byId id: String) -> Project? {
        projects.first { $0.id == id }
    }

    /// Find a tab by its stable UUID, returning the owning project alongside it.
    public func findTab(byUUID uuid: UUID) -> (project: Project, tab: Tab)? {
        for project in projects {
            if let tab = project.tabs.first(where: { $0.uuid == uuid }) {
                return (project, tab)
            }
        }
        return nil
    }

    /// Find the tab that owns the given pane.
    public func findTab(byPaneId paneId: String) -> (project: Project, tab: Tab)? {
        for project in projects {
            for tab in project.tabs where tab.panes.contains(where: { $0.id == paneId }) {
                return (project, tab)
            }
        }
        return nil
    }

    /// Find a pane by its ID, returning the owning project and tab.
    public func findPane(byId paneId: String) -> (project: Project, tab: Tab, pane: Pane)? {
        for project in projects {
            for tab in project.tabs {
                if let pane = tab.panes.first(where: { $0.id == paneId }) {
                    return (project, tab, pane)
                }
            }
        }
        return nil
    }
}
