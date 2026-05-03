import Foundation
import Observation

@Observable
@MainActor
final class Workspace {
    var sessions: [Session] = []
    var activeSessionId: String?
    var activeWindowId: String?
    var activePaneId: String?
    var connected: Bool = false

    var activeSession: Session? {
        sessions.first { $0.id == activeSessionId }
    }

    func session(byId id: String) -> Session? {
        sessions.first { $0.id == id }
    }
}
