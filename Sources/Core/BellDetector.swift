import Foundation

/// Detects user-attention signals in a PTY byte stream.
///
/// Two signal sources:
///   - Standalone BEL bytes (0x07) outside any escape sequence.
///   - OSC 777 notification sequences (`ESC ] 777 ; notify ; <title> ; <body> ST`),
///     which are the de-facto standard for terminal-driven desktop notifications.
///     Claude Code 2.1.141+ uses these to signal "waiting for your input".
///
/// BELs that occur as OSC string terminators (e.g. the trailing 0x07 of
/// `ESC ] 133 ; A BEL` semantic-prompt markers, or `ESC ] 0 ; title BEL`
/// set-title sequences) do **not** count — those are syntax, not attention.
public enum BellDetector {
    /// True if `data` contains a standalone BEL or any OSC notification sequence.
    public static func containsAttentionSignal(_ data: Data) -> Bool {
        scan(data).hasSignal
    }

    /// True if `data` contains a standalone BEL outside any escape.
    /// Kept as a name for callers that want the narrower test, but most should
    /// use `containsAttentionSignal` so OSC 777 from modern TUIs counts too.
    public static func containsStandaloneBell(_ data: Data) -> Bool {
        scan(data).hasStandaloneBell
    }

    /// True if `data` contains an OSC 777 (notify) sequence.
    public static func containsOSCNotify(_ data: Data) -> Bool {
        scan(data).hasOSCNotify
    }

    private static func scan(_ data: Data) -> (hasStandaloneBell: Bool, hasOSCNotify: Bool, hasSignal: Bool) {
        var inOSC = false
        var oscPrefix = Data()            // accumulates first few bytes of current OSC for "777" sniff
        var prevWasEsc = false
        var hasStandaloneBell = false
        var hasOSCNotify = false

        func finishOSC() {
            if oscPrefix.starts(with: Data([0x37, 0x37, 0x37, 0x3B])) { // "777;"
                hasOSCNotify = true
            }
            oscPrefix.removeAll(keepingCapacity: true)
            inOSC = false
        }

        for byte in data {
            if byte == 0x1B {
                prevWasEsc = true
                continue
            }
            if prevWasEsc {
                if byte == 0x5D {                       // ESC ] → OSC start
                    inOSC = true
                    oscPrefix.removeAll(keepingCapacity: true)
                } else if byte == 0x5C && inOSC {       // ESC \ → ST
                    finishOSC()
                }
                prevWasEsc = false
                continue
            }
            if byte == 0x07 {                           // BEL
                if inOSC {
                    finishOSC()
                } else {
                    hasStandaloneBell = true
                }
                continue
            }
            if inOSC, oscPrefix.count < 4 {             // only need first 4 bytes
                oscPrefix.append(byte)
            }
        }
        return (hasStandaloneBell, hasOSCNotify, hasStandaloneBell || hasOSCNotify)
    }
}
