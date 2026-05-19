import Foundation
import AppKit
import ForgeCore

/// Diagnostic endpoints for the reconnection bifurcation harness.
/// These are read-only and side-effect-free. Safe to call repeatedly.
extension DebugServer {

    /// GET /surface-text/<paneId>
    /// Returns the visible viewport grid as plaintext (cells joined by lines).
    /// 404 if the pane has no renderer or the renderer can't read.
    func surfaceTextResponse(paneId: String) -> HTTPResponse {
        guard let ctrl = controller else {
            return jsonResponse(["error": "No controller"])
        }
        guard let renderer = ctrl.paneRenderers[paneId] as? GhosttyRenderer else {
            return jsonResponse(
                ["error": "No renderer for pane", "paneId": paneId],
                status: "404 Not Found"
            )
        }
        guard let text = renderer.readVisibleText() else {
            return jsonResponse(
                ["error": "Surface read failed", "paneId": paneId],
                status: "503 Service Unavailable"
            )
        }
        // Plain text response — easier to grep + diff than JSON.
        return HTTPResponse(
            status: "200 OK",
            contentType: "text/plain; charset=utf-8",
            body: Data(text.utf8)
        )
    }

    /// GET /pty-tail/<paneId>?bytes=N
    /// Returns the last N bytes of ~/.config/forge/scrollback/<paneId>.log
    /// as application/octet-stream (raw bytes — includes ANSI escapes).
    func ptyTailResponse(paneId: String, bytes: Int) -> HTTPResponse {
        let path = NSHomeDirectory() + "/.config/forge/scrollback/\(paneId).log"
        guard FileManager.default.fileExists(atPath: path) else {
            return jsonResponse(
                ["error": "Scrollback log not found", "paneId": paneId, "path": path],
                status: "404 Not Found"
            )
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return jsonResponse(
                ["error": "Failed to read scrollback log", "paneId": paneId],
                status: "500 Internal Server Error"
            )
        }
        let tail = data.suffix(bytes)
        return HTTPResponse(
            status: "200 OK",
            contentType: "application/octet-stream",
            body: Data(tail)
        )
    }

    /// Parse a single name=value pair out of a URL query string.
    func parseQueryParam(_ query: String, name: String) -> String? {
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            if parts[0] == Substring(name) {
                return String(parts[1])
            }
        }
        return nil
    }
}
