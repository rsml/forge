import Foundation
import AppKit

/// Routes decoded %output data to per-pane TerminalRenderer instances.
/// Buffers output for panes that don't have a renderer yet (e.g. newly
/// split panes whose renderer hasn't been created by updateRenderers).
@MainActor
final class OutputRouter {
    private var renderers: [String: TerminalRenderer] = [:]
    /// Buffered output for panes awaiting renderer registration.
    private var pendingOutput: [String: Data] = [:]
    /// Max bytes to buffer per pane before dropping oldest data.
    private let maxBufferSize = 65_536

    func register(paneId: String, renderer: TerminalRenderer) {
        renderers[paneId] = renderer
        // Replay any output that arrived before the renderer existed.
        if let buffered = pendingOutput.removeValue(forKey: paneId) {
            ForgeLog.log("[debug] OutputRouter: replaying \(buffered.count) buffered bytes for pane \(paneId)")
            renderer.feed(buffered)
        }
    }

    func unregister(paneId: String) {
        renderers.removeValue(forKey: paneId)
        pendingOutput.removeValue(forKey: paneId)
    }

    func unregisterAll() {
        renderers.removeAll()
        pendingOutput.removeAll()
    }

    func route(paneId: String, data: Data) {
        if let renderer = renderers[paneId] {
            renderer.feed(data)
        } else {
            // Buffer until a renderer registers for this pane.
            var buf = pendingOutput[paneId] ?? Data()
            buf.append(data)
            if buf.count > maxBufferSize {
                buf = buf.suffix(maxBufferSize)
            }
            pendingOutput[paneId] = buf
            ForgeLog.log("[debug] OutputRouter: buffering \(data.count) bytes for pane \(paneId) (total \(buf.count))")
        }
    }

    func hasRenderer(for paneId: String, matching renderer: TerminalRenderer) -> Bool {
        renderers[paneId] === renderer
    }
}
