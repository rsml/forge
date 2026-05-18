import Foundation
import Darwin
import ForgeCore

/// PersistencePort implementation using the forged daemon.
/// Connects to the daemon's Unix socket and sends/receives fds via SCM_RIGHTS.
@MainActor
final class DaemonAdapter: PersistencePort {
    private var socketFD: Int32 = -1
    private let socketPath: String

    init() {
        let tmpDir = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp"
        self.socketPath = (tmpDir as NSString).appendingPathComponent("forge-daemon.sock")
    }

    /// Ensure connected to daemon. Launches daemon if not running.
    func ensureConnected() throws {
        if socketFD >= 0 { return }

        // Try to connect
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DaemonError.socketFailed }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for (i, byte) in pathBytes.enumerated() { dest[i] = byte }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count)
        let result = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, addrLen)
            }
        }

        if result != 0 {
            close(fd)
            // Try launching daemon
            try launchDaemon()
            // Retry connect
            let fd2 = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd2 >= 0 else { throw DaemonError.socketFailed }

            // Wait a moment for daemon to start
            Thread.sleep(forTimeInterval: 0.5)

            let result2 = withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    Darwin.connect(fd2, sockaddrPtr, addrLen)
                }
            }
            guard result2 == 0 else {
                close(fd2)
                throw DaemonError.connectFailed
            }
            socketFD = fd2
        } else {
            socketFD = fd
        }
        ForgeLog.log("[daemon] Connected to forged")
    }

    private func launchDaemon() throws {
        // Find forged binary next to Forge binary
        let forgedPath: String
        if let bundlePath = Bundle.main.executablePath {
            let dir = (bundlePath as NSString).deletingLastPathComponent
            forgedPath = (dir as NSString).appendingPathComponent("forged")
        } else {
            forgedPath = "forged"
        }

        guard FileManager.default.fileExists(atPath: forgedPath) else {
            ForgeLog.log("[daemon] forged binary not found at \(forgedPath)")
            throw DaemonError.daemonNotFound
        }

        var pid: pid_t = 0
        let args = [forgedPath, "--socket", socketPath]
        let argv = args.map { strdup($0) } + [nil]
        defer { argv.compactMap { $0 }.forEach { free($0) } }

        let status = posix_spawn(&pid, forgedPath, nil, nil, argv, environ)
        guard status == 0 else {
            throw DaemonError.launchFailed(status)
        }
        ForgeLog.log("[daemon] Launched forged (pid=\(pid))")
    }

    // MARK: - PersistencePort

    nonisolated func store(paneId: String, fd: Int32, pid: Int32, cwd: String) async throws {
        let msg = try JSONSerialization.data(withJSONObject: [
            "op": "store", "pane_id": paneId, "pid": Int(pid), "cwd": cwd
        ] as [String: Any])
        try await MainActor.run {
            try ensureConnected()
            try sendWithFD(fd: fd, message: msg)
            _ = try receiveMessage()
        }
    }

    nonisolated func retrieve(paneId: String) async throws -> (fd: Int32, pid: Int32, cwd: String)? {
        let msg = try JSONSerialization.data(withJSONObject: [
            "op": "retrieve", "pane_id": paneId
        ])
        return try await MainActor.run {
            try ensureConnected()
            try sendMessage(msg)
            let (fd, response) = try receiveWithFD()
            guard let json = try JSONSerialization.jsonObject(with: response) as? [String: Any],
                  let status = json["status"] as? String else { return nil }
            if status == "ok", let fd {
                let pid = (json["pid"] as? Int).map { Int32($0) } ?? 0
                let cwd = json["cwd"] as? String ?? ""
                return (fd, pid, cwd)
            }
            return nil
        }
    }

    nonisolated func list() async throws -> [PersistedPaneInfo] {
        let msg = try JSONSerialization.data(withJSONObject: ["op": "list"])
        return try await MainActor.run {
            try ensureConnected()
            try sendMessage(msg)
            let (_, response) = try receiveWithFD()
            guard let json = try JSONSerialization.jsonObject(with: response) as? [String: Any],
                  let panes = json["panes"] as? [[String: Any]] else { return [] }
            return panes.compactMap { p in
                guard let id = p["pane_id"] as? String else { return nil }
                return PersistedPaneInfo(
                    paneId: id,
                    pid: (p["pid"] as? Int).map { Int32($0) } ?? 0,
                    cwd: p["cwd"] as? String ?? "",
                    alive: p["alive"] as? Bool ?? false
                )
            }
        }
    }

    nonisolated func release(paneId: String) async throws {
        let msg = try JSONSerialization.data(withJSONObject: [
            "op": "release", "pane_id": paneId
        ])
        try await MainActor.run {
            try ensureConnected()
            try sendMessage(msg)
            _ = try receiveMessage()
        }
    }

    /// Query the daemon for foreground activity on the given panes.
    ///
    /// Subject to a hard 200 ms timeout — a wedged daemon must never pin the close path.
    /// Callers fail-open (treat timeout/error as "no activity") to avoid phantom warnings
    /// every time forged hiccups.
    nonisolated func isActive(
        paneIds: [String]
    ) async throws -> [(paneId: String, isActive: Bool, command: String?)] {
        let msg = try JSONSerialization.data(withJSONObject: [
            "op": "is_active", "pane_ids": paneIds
        ] as [String: Any])

        return try await withThrowingTaskGroup(
            of: [(paneId: String, isActive: Bool, command: String?)].self
        ) { group in
            group.addTask {
                try await MainActor.run {
                    try self.ensureConnected()
                    try self.sendMessage(msg)
                    let (_, response) = try self.receiveWithFD()
                    guard let json = try JSONSerialization.jsonObject(with: response) as? [String: Any],
                          let panes = json["panes"] as? [[String: Any]] else {
                        return []
                    }
                    return panes.compactMap { entry in
                        guard let id = entry["pane_id"] as? String else { return nil }
                        let active = entry["active"] as? Bool ?? false
                        let command = entry["command"] as? String
                        return (paneId: id, isActive: active, command: command)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 200_000_000)
                throw DaemonError.timeout
            }
            // First task to finish wins. Cancel the loser.
            guard let result = try await group.next() else {
                group.cancelAll()
                throw DaemonError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Socket I/O

    private func sendMessage(_ data: Data) throws {
        guard socketFD >= 0 else { throw DaemonError.notConnected }
        let sent = data.withUnsafeBytes { buf in
            Darwin.send(socketFD, buf.baseAddress!, buf.count, 0)
        }
        guard sent >= 0 else { throw DaemonError.sendFailed }
    }

    private func sendWithFD(fd: Int32, message: Data) throws {
        guard socketFD >= 0 else { throw DaemonError.notConnected }

        var iov = iovec()
        var msgData = [UInt8](message)
        msgData.withUnsafeMutableBufferPointer { buf in
            iov.iov_base = UnsafeMutableRawPointer(buf.baseAddress!)
            iov.iov_len = buf.count
        }

        let cmsgSize = MemoryLayout<cmsghdr>.size + MemoryLayout<Int32>.size
        let cmsgBuf = UnsafeMutableRawPointer.allocate(byteCount: cmsgSize, alignment: MemoryLayout<cmsghdr>.alignment)
        defer { cmsgBuf.deallocate() }

        let cmsg = cmsgBuf.assumingMemoryBound(to: cmsghdr.self)
        cmsg.pointee.cmsg_len = socklen_t(cmsgSize)
        cmsg.pointee.cmsg_level = SOL_SOCKET
        cmsg.pointee.cmsg_type = SCM_RIGHTS
        cmsgBuf.advanced(by: MemoryLayout<cmsghdr>.size)
            .assumingMemoryBound(to: Int32.self).pointee = fd

        var msg = msghdr()
        withUnsafeMutablePointer(to: &iov) { iovPtr in
            msg.msg_iov = iovPtr
            msg.msg_iovlen = 1
        }
        msg.msg_control = cmsgBuf
        msg.msg_controllen = socklen_t(cmsgSize)

        let sent = withUnsafePointer(to: &msg) { sendmsg(socketFD, $0, 0) }
        guard sent >= 0 else { throw DaemonError.sendFailed }
    }

    private func receiveMessage() throws -> Data {
        let (_, data) = try receiveWithFD()
        return data
    }

    private func receiveWithFD() throws -> (fd: Int32?, data: Data) {
        guard socketFD >= 0 else { throw DaemonError.notConnected }

        var buf = [UInt8](repeating: 0, count: 4096)
        var iov = iovec()
        buf.withUnsafeMutableBufferPointer { bufPtr in
            iov.iov_base = UnsafeMutableRawPointer(bufPtr.baseAddress!)
            iov.iov_len = bufPtr.count
        }

        let cmsgSize = MemoryLayout<cmsghdr>.size + MemoryLayout<Int32>.size
        let cmsgBuf = UnsafeMutableRawPointer.allocate(byteCount: cmsgSize, alignment: MemoryLayout<cmsghdr>.alignment)
        defer { cmsgBuf.deallocate() }
        memset(cmsgBuf, 0, cmsgSize)

        var msg = msghdr()
        withUnsafeMutablePointer(to: &iov) { iovPtr in
            msg.msg_iov = iovPtr
            msg.msg_iovlen = 1
        }
        msg.msg_control = cmsgBuf
        msg.msg_controllen = socklen_t(cmsgSize)

        let received = withUnsafeMutablePointer(to: &msg) { recvmsg(socketFD, $0, 0) }
        guard received > 0 else { throw DaemonError.receiveFailed }

        var receivedFd: Int32? = nil
        if msg.msg_controllen >= socklen_t(cmsgSize) {
            let cmsg = cmsgBuf.assumingMemoryBound(to: cmsghdr.self)
            if cmsg.pointee.cmsg_level == SOL_SOCKET && cmsg.pointee.cmsg_type == SCM_RIGHTS {
                receivedFd = cmsgBuf.advanced(by: MemoryLayout<cmsghdr>.size)
                    .assumingMemoryBound(to: Int32.self).pointee
            }
        }

        return (receivedFd, Data(buf.prefix(received)))
    }
}

enum DaemonError: Error {
    case socketFailed, connectFailed, notConnected, sendFailed, receiveFailed
    case daemonNotFound, launchFailed(Int32)
    case timeout
}
