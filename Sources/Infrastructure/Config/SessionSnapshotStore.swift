import Foundation
import CryptoKit
import ForgeCore

enum SessionSnapshotStore {
    private static var sessionsDir: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/forge/sessions")
    }

    static func save(_ snapshot: SessionSnapshot) {
        let url = fileURL(for: snapshot.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else {
            ForgeLog.log("[app] Failed to encode session snapshot for \(snapshot.path)")
            return
        }
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        do {
            try data.write(to: url)
            ForgeLog.log("[app] Saved session snapshot: \(url.lastPathComponent)")
        } catch {
            ForgeLog.log("[app] Failed to write session snapshot: \(error)")
        }
    }

    static func load(path: String) -> SessionSnapshot? {
        let url = fileURL(for: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(SessionSnapshot.self, from: data) else {
            ForgeLog.log("[app] Malformed session snapshot, deleting: \(url.lastPathComponent)")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return snapshot
    }

    static func delete(path: String) {
        let url = fileURL(for: path)
        try? FileManager.default.removeItem(at: url)
    }

    private static func fileURL(for path: String) -> URL {
        let canonical = URL(fileURLWithPath: path).standardized.path
        let hash = SHA256.hash(data: Data(canonical.utf8))
        let hex = hash.prefix(16).map { String(format: "%02x", $0) }.joined()
        return sessionsDir.appendingPathComponent("\(hex).json")
    }
}
