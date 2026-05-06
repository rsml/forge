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

    /// Find a tab by its tmux tab ID string, returning the owning project alongside it.
    public func findTab(byTmuxId tmuxId: String) -> (project: Project, tab: Tab)? {
        for project in projects {
            if let tab = project.tabs.first(where: { $0.id == tmuxId }) {
                return (project, tab)
            }
        }
        return nil
    }
}
