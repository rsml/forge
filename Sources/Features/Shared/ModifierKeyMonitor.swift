import SwiftUI
import AppKit

@Observable
@MainActor
final class ModifierKeyMonitor {
    var commandPressed = false
    var optionPressed = false
    private nonisolated(unsafe) var flagsMonitor: Any?
    private nonisolated(unsafe) var keyMonitor: Any?
    var onOptionNumber: ((Int) -> Void)?

    init() {
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.commandPressed = event.modifierFlags.contains(.command)
                self?.optionPressed = event.modifierFlags.contains(.option)
            }
            return event
        }

        // Intercept Option+1-9 before macOS text input eats them
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains(.option),
                  let chars = event.charactersIgnoringModifiers,
                  let digit = chars.first?.wholeNumberValue,
                  digit >= 1, digit <= 9
            else { return event }
            Task { @MainActor in
                self?.onOptionNumber?(digit)
            }
            return nil // consume the event
        }
    }

    deinit {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}
