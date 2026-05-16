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
/// Resize and status are NOT here — Ghostty handles resize internally
/// via setFrameSize → ioctl(TIOCSWINSZ), and status arrives via
/// GhosttyKit's action_cb (COMMAND_FINISHED, CHILD_EXITED, BELL).
@MainActor
public protocol ProcessPort {
    func create(cwd: String, env: [String: String]) -> PaneHandle
    func kill(_ handle: PaneHandle)
}
