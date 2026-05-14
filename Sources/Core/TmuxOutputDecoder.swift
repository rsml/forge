import Foundation

/// Decodes tmux control mode `%output` payload escaping.
/// Tmux uses octal escapes: `\012` for LF, `\015` for CR, `\033` for ESC, `\\` for backslash.
public enum TmuxOutputDecoder {

    public static func decode(_ input: String) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(input.utf8.count)
        var i = input.startIndex
        while i < input.endIndex {
            if input[i] == "\\" {
                let next = input.index(after: i)
                if next < input.endIndex && input[next] == "\\" {
                    result.append(UInt8(ascii: "\\"))
                    i = input.index(after: next)
                } else if let (byte, end) = parseOctal(input, from: next) {
                    result.append(byte)
                    i = end
                } else {
                    result.append(UInt8(ascii: "\\"))
                    i = next
                }
            } else {
                for byte in String(input[i]).utf8 {
                    result.append(byte)
                }
                i = input.index(after: i)
            }
        }
        return result
    }

    private static func parseOctal(_ s: String, from start: String.Index) -> (UInt8, String.Index)? {
        var end = start
        var count = 0
        while end < s.endIndex && count < 3 && s[end] >= "0" && s[end] <= "7" {
            end = s.index(after: end)
            count += 1
        }
        guard count == 3 else { return nil }
        let octalStr = s[start..<end]
        guard let value = UInt8(octalStr, radix: 8) else { return nil }
        return (value, end)
    }
}
