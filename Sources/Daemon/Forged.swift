import Foundation
import Darwin

/// forged — Forge PTY daemon.
/// Holds PTY master file descriptors so terminal processes survive Forge restarts.
/// Protocol: JSON messages over a Unix domain socket with fd passing via SCM_RIGHTS.
@main
struct Forged {
    /// Stored file descriptors: pane ID → (fd, metadata)
    /// nonisolated(unsafe): single-threaded daemon, no concurrency.
    nonisolated(unsafe) static var storedFDs: [String: StoredPane] = [:]
    nonisolated(unsafe) static var running = true
    nonisolated(unsafe) static var clientFDs: [Int32] = []

    struct StoredPane {
        let fd: Int32
        let pid: Int32
        let cwd: String
        let createdAt: Date
    }

    static func main() {
        let socketPath = CommandLine.arguments.count > 2 && CommandLine.arguments[1] == "--socket"
            ? CommandLine.arguments[2]
            : FDSocket.defaultSocketPath

        log("forged starting on \(socketPath)")

        // Raise fd limit
        var rlim = rlimit(rlim_cur: 10240, rlim_max: 10240)
        setrlimit(RLIMIT_NOFILE, &rlim)

        let serverFD: Int32
        do {
            serverFD = try FDSocket.listen(path: socketPath)
        } catch {
            log("Failed to listen: \(error)")
            exit(1)
        }

        // Make server socket non-blocking for poll
        fcntl(serverFD, F_SETFL, O_NONBLOCK)

        log("Listening on \(socketPath)")

        // Signal handling — clean shutdown
        signal(SIGTERM) { _ in Forged.running = false }
        signal(SIGINT) { _ in Forged.running = false }
        signal(SIGPIPE, SIG_IGN)

        // Main loop
        while running {
            // Poll for new connections and client messages
            var pollFDs = [pollfd(fd: serverFD, events: Int16(POLLIN), revents: 0)]
            for clientFD in clientFDs {
                pollFDs.append(pollfd(fd: clientFD, events: Int16(POLLIN), revents: 0))
            }

            let ready = poll(&pollFDs, UInt32(pollFDs.count), 1000) // 1s timeout
            if ready < 0 {
                if errno == EINTR { continue }
                log("poll() error: \(errno)")
                break
            }
            if ready == 0 {
                // Timeout — check for dead processes
                reapDeadProcesses()
                continue
            }

            // Check server socket for new connections
            if pollFDs[0].revents & Int16(POLLIN) != 0 {
                let clientFD = accept(serverFD, nil, nil)
                if clientFD >= 0 {
                    fcntl(clientFD, F_SETFL, O_NONBLOCK)
                    clientFDs.append(clientFD)
                    log("Client connected (fd=\(clientFD))")
                }
            }

            // Check client sockets for messages
            var disconnected: [Int32] = []
            for i in 1..<pollFDs.count {
                if pollFDs[i].revents & Int16(POLLIN) != 0 {
                    let clientFD = pollFDs[i].fd
                    do {
                        try handleClient(clientFD)
                    } catch FDSocketError.connectionClosed {
                        log("Client disconnected (fd=\(clientFD))")
                        disconnected.append(clientFD)
                        close(clientFD)
                    } catch {
                        log("Client error: \(error)")
                        disconnected.append(clientFD)
                        close(clientFD)
                    }
                }
                if pollFDs[i].revents & Int16(POLLHUP) != 0 {
                    let clientFD = pollFDs[i].fd
                    disconnected.append(clientFD)
                    close(clientFD)
                }
            }
            clientFDs.removeAll { disconnected.contains($0) }
        }

        // Cleanup
        log("Shutting down, releasing \(storedFDs.count) fds")
        for (_, pane) in storedFDs { close(pane.fd) }
        close(serverFD)
        unlink(socketPath)
    }

    static func handleClient(_ clientFD: Int32) throws {
        let (receivedFD, messageData) = try FDSocket.receive(from: clientFD)

        guard let json = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any],
              let op = json["op"] as? String else {
            log("Invalid message from client")
            return
        }

        switch op {
        case "store":
            guard let paneId = json["pane_id"] as? String,
                  let fd = receivedFD else {
                log("store: missing pane_id or fd")
                return
            }
            let pid = (json["pid"] as? Int).map { Int32($0) } ?? 0
            let cwd = json["cwd"] as? String ?? ""
            storedFDs[paneId] = StoredPane(fd: fd, pid: pid, cwd: cwd, createdAt: Date())
            log("Stored fd=\(fd) for pane \(paneId) (pid=\(pid))")
            let response = try JSONSerialization.data(withJSONObject: ["status": "ok"])
            try FDSocket.sendMessage(response, over: clientFD)

        case "retrieve":
            guard let paneId = json["pane_id"] as? String else {
                log("retrieve: missing pane_id")
                return
            }
            if let pane = storedFDs.removeValue(forKey: paneId) {
                // Check if process is still alive
                if kill(pane.pid, 0) == 0 || pane.pid == 0 {
                    let response = try JSONSerialization.data(withJSONObject: [
                        "status": "ok", "pid": Int(pane.pid), "cwd": pane.cwd
                    ] as [String: Any])
                    try FDSocket.send(fd: pane.fd, over: clientFD, message: response)
                    close(pane.fd) // We sent the fd, close our copy
                    log("Retrieved fd for pane \(paneId)")
                } else {
                    close(pane.fd)
                    let response = try JSONSerialization.data(withJSONObject: ["status": "dead"])
                    try FDSocket.sendMessage(response, over: clientFD)
                    log("Pane \(paneId) process dead (pid=\(pane.pid))")
                }
            } else {
                let response = try JSONSerialization.data(withJSONObject: ["status": "not_found"])
                try FDSocket.sendMessage(response, over: clientFD)
            }

        case "list":
            var panes: [[String: Any]] = []
            for (id, pane) in storedFDs {
                let alive = pane.pid == 0 || kill(pane.pid, 0) == 0
                panes.append([
                    "pane_id": id,
                    "pid": Int(pane.pid),
                    "cwd": pane.cwd,
                    "alive": alive
                ] as [String: Any])
            }
            let response = try JSONSerialization.data(withJSONObject: [
                "status": "ok", "panes": panes, "count": panes.count
            ] as [String: Any])
            try FDSocket.sendMessage(response, over: clientFD)

        case "release":
            guard let paneId = json["pane_id"] as? String else { return }
            if let pane = storedFDs.removeValue(forKey: paneId) {
                close(pane.fd)
                log("Released pane \(paneId)")
            }
            let response = try JSONSerialization.data(withJSONObject: ["status": "ok"])
            try FDSocket.sendMessage(response, over: clientFD)

        case "shutdown":
            log("Shutdown requested by client")
            running = false
            let response = try JSONSerialization.data(withJSONObject: ["status": "ok"])
            try FDSocket.sendMessage(response, over: clientFD)

        default:
            log("Unknown op: \(op)")
        }
    }

    static func reapDeadProcesses() {
        var dead: [String] = []
        for (id, pane) in storedFDs {
            if pane.pid > 0 && kill(pane.pid, 0) != 0 {
                dead.append(id)
            }
        }
        for id in dead {
            if let pane = storedFDs.removeValue(forKey: id) {
                close(pane.fd)
                log("Reaped dead pane \(id) (pid=\(pane.pid))")
            }
        }
    }

    static func log(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] [forged] \(message)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
            // Also append to log file
            if let fh = FileHandle(forWritingAtPath: "/tmp/forged.log") {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            } else {
                FileManager.default.createFile(atPath: "/tmp/forged.log", contents: data)
            }
        }
    }
}
