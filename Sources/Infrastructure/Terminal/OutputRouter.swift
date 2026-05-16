import Foundation
import AppKit

/// Routes decoded %output data to per-pane TerminalRenderer instances.
@MainActor
final class OutputRouter {
    private var renderers: [String: TerminalRenderer] = [:]

    func register(paneId: String, renderer: TerminalRenderer) {
        renderers[paneId] = renderer
    }

    func unregister(paneId: String) {
        renderers.removeValue(forKey: paneId)
    }

    func unregisterAll() {
        renderers.removeAll()
    }

    func route(paneId: String, data: Data) {
        if renderers[paneId] == nil {
            ForgeLog.log("[debug] OutputRouter: no renderer for pane \(paneId) (\(data.count) bytes dropped)")
        }
        renderers[paneId]?.feed(data)
    }

    func hasRenderer(for paneId: String, matching renderer: TerminalRenderer) -> Bool {
        renderers[paneId] === renderer
    }
}
