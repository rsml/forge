import Foundation
import Darwin

/// Unix domain socket helpers for fd passing via sendmsg/recvmsg.
/// Used by both forged (server) and DaemonAdapter (client).
enum FDSocket {

    /// Create a Unix domain socket, bind, and listen.
    static func listen(path: String) throws -> Int32 {
        // Remove stale socket file
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw FDSocketError.socketFailed(errno) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            throw FDSocketError.pathTooLong
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for (i, byte) in pathBytes.enumerated() { dest[i] = byte }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count)
        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(fd, sockaddrPtr, addrLen)
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw FDSocketError.bindFailed(errno)
        }

        guard Darwin.listen(fd, 5) == 0 else {
            close(fd)
            throw FDSocketError.listenFailed(errno)
        }

        return fd
    }

    /// Connect to an existing Unix domain socket.
    static func connect(path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw FDSocketError.socketFailed(errno) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for (i, byte) in pathBytes.enumerated() { dest[i] = byte }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count)
        let connectResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, addrLen)
            }
        }
        guard connectResult == 0 else {
            close(fd)
            throw FDSocketError.connectFailed(errno)
        }

        return fd
    }

    /// Send a file descriptor over a Unix domain socket with a JSON message.
    static func send(fd fileDescriptor: Int32, over socket: Int32, message: Data) throws {
        var iov = iovec()
        var msgData = [UInt8](message)
        msgData.withUnsafeMutableBufferPointer { buf in
            iov.iov_base = UnsafeMutableRawPointer(buf.baseAddress!)
            iov.iov_len = buf.count
        }

        // Control message for SCM_RIGHTS
        let cmsgSize = MemoryLayout<cmsghdr>.size + MemoryLayout<Int32>.size
        let cmsgBuf = UnsafeMutableRawPointer.allocate(byteCount: cmsgSize, alignment: MemoryLayout<cmsghdr>.alignment)
        defer { cmsgBuf.deallocate() }

        let cmsg = cmsgBuf.assumingMemoryBound(to: cmsghdr.self)
        cmsg.pointee.cmsg_len = socklen_t(cmsgSize)
        cmsg.pointee.cmsg_level = SOL_SOCKET
        cmsg.pointee.cmsg_type = SCM_RIGHTS

        // Copy the fd into the control message data area
        let fdPtr = cmsgBuf.advanced(by: MemoryLayout<cmsghdr>.size)
            .assumingMemoryBound(to: Int32.self)
        fdPtr.pointee = fileDescriptor

        var msg = msghdr()
        withUnsafeMutablePointer(to: &iov) { iovPtr in
            msg.msg_iov = iovPtr
            msg.msg_iovlen = 1
        }
        msg.msg_control = cmsgBuf
        msg.msg_controllen = socklen_t(cmsgSize)

        let sent = withUnsafePointer(to: &msg) { msgPtr in
            sendmsg(socket, msgPtr, 0)
        }
        guard sent >= 0 else { throw FDSocketError.sendFailed(errno) }
    }

    /// Send a message without an fd (just data).
    static func sendMessage(_ message: Data, over socket: Int32) throws {
        let sent = message.withUnsafeBytes { buf in
            Darwin.send(socket, buf.baseAddress!, buf.count, 0)
        }
        guard sent >= 0 else { throw FDSocketError.sendFailed(errno) }
    }

    /// Receive a file descriptor and message from a Unix domain socket.
    /// Returns nil fd if no fd was passed (just a message).
    static func receive(from socket: Int32, bufferSize: Int = 4096) throws -> (fd: Int32?, message: Data) {
        var buf = [UInt8](repeating: 0, count: bufferSize)
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

        let received = withUnsafeMutablePointer(to: &msg) { msgPtr in
            recvmsg(socket, msgPtr, 0)
        }
        guard received > 0 else {
            if received == 0 { throw FDSocketError.connectionClosed }
            throw FDSocketError.receiveFailed(errno)
        }

        // Extract fd from control message (if present)
        var receivedFd: Int32? = nil
        if msg.msg_controllen >= socklen_t(cmsgSize) {
            let cmsg = cmsgBuf.assumingMemoryBound(to: cmsghdr.self)
            if cmsg.pointee.cmsg_level == SOL_SOCKET && cmsg.pointee.cmsg_type == SCM_RIGHTS {
                let fdPtr = cmsgBuf.advanced(by: MemoryLayout<cmsghdr>.size)
                    .assumingMemoryBound(to: Int32.self)
                receivedFd = fdPtr.pointee
            }
        }

        let messageData = Data(buf.prefix(received))
        return (receivedFd, messageData)
    }

    /// Default socket path for forged.
    static var defaultSocketPath: String {
        let tmpDir = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp"
        return (tmpDir as NSString).appendingPathComponent("forge-daemon.sock")
    }
}

enum FDSocketError: Error, CustomStringConvertible {
    case socketFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case connectFailed(Int32)
    case sendFailed(Int32)
    case receiveFailed(Int32)
    case connectionClosed
    case pathTooLong

    var description: String {
        switch self {
        case .socketFailed(let e): return "socket() failed: \(String(cString: strerror(e)))"
        case .bindFailed(let e): return "bind() failed: \(String(cString: strerror(e)))"
        case .listenFailed(let e): return "listen() failed: \(String(cString: strerror(e)))"
        case .connectFailed(let e): return "connect() failed: \(String(cString: strerror(e)))"
        case .sendFailed(let e): return "send() failed: \(String(cString: strerror(e)))"
        case .receiveFailed(let e): return "recv() failed: \(String(cString: strerror(e)))"
        case .connectionClosed: return "Connection closed"
        case .pathTooLong: return "Socket path too long"
        }
    }
}
