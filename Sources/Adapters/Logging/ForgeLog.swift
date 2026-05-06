import Foundation

enum ForgeLog {
    static let logFile = "/tmp/forge.log"

    // Serial queue ensures all file I/O is ordered and race-free.
    private static let queue = DispatchQueue(label: "forge.log")

    // Persistent handle eliminates open/seek/close overhead on every call.
    // All accesses are serialised through `queue`, so nonisolated(unsafe) is correct.
    private nonisolated(unsafe) static var handle: FileHandle?

    // Rotate when the file exceeds 1 MB to prevent unbounded growth.
    private static let maxSize: UInt64 = 1_048_576

    static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        // stdout needs no synchronisation — print before queuing.
        print(line, terminator: "")

        guard let data = line.data(using: .utf8) else { return }

        queue.sync {
            let h = getOrCreateHandle()
            guard let h else { return }

            // Rotate when the file is at or above the size limit.
            let size = h.seekToEndOfFile()
            if size >= maxSize {
                rotate(currentHandle: h)
                // After rotation the active handle is the new empty file.
                guard let fresh = ForgeLog.handle else { return }
                fresh.write(data)
            } else {
                h.write(data)
            }
        }
    }

    // Must be called from within `queue`.
    private static func getOrCreateHandle() -> FileHandle? {
        if let existing = handle { return existing }

        let fm = FileManager.default
        if !fm.fileExists(atPath: logFile) {
            fm.createFile(atPath: logFile, contents: nil)
        }

        let h = FileHandle(forWritingAtPath: logFile)
        handle = h
        return h
    }

    // Rename the current log to .old and open a fresh file.
    // Must be called from within `queue`.
    private static func rotate(currentHandle: FileHandle) {
        currentHandle.closeFile()
        handle = nil

        let oldFile = logFile + ".old"
        let fm = FileManager.default

        // Overwrite any previous .old file.
        try? fm.removeItem(atPath: oldFile)
        try? fm.moveItem(atPath: logFile, toPath: oldFile)

        // Create and open the new log file.
        fm.createFile(atPath: logFile, contents: nil)
        handle = FileHandle(forWritingAtPath: logFile)
    }
}
