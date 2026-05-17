import Foundation

/// Handle to a terminal surface with a running process.
/// Opaque to the domain — implementation details stay in Infrastructure.
public final class PaneHandle: @unchecked Sendable {
    public let id: String
    public let surface: AnyObject
    public init(id: String, surface: AnyObject) {
        self.id = id
        self.surface = surface
    }
}

/// Creates and manages terminal processes.
@MainActor
public protocol ProcessPort {
    func create(cwd: String, env: [String: String]) -> PaneHandle
    func kill(_ handle: PaneHandle)
}

/// Info about a persisted pane from the daemon.
public struct PersistedPaneInfo: Sendable {
    public let paneId: String
    public let pid: Int32
    public let cwd: String
    public let alive: Bool

    public init(paneId: String, pid: Int32, cwd: String, alive: Bool) {
        self.paneId = paneId; self.pid = pid; self.cwd = cwd; self.alive = alive
    }
}

/// Persists PTY file descriptors across app restarts via the forged daemon.
public protocol PersistencePort {
    func store(paneId: String, fd: Int32, pid: Int32, cwd: String) async throws
    func retrieve(paneId: String) async throws -> (fd: Int32, pid: Int32, cwd: String)?
    func list() async throws -> [PersistedPaneInfo]
    func release(paneId: String) async throws
}
