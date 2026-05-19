import Foundation

/// Detects "real" terminal bells (0x07) in a byte stream while ignoring BELs
/// that occur inside ANSI/OSC escape sequences. Modern shells emit OSC 133
/// semantic-prompt markers (`ESC ] 133 ; ... BEL`) on every prompt redraw,
/// and the trailing BEL is a string terminator — not a user-facing alert.
///
/// State machine:
///   - Outside any escape: a literal 0x07 is a real bell.
///   - Inside an OSC sequence (started by `ESC ]`): a 0x07 is a string
///     terminator. Same for `ESC \`.
public enum BellDetector {
    public static func containsStandaloneBell(_ data: Data) -> Bool {
        var inOSC = false
        var prevWasEsc = false
        for byte in data {
            if byte == 0x1B {                       // ESC
                prevWasEsc = true
                continue
            }
            if prevWasEsc {
                if byte == 0x5D {                   // ESC ] → OSC start
                    inOSC = true
                } else if byte == 0x5C && inOSC {   // ESC \ → ST (end of OSC)
                    inOSC = false
                }
                prevWasEsc = false
                continue
            }
            if byte == 0x07 {                       // BEL
                if inOSC {
                    inOSC = false                   // BEL as OSC terminator
                } else {
                    return true                     // standalone bell
                }
            }
        }
        return false
    }
}
