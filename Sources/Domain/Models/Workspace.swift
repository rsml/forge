import Foundation
import Observation

@Observable
@MainActor
public final class Workspace {
    public var sessions: [Session] = []
    public var activeSessionId: String?
    public var activeWindowId: String?
    public var activePaneId: String?
    public var connected: Bool = false

    public init() {}

    public var activeSession: Session? {
        sessions.first { $0.id == activeSessionId }
    }

    public func session(byId id: String) -> Session? {
        sessions.first { $0.id == id }
    }

    /// Find a window by its stable UUID, returning the owning session alongside it.
    public func findWindow(byUUID uuid: UUID) -> (session: Session, window: Window)? {
        for session in sessions {
            if let window = session.windows.first(where: { $0.uuid == uuid }) {
                return (session, window)
            }
        }
        return nil
    }

    /// Find a window by its tmux window ID string, returning the owning session alongside it.
    public func findWindow(byTmuxId tmuxId: String) -> (session: Session, window: Window)? {
        for session in sessions {
            if let window = session.windows.first(where: { $0.id == tmuxId }) {
                return (session, window)
            }
        }
        return nil
    }
}
