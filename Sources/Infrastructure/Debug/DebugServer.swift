import Foundation
import AppKit
import Network
import ForgeCore

/// Lightweight HTTP debug server running inside Forge.
/// Lets Claude (or any tool) take screenshots, read state, and send actions.
///
/// Endpoints:
///   GET  /screenshot    — PNG of the app window
///   GET  /state         — JSON workspace state
///   POST /action        — execute an action (body: {"action": "...", "args": {...}})
///   GET  /logs          — recent log lines
///   GET  /ping          — health check
@MainActor
final class DebugServer {
    private var listener: NWListener?
    weak var controller: WorkspaceController?
    let port: UInt16

    init(port: UInt16 = 7654) {
        self.port = port
    }

    func start(controller: WorkspaceController) {
        self.controller = controller

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!) else {
            ForgeLog.log("[debug] Failed to create listener on port \(port)")
            return
        }

        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ForgeLog.log("[debug] Server listening on http://localhost:\(self.port)")
            case .failed(let error):
                ForgeLog.log("[debug] Server failed: \(error)")
            default:
                break
            }
        }

        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        // Accumulate data until we have the full HTTP request (headers + body)
        receiveFullRequest(connection: connection, accumulated: Data())
    }

    private func receiveFullRequest(connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            guard let data, error == nil else { connection.cancel(); return }

            var all = accumulated
            all.append(data)

            let text = String(data: all, encoding: .utf8) ?? ""

            // Check if we have the full request (headers + body based on Content-Length)
            if let headerEnd = text.range(of: "\r\n\r\n") {
                let headers = String(text[..<headerEnd.lowerBound])
                let bodyReceived = text[headerEnd.upperBound...]

                // Parse Content-Length
                var expectedLength = 0
                for line in headers.split(separator: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        expectedLength = Int(line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "0") ?? 0
                    }
                }

                if bodyReceived.utf8.count >= expectedLength || isComplete {
                    Task { @MainActor in
                        let response = await self.handleRequest(text)
                        self.sendResponse(connection: connection, response: response)
                    }
                    return
                }
            }

            if isComplete {
                Task { @MainActor in
                    let response = await self.handleRequest(text)
                    self.sendResponse(connection: connection, response: response)
                }
            } else {
                // Need more data
                self.receiveFullRequest(connection: connection, accumulated: all)
            }
        }
    }

    private func sendResponse(connection: NWConnection, response: HTTPResponse) {
        var header = "HTTP/1.1 \(response.status)\r\n"
        header += "Content-Type: \(response.contentType)\r\n"
        header += "Content-Length: \(response.body.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        var fullData = header.data(using: .utf8)!
        fullData.append(response.body)

        connection.send(content: fullData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Request Routing

    private func handleRequest(_ raw: String) async -> HTTPResponse {
        let lines = raw.split(separator: "\r\n", maxSplits: 1)
        guard let requestLine = lines.first else {
            return HTTPResponse(status: "400 Bad Request", body: "Bad request".data(using: .utf8)!)
        }

        let parts = requestLine.split(separator: " ")
        let method = parts.count > 0 ? String(parts[0]) : "GET"
        let path = parts.count > 1 ? String(parts[1]) : "/"

        // Extract body for POST
        let body: String? = {
            guard let bodyStart = raw.range(of: "\r\n\r\n") else { return nil }
            let bodyStr = String(raw[bodyStart.upperBound...])
            return bodyStr.isEmpty ? nil : bodyStr
        }()

        switch (method, path) {
        case ("GET", "/ping"):
            return jsonResponse(["status": "ok", "app": "Forge"])

        case ("GET", "/screenshot"):
            return await screenshotResponse()

        case ("GET", "/state"):
            return stateResponse()

        case ("POST", "/action"):
            return await actionResponse(body: body)

        case ("GET", "/logs"):
            return logsResponse()

        default:
            return jsonResponse(["error": "Not found", "path": path], status: "404 Not Found")
        }
    }

}
