@preconcurrency import AppKit
import GhosttyKit
import QuartzCore

/// NSView subclass that hosts a CAMetalLayer for ghostty GPU rendering.
/// Forwards keyboard, mouse, and frame events to the ghostty surface.
/// The `surface` property is set externally by `GhosttyRenderer` after creation.
final class GhosttyNSView: NSView {
    // Set by GhosttyRenderer after surface creation.
    var surface: ghostty_surface_t?
    /// In EXEC mode, the surface is created before the view is in a window.
    /// Metal needs a valid window context. This holds the surface until
    /// viewDidMoveToWindow connects it.
    var pendingSurface: ghostty_surface_t?
    /// Called after ghostty_surface_set_size with the computed (cols, rows).
    var onSurfaceResize: ((Int, Int) -> Void)?
    /// Called when this view becomes first responder (user clicked to focus).
    var onFocusGained: (() -> Void)?
    /// True when in EXEC mode — Ghostty handles keys natively.
    var execMode: Bool = false

    // MARK: - Layer Setup

    override var wantsLayer: Bool {
        get { true }
        set {} // swiftlint:disable:this unused_setter_value
    }

    override var wantsUpdateLayer: Bool { true }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.pixelFormat = .bgra8Unorm
        layer.isOpaque = false
        layer.framebufferOnly = false
        layer.contentsScale = window?.backingScaleFactor ?? 2.0
        return layer
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Frame / Display / Scale

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let surface else { return }
        let scale = window?.backingScaleFactor ?? 2.0
        let w = UInt32(newSize.width * scale)
        let h = UInt32(newSize.height * scale)
        guard w > 0, h > 0 else { return }
        ghostty_surface_set_size(surface, w, h)
        // Query computed cols/rows and notify
        let size = ghostty_surface_size(surface)
        if size.columns > 0 && size.rows > 0 {
            onSurfaceResize?(Int(size.columns), Int(size.rows))
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let window else { return }
        let scale = window.backingScaleFactor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = scale
        CATransaction.commit()
        guard let surface else { return }
        ghostty_surface_set_content_scale(surface, Double(scale), Double(scale))
        let w = UInt32(frame.width * scale)
        let h = UInt32(frame.height * scale)
        if w > 0, h > 0 {
            ghostty_surface_set_size(surface, w, h)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // EXEC mode: connect the deferred surface now that we have a window.
        if let pending = pendingSurface, window != nil {
            surface = pending
            pendingSurface = nil
        }
        guard let window, let surface else { return }
        let scale = window.backingScaleFactor
        layer?.contentsScale = scale
        ghostty_surface_set_content_scale(surface, Double(scale), Double(scale))
        if let screen = window.screen {
            ghostty_surface_set_display_id(surface, screen.displayID)
        }
        let w = UInt32(frame.width * scale)
        let h = UInt32(frame.height * scale)
        if w > 0, h > 0 {
            ghostty_surface_set_size(surface, w, h)
        }
    }

    // MARK: - Focus

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface {
            ghostty_surface_set_focus(surface, true)
            onFocusGained?()
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, let surface {
            ghostty_surface_set_focus(surface, false)
        }
        return result
    }

    // MARK: - Keyboard Input
    //
    // We bypass ghostty's key encoder (ghostty_surface_key) entirely.
    // Ghostty uses Kitty keyboard protocol which encodes Ctrl+C as ESC[3;5u —
    // tmux's shell doesn't expect that. Instead, we convert NSEvent → raw
    // terminal bytes and send directly to tmux via onKeyInput.

    /// Callback for raw terminal bytes from keyboard input.
    /// Wired by GhosttyRenderer to send to tmux via send-keys -H.
    var onKeyInput: ((Data) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard window?.firstResponder === self else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { return false }

        if execMode {
            // EXEC mode: let Ghostty handle keys natively
            if flags.contains(.control) {
                let keyEvent = buildKeyEvent(for: event, action: GHOSTTY_ACTION_PRESS)
                if let surface { _ = ghostty_surface_key(surface, keyEvent) }
                return true
            }
            return false
        }

        // MANUAL IO mode: bypass Ghostty's key encoder
        if flags.contains(.control) {
            sendKeyEvent(event)
            return true
        }
        return false
    }

    override func keyDown(with event: NSEvent) {
        if execMode {
            let keyEvent = buildKeyEvent(for: event, action: GHOSTTY_ACTION_PRESS)
            if let surface { _ = ghostty_surface_key(surface, keyEvent) }
            return
        }
        sendKeyEvent(event)
    }

    override func keyUp(with event: NSEvent) {
        if execMode {
            let keyEvent = buildKeyEvent(for: event, action: GHOSTTY_ACTION_RELEASE)
            if let surface { _ = ghostty_surface_key(surface, keyEvent) }
            return
        }
    }

    override func flagsChanged(with event: NSEvent) {
        if execMode {
            let keyEvent = buildKeyEvent(for: event, action: GHOSTTY_ACTION_PRESS)
            if let surface { _ = ghostty_surface_key(surface, keyEvent) }
            return
        }
        // No action needed — modifier-only events don't produce terminal bytes
    }

    override func insertText(_ insertString: Any) {
        let text: String
        if let s = insertString as? String { text = s }
        else if let s = insertString as? NSAttributedString { text = s.string }
        else { return }
        guard !text.isEmpty else { return }
        if execMode {
            text.withCString { cStr in
                if let surface { ghostty_surface_text(surface, cStr, UInt(text.utf8.count)) }
            }
            return
        }
        onKeyInput?(Data(text.utf8))
    }

    private func sendKeyEvent(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Ctrl+key → control byte (0x01-0x1A)
        if flags.contains(.control), let chars = event.charactersIgnoringModifiers, let scalar = chars.unicodeScalars.first {
            let code = scalar.value
            if code >= UInt32(Character("a").asciiValue!), code <= UInt32(Character("z").asciiValue!) {
                let controlByte = UInt8(code - UInt32(Character("a").asciiValue!) + 1)
                onKeyInput?(Data([controlByte]))
                return
            }
            // Ctrl+[ = ESC, Ctrl+] = 0x1D, Ctrl+\ = 0x1C, etc.
            switch scalar {
            case "[": onKeyInput?(Data([0x1B])); return
            case "]": onKeyInput?(Data([0x1D])); return
            case "\\": onKeyInput?(Data([0x1C])); return
            case "^": onKeyInput?(Data([0x1E])); return
            case "_": onKeyInput?(Data([0x1F])); return
            case "@": onKeyInput?(Data([0x00])); return
            default: break
            }
        }

        // Special keys → VT escape sequences
        switch Int(event.keyCode) {
        case 126: onKeyInput?(Data([0x1B, 0x5B, 0x41])); return // Up
        case 125: onKeyInput?(Data([0x1B, 0x5B, 0x42])); return // Down
        case 124: onKeyInput?(Data([0x1B, 0x5B, 0x43])); return // Right
        case 123: onKeyInput?(Data([0x1B, 0x5B, 0x44])); return // Left
        case 115: onKeyInput?(Data([0x1B, 0x5B, 0x48])); return // Home
        case 119: onKeyInput?(Data([0x1B, 0x5B, 0x46])); return // End
        case 116: onKeyInput?(Data([0x1B, 0x5B, 0x35, 0x7E])); return // PageUp
        case 121: onKeyInput?(Data([0x1B, 0x5B, 0x36, 0x7E])); return // PageDown
        case 117: onKeyInput?(Data([0x1B, 0x5B, 0x33, 0x7E])); return // Delete (forward)
        case 51: onKeyInput?(Data([0x7F])); return // Backspace
        case 36: onKeyInput?(Data([0x0D])); return // Return
        case 48: onKeyInput?(Data([0x09])); return // Tab
        case 53: onKeyInput?(Data([0x1B])); return // Escape
        default: break
        }

        // Regular characters → UTF-8
        if let text = event.characters, !text.isEmpty {
            onKeyInput?(Data(text.utf8))
        }
    }

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, point.x, frame.height - point.y, modsFromFlags(event.modifierFlags))
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, modsFromFlags(event.modifierFlags))
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, modsFromFlags(event.modifierFlags))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, point.x, frame.height - point.y, modsFromFlags(event.modifierFlags))
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, modsFromFlags(event.modifierFlags))
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, modsFromFlags(event.modifierFlags))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, point.x, frame.height - point.y, modsFromFlags(event.modifierFlags))
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, point.x, frame.height - point.y, modsFromFlags(event.modifierFlags))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        if event.hasPreciseScrollingDeltas {
            x *= 2
            y *= 2
        }
        // Scroll mods packed int: bit 0 = precision, bits 1-3 = momentum phase.
        var scrollMods: Int32 = 0
        if event.hasPreciseScrollingDeltas {
            scrollMods |= 1
        }
        let momentum: Int32 = switch event.momentumPhase {
        case .began: Int32(GHOSTTY_MOUSE_MOMENTUM_BEGAN.rawValue)
        case .changed: Int32(GHOSTTY_MOUSE_MOMENTUM_CHANGED.rawValue)
        case .ended: Int32(GHOSTTY_MOUSE_MOMENTUM_ENDED.rawValue)
        case .cancelled: Int32(GHOSTTY_MOUSE_MOMENTUM_CANCELLED.rawValue)
        case .mayBegin: Int32(GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN.rawValue)
        default: Int32(GHOSTTY_MOUSE_MOMENTUM_NONE.rawValue)
        }
        scrollMods |= momentum << 1
        ghostty_surface_mouse_scroll(surface, x, y, scrollMods)
    }

    // MARK: - Helpers

    private func buildKeyEvent(for event: NSEvent, action: ghostty_input_action_e) -> ghostty_input_key_s {
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = modsFromFlags(event.modifierFlags)
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.text = nil
        keyEvent.composing = false
        keyEvent.unshifted_codepoint = 0
        return keyEvent
    }

    private func modsFromFlags(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        return ghostty_input_mods_e(rawValue: mods)
    }
}

// MARK: - NSScreen extension for display ID

private extension NSScreen {
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? 0
    }
}
