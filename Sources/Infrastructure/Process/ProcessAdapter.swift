import AppKit
import ForgeCore

/// ProcessPort implementation using GhosttyKit EXEC mode.
/// Each create() spawns a Ghostty surface that owns its PTY natively.
@MainActor
final class ProcessAdapter: ProcessPort {
    private let ghosttyApp: GhosttyApp

    init(ghosttyApp: GhosttyApp) {
        self.ghosttyApp = ghosttyApp
    }

    func create(cwd: String, env: [String: String]) -> PaneHandle {
        let id = UUID().uuidString
        let renderer = GhosttyRenderer(ghosttyApp: ghosttyApp, cwd: cwd, env: env)
        return PaneHandle(id: id, surface: renderer)
    }

    func kill(_ handle: PaneHandle) {
        // Surface destruction closes Ghostty's fd → SIGHUP → process dies.
        // GhosttyRenderer.deinit calls ghostty_surface_free.
        // Setting the handle's surface to nil triggers ARC release.
    }
}
