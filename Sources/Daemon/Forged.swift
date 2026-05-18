import Foundation
import Darwin
import ForgeCore

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
        let pgid: pid_t
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
            // Capture the pgid now — the shell is the foreground pgrp until a child grabs it.
            let pgid = pid > 0 ? getpgid(pid) : pid_t(0)
            // Close previous fd for this pane (if overwriting)
            if let existing = storedFDs[paneId] {
                close(existing.fd)
                log("Replaced previous fd=\(existing.fd) for pane \(paneId)")
            }
            storedFDs[paneId] = StoredPane(fd: fd, pid: pid, pgid: pgid, cwd: cwd, createdAt: Date())
            log("Stored fd=\(fd) for pane \(paneId) (pid=\(pid) pgid=\(pgid))")
            let response = try JSONSerialization.data(withJSONObject: ["status": "ok"])
            try FDSocket.sendMessage(response, over: clientFD)

        case "retrieve":
            guard let paneId = json["pane_id"] as? String else {
                log("retrieve: missing pane_id")
                return
            }
            if let pane = storedFDs[paneId] {
                // Check if process is still alive
                if kill(pane.pid, 0) == 0 || pane.pid == 0 {
                    // Send a dup of the fd — keep our copy for persistence
                    let dupFd = Darwin.dup(pane.fd)
                    let response = try JSONSerialization.data(withJSONObject: [
                        "status": "ok", "pid": Int(pane.pid), "cwd": pane.cwd
                    ] as [String: Any])
                    try FDSocket.send(fd: dupFd, over: clientFD, message: response)
                    close(dupFd) // Close the dup we just sent
                    log("Retrieved fd for pane \(paneId) (sent dup, keeping original)")
                } else {
                    storedFDs.removeValue(forKey: paneId)
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

        case "is_active":
            guard let paneIds = json["pane_ids"] as? [String] else {
                log("is_active: missing pane_ids")
                return
            }
            var results: [[String: Any]] = []
            for id in paneIds {
                results.append(activityEntry(for: id))
            }
            let response = try JSONSerialization.data(withJSONObject: [
                "status": "ok", "panes": results
            ] as [String: Any])
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

    /// Per-pane activity check. Returns a JSON-ready dict suitable for the `is_active` response.
    /// Active iff the PTY's foreground process group differs from the shell's pgid — i.e. some
    /// child (claude, vim, npm, ...) has grabbed the controlling terminal via tcsetpgrp.
    static func activityEntry(for paneId: String) -> [String: Any] {
        let inactive: [String: Any] = ["pane_id": paneId, "active": false]
        guard let pane = storedFDs[paneId] else { return inactive }
        // Reap stale entries — shell process exited. Also treat unknown pid (0) as inactive.
        guard pane.pid > 0, kill(pane.pid, 0) == 0 else { return inactive }
        let fg = tcgetpgrp(pane.fd)
        guard fg > 0, fg != pane.pgid else { return inactive }
        var entry: [String: Any] = ["pane_id": paneId, "active": true]
        if let cmd = procCommandName(pid: fg) {
            entry["command"] = cmd
        }
        return entry
    }

    /// Resolves a display name for a foreground process — what the user *thinks*
    /// they ran, not what's on disk.
    ///
    /// Reads `KERN_PROCARGS2` for argv and `proc_pidpath` for the resolved
    /// executable path, then delegates the interpretation to
    /// `CommandNameResolver.resolve(argv:execPath:)` (a pure function in
    /// ForgeCore — see its docs for the layered fallback strategy).
    static func procCommandName(pid: pid_t) -> String? {
        let argv = procArgv(pid: pid)

        var execPath = ""
        let bufSize: Int = 4096
        let buf = UnsafeMutablePointer<CChar>.allocate(capacity: bufSize)
        defer { buf.deallocate() }
        if proc_pidpath(pid, buf, UInt32(bufSize)) > 0 {
            execPath = String(cString: buf)
        }

        return CommandNameResolver.resolve(argv: argv, execPath: execPath)
    }

    /// Reads the command-line arguments of a process via `sysctl(KERN_PROCARGS2)`.
    /// Returns an empty array if the lookup fails for any reason — callers fall
    /// back to other signals.
    ///
    /// `KERN_PROCARGS2` layout (host byte order):
    /// ```
    /// [argc: Int32]
    /// [exec_path: NUL-terminated C string]
    /// [padding: zero or more NULs]
    /// [argv[0]: NUL-terminated]
    /// [argv[1]: NUL-terminated]
    /// ...
    /// [argv[argc-1]: NUL-terminated]
    /// [envp: NUL-terminated strings...]
    /// ```
    static func procArgv(pid: pid_t) -> [String] {
        // Determine kernel-imposed upper bound. `KERN_ARGMAX` is typically ~256 KB
        // on modern macOS; the size needed for this proc is at most that.
        var argMax: Int32 = 0
        var argMaxLen = MemoryLayout<Int32>.size
        var mibArgMax: [Int32] = [CTL_KERN, KERN_ARGMAX]
        if sysctl(&mibArgMax, UInt32(mibArgMax.count), &argMax, &argMaxLen, nil, 0) != 0 || argMax <= 0 {
            argMax = 262_144  // sane fallback
        }

        var size = Int(argMax)
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buf.deallocate() }

        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, UInt32(mib.count), buf, &size, nil, 0) == 0,
              size >= MemoryLayout<Int32>.size else {
            return []
        }

        // First 4 bytes: argc (host byte order).
        let argc = buf.withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
        guard argc > 0 else { return [] }

        var i = MemoryLayout<Int32>.size

        // Skip exec_path (NUL-terminated).
        while i < size, buf[i] != 0 { i += 1 }
        // Skip padding NULs between exec_path and argv[0].
        while i < size, buf[i] == 0 { i += 1 }

        var args: [String] = []
        args.reserveCapacity(Int(argc))
        for _ in 0..<argc {
            guard i < size else { break }
            let start = i
            while i < size, buf[i] != 0 { i += 1 }
            let bytes = UnsafeBufferPointer(start: buf.advanced(by: start), count: i - start)
            if let s = String(bytes: bytes, encoding: .utf8) {
                args.append(s)
            }
            i += 1  // skip terminating NUL
        }
        return args
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
