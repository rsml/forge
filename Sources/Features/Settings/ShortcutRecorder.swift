import SwiftUI
import AppKit
import ForgeCore

/// A clickable key combo field. When clicked it enters "recording" mode and
/// captures the next key press via an NSEvent monitor, then calls `onChange`.
struct ShortcutRecorder: View {
    let current: String          // e.g. "⌘P"
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Button(action: {
            if isRecording { onCancel() } else { onStartRecording() }
        }) {
            HStack(spacing: 4) {
                if isRecording {
                    Text("Press shortcut…")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                } else {
                    Text(current.isEmpty ? "None" : current)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(current.isEmpty ? .tertiary : .primary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minWidth: 80)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isRecording
                          ? Color.accentColor.opacity(0.12)
                          : Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                                    lineWidth: isRecording ? 1.5 : 0.5)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - NSEvent key capture helper

/// Captures a single key event using a local NSEvent monitor and returns the
/// human-readable shortcut string (e.g. "⌘⇧P") and the raw components.
struct KeyCaptureResult {
    let display: String          // e.g. "⌘⇧P"
    let key: String              // e.g. "p"
    let modifiers: [String]      // e.g. ["command", "shift"]
}

final class KeyCaptureSession {
    private var monitor: Any?

    func start(onCapture: @escaping (KeyCaptureResult?) -> Void) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Escape → cancel
            if event.keyCode == 53 {
                self?.stop()
                onCapture(nil)
                return nil
            }
            let result = Self.parse(event)
            self?.stop()
            onCapture(result)
            return nil
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    private static let unshiftMap: [Character: Character] = [
        "{": "[", "}": "]", "<": ",", ">": ".",
        "~": "`", "!": "1", "@": "2", "#": "3",
        "$": "4", "%": "5", "^": "6", "&": "7",
        "*": "8", "(": "9", ")": "0", "_": "-",
        "+": "=", "|": "\\", ":": ";", "\"": "'", "?": "/",
    ]

    private static func parse(_ event: NSEvent) -> KeyCaptureResult? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: [String] = []
        var display = ""

        if flags.contains(.control)  { modifiers.append("control");  display += "⌃" }
        if flags.contains(.option)   { modifiers.append("option");   display += "⌥" }
        if flags.contains(.shift)    { modifiers.append("shift");    display += "⇧" }
        if flags.contains(.command)  { modifiers.append("command");  display += "⌘" }

        var keyLabel = keyString(for: event)
        // Unshift: when shift is held, charactersIgnoringModifiers still returns the shifted char
        if flags.contains(.shift), let ch = keyLabel.first, let unshifted = unshiftMap[ch] {
            keyLabel = String(unshifted)
        }
        display += keyLabel.uppercased()

        return KeyCaptureResult(display: display, key: keyLabel.lowercased(), modifiers: modifiers)
    }

    private static func keyString(for event: NSEvent) -> String {
        switch event.keyCode {
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 48:  return "⇥"
        case 53:  return "⎋"
        case 36:  return "↩"
        case 51:  return "⌫"
        case 49:  return "Space"
        default:
            return event.charactersIgnoringModifiers?.lowercased() ?? "?"
        }
    }
}
