import Foundation

/// Parsed tmux control mode events.
public enum TmuxEvent: Equatable {
    case bell(tabId: String)
    case silenceChanged(tabId: String, isSilent: Bool)
    case tabClose(tabId: String)
    case structural
    case ignored
}

/// Parses raw tmux control mode event strings into typed events.
public enum TmuxEventParser {

    private static let structuralPrefixes = [
        "%tab-add", "%tab-close", "%unlinked-tab-close",
        "%layout-change",
        "%project-changed", "%project-renamed",
        "%tab-renamed",
    ]

    public static func parse(_ event: String) -> TmuxEvent {
        if event.hasPrefix("%bell") {
            let parts = event.split(separator: " ")
            guard parts.count >= 2 else { return .ignored }
            return .bell(tabId: String(parts[1]))
        }

        // %subscription-changed silence $0 @43 1 - : 1
        if event.hasPrefix("%subscription-changed silence ") {
            if let windowId = parseWindowId(from: event),
               let value = parseSubscriptionValue(from: event) {
                return .silenceChanged(tabId: windowId, isSilent: value == "1")
            }
        }

        if event.hasPrefix("%tab-close") || event.hasPrefix("%unlinked-tab-close") {
            let parts = event.split(separator: " ")
            if parts.count >= 2 {
                return .tabClose(tabId: String(parts[1]))
            }
        }

        let isStructural = structuralPrefixes.contains { event.hasPrefix($0) }
        return isStructural ? .structural : .ignored
    }

    /// Extract @<id> from a subscription-changed event.
    private static func parseWindowId(from event: String) -> String? {
        for part in event.split(separator: " ") where part.hasPrefix("@") {
            return String(part)
        }
        return nil
    }

    /// Extract the value after " : " in a subscription-changed event.
    private static func parseSubscriptionValue(from event: String) -> String? {
        guard let colonRange = event.range(of: " : ") else { return nil }
        let value = event[colonRange.upperBound...].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
