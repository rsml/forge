import Foundation

/// Bridging object for ghostty C void* callbacks to Swift objects.
/// Use Unmanaged.passRetained when creating, release in GhosttyRenderer.deinit.
final class GhosttyCallbackContext {
    weak var renderer: GhosttyRenderer?

    init(renderer: GhosttyRenderer) {
        self.renderer = renderer
    }
}
