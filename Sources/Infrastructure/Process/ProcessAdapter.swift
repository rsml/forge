import AppKit
import ForgeCore

/// ProcessPort implementation using GhosttyKit EXEC mode.
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
        // GhosttyRenderer.deinit calls ghostty_surface_free → SIGHUP → process dies.
    }
}
