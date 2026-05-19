import Foundation

public struct DetectedPort: Hashable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
}

/// Scans text (typically pane scrollback) for dev-server `host:port` URLs.
/// Pure regex pass; order-preserving; deduplicates within the result.
public enum PortDetector {
    /// `host:port` with known dev-server hosts.
    private static let strictRegex = try! NSRegularExpression(
        pattern: #"\b(localhost|127\.0\.0\.1|0\.0\.0\.0):(\d{2,5})\b"#,
        options: []
    )
    /// Bare `:port` preceded by dev-server keywords like "ready", "listening", "Local", "url", "started", "running".
    /// 4-5 digit ports only — keeps timestamps (`:34:56`) out.
    private static let looseRegex = try! NSRegularExpression(
        pattern: #"(?i)\b(?:ready|listening|started|running|Local|url)\b[^\n]{0,40}?:(\d{4,5})\b"#,
        options: []
    )
    /// `port 8080` / `server 8080` / `port: 8080` / `server: 8080` — keyword followed by
    /// whitespace (optionally a colon) then a port number. Covers Python's `python -m http.server`
    /// output ("Serving HTTP on :: port 8080") and similar.
    /// 2-5 digit ports — the keyword anchor protects against false positives.
    private static let portKeywordRegex = try! NSRegularExpression(
        pattern: #"(?i)\b(?:port|server)\b\s*:?\s+(\d{2,5})\b"#,
        options: []
    )

    public static func detect(in text: String) -> [DetectedPort] {
        var seen: Set<DetectedPort> = []
        var result: [DetectedPort] = []
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)

        for match in strictRegex.matches(in: text, range: range) {
            guard match.numberOfRanges >= 3 else { continue }
            let host = ns.substring(with: match.range(at: 1))
            let portStr = ns.substring(with: match.range(at: 2))
            guard let port = Int(portStr), (1...65535).contains(port) else { continue }
            let p = DetectedPort(host: host, port: port)
            if seen.insert(p).inserted { result.append(p) }
        }
        for match in looseRegex.matches(in: text, range: range) {
            guard match.numberOfRanges >= 2 else { continue }
            let portStr = ns.substring(with: match.range(at: 1))
            guard let port = Int(portStr), (1024...65535).contains(port) else { continue }
            // Loose pass assumes localhost — dev-server output rarely names a different host.
            let p = DetectedPort(host: "localhost", port: port)
            if seen.insert(p).inserted { result.append(p) }
        }
        for match in portKeywordRegex.matches(in: text, range: range) {
            guard match.numberOfRanges >= 2 else { continue }
            let portStr = ns.substring(with: match.range(at: 1))
            guard let port = Int(portStr), (1...65535).contains(port) else { continue }
            // Loose pass assumes localhost — dev-server output rarely names a different host.
            let p = DetectedPort(host: "localhost", port: port)
            if seen.insert(p).inserted { result.append(p) }
        }
        return result
    }
}
