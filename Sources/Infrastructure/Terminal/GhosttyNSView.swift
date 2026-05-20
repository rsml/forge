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

    // libghostty installs its own IOSurfaceLayer as a layer-hosting layer
    // via setProperty("layer", ...) + setProperty("wantsLayer", true).
    // We must NOT pre-create a CAMetalLayer here — doing so makes this a
    // layer-BACKED view and pins isOpaque=false, which silently disables
    // subpixel anti-aliasing for the composited text and yields the thin
    // rendering vs. Ghostty.app. See upstream SurfaceView_AppKit which
    // overrides neither wantsLayer nor makeBackingLayer.

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

        // Connect deferred surface now that we have a window (Metal needs it).
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
            // Notify listeners — setFrameSize won't fire again if frame was
            // already set before the surface connected (pendingSurface flow).
            let size = ghostty_surface_size(surface)
            if size.columns > 0, size.rows > 0 {
                onSurfaceResize?(Int(size.columns), Int(size.rows))
            }
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
    // the shell doesn't expect that. Instead, we convert NSEvent → raw
    // terminal bytes and send directly to the PTY via onKeyInput.

    /// Callback for raw terminal bytes from keyboard input.
    /// Wired by GhosttyRenderer to write directly to the PTY.
    var onKeyInput: ((Data) -> Void)?

    /// Callback for raw bytes that must reach the PTY uninterpreted.
    /// Used in EXEC mode to bypass Ghostty's Kitty-protocol encoder for the
    /// three kernel-signal control bytes (Ctrl+C, Ctrl+Z, Ctrl+\) so the
    /// kernel TTY discipline can deliver SIGINT/SIGTSTP/SIGQUIT.
    var onRawInput: ((Data) -> Void)?

    /// Fires for any user-driven input event — keys, text insertion.
    /// Pure-modifier presses (Shift, Cmd alone) and key releases don't count.
    /// Used by the attention pipeline to clear stale bell / content-match flags
    /// the moment the user engages the pane.
    var onUserInput: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard window?.firstResponder === self else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { return false }

        if execMode {
            // EXEC mode: let Ghostty handle keys natively
            if flags.contains(.control) {
                sendExecKey(event)
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
        onUserInput?()
        if execMode {
            sendExecKey(event)
            return
        }
        sendKeyEvent(event)
    }

    /// Forwards an NSEvent to Ghostty in EXEC mode with both `text` and
    /// `unshifted_codepoint` populated. The Kitty keyboard protocol encoder
    /// (which Claude Code 2.1+ enables whenever TERM_PROGRAM=ghostty) silently
    /// drops Ctrl+letter combos when unshifted_codepoint is zero — so it must
    /// be set for every key, not just typed text.
    private func sendExecKey(_ event: NSEvent) {
        guard let surface else { return }

        // Bypass Ghostty's key encoder for the kernel-signal control bytes.
        // The kernel TTY discipline only translates the literal byte (\x03,
        // \x1A, \x1C) to SIGINT/SIGTSTP/SIGQUIT — it never parses escape
        // sequences. If a prior TUI left Kitty mode pushed on the terminal's
        // stack and Ghostty's encoder emits ESC[99;5u for Ctrl+C, sleep is
        // never killed. Sending the raw byte makes signals work regardless.
        if let signalByte = kernelSignalByte(for: event) {
            onRawInput?(Data([signalByte]))
            return
        }

        let text = sanitizedCharacters(event) ?? ""
        text.withCString { cStr in
            var keyEvent = buildKeyEvent(for: event, action: GHOSTTY_ACTION_PRESS)
            if !text.isEmpty { keyEvent.text = cStr }
            _ = ghostty_surface_key(surface, keyEvent)
        }
    }

    /// Returns the raw control byte for Ctrl+C / Ctrl+Z / Ctrl+\\ — the three
    /// keys the kernel TTY discipline maps to signals. Returns nil for any
    /// other combination so it falls through to the normal encoder.
    private func kernelSignalByte(for event: NSEvent) -> UInt8? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.control) else { return nil }
        // Allow Shift (Ctrl+Shift+C still ≡ Ctrl+C for signal purposes) and
        // CapsLock, but bail if Cmd/Opt are also held — those are app shortcuts.
        let blocking = flags.subtracting([.control, .shift, .capsLock])
        guard blocking.isEmpty else { return nil }
        guard let chars = event.characters(byApplyingModifiers: []),
              let scalar = chars.unicodeScalars.first else { return nil }
        let base = scalar.value
        let lower = (base >= 0x41 && base <= 0x5A) ? base + 0x20 : base
        switch lower {
        case 0x63: return 0x03  // Ctrl+C → ETX  → SIGINT
        case 0x7A: return 0x1A  // Ctrl+Z → SUB  → SIGTSTP
        case 0x5C: return 0x1C  // Ctrl+\\ → FS   → SIGQUIT
        default: return nil
        }
    }

    /// Text payload for the Ghostty key event, matching Ghostty's own apprt
    /// (`NSEvent+Extension.swift`). NSEvent.characters returns "\\u{03}" for
    /// Ctrl+C — Ghostty's KeyEncoder does control-character mapping itself,
    /// so we hand it the base character ("c") instead of the control byte.
    private func sanitizedCharacters(_ event: NSEvent) -> String? {
        guard let chars = event.characters, !chars.isEmpty else { return nil }
        if chars.count == 1, let scalar = chars.unicodeScalars.first {
            if scalar.value < 0x20 {
                return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
            }
            // PUA range = function keys; Ghostty's encoder handles them by
            // keycode, not text.
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }
        return chars
    }

    override func keyUp(with event: NSEvent) {
        if execMode {
            let keyEvent = buildKeyEvent(for: event, action: GHOSTTY_ACTION_RELEASE)
            if let surface { _ = ghostty_surface_key(surface, keyEvent) }
            return
        }
    }

    override func flagsChanged(with event: NSEvent) {
        // Modifier-only events (Ctrl, Shift, Cmd, Alt alone) carry no
        // character payload. Forwarding them to ghostty_surface_key with
        // unshifted_codepoint=0 produces stray `;5u` fragments at the prompt
        // when Kitty mode's report_all flag is set. Consume the event.
    }

    // MARK: - Standard Edit Selectors
    //
    // Stock AppKit Edit menu items (Cut, Copy, Paste, Select All) dispatch
    // through the responder chain via NSText.* selectors. These IBActions
    // are the terminus on this view — they delegate to libghostty's binding
    // actions which read/write NSPasteboard.general directly.

    @IBAction func paste(_ sender: Any?) {
        guard let surface else { return }
        guard let text = pasteboardContents(NSPasteboard.general), !text.isEmpty else { return }
        text.withCString { cStr in
            ghostty_surface_text_input(surface, cStr, UInt(text.utf8.count))
        }
    }

    /// Pick what to feed the terminal from the pasteboard, mirroring Ghostty's
    /// "opinionated" behaviour: file URLs win over plain text so dragging a
    /// screenshot/image (or any file) out of Finder pastes its shell-escaped
    /// path. Falls back to the plain string for everything else. Raw image
    /// bytes (e.g. a screen-capture to clipboard with no file backing) have no
    /// shell-meaningful form and return nil.
    private func pasteboardContents(_ pb: NSPasteboard) -> String? {
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            return urls.map { $0.isFileURL ? shellEscape($0.path) : $0.absoluteString }
                       .joined(separator: " ")
        }
        return pb.string(forType: .string)
    }

    /// Backslash-escape shell metacharacters so a pasted path is safe to drop
    /// into a live prompt without re-quoting. Matches upstream Ghostty's
    /// `Ghostty.Shell.escape`.
    private func shellEscape(_ str: String) -> String {
        let unsafe = "\\ ()[]{}<>\"'`!#$&;|*?\t"
        var result = str
        for ch in unsafe {
            result = result.replacingOccurrences(of: String(ch), with: "\\\(ch)")
        }
        return result
    }

    @IBAction func copy(_ sender: Any?) {
        guard let surface else { return }
        let action = "copy_to_clipboard"
        _ = ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
    }

    @IBAction override func selectAll(_ sender: Any?) {
        guard let surface else { return }
        let action = "select_all"
        _ = ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
    }

    override func insertText(_ insertString: Any) {
        let text: String
        if let s = insertString as? String { text = s }
        else if let s = insertString as? NSAttributedString { text = s.string }
        else { return }
        guard !text.isEmpty else { return }
        onUserInput?()
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
        // If a context menu is attached, pop it up instead of forwarding the
        // event to the ghostty surface. SwiftUI's `.contextMenu` modifier can't
        // see right-clicks here because this NSView consumes them — so the
        // menu is set directly on the view by PaneTerminalView.
        if let menu {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
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
        keyEvent.unshifted_codepoint = unshiftedCodepoint(for: event)
        return keyEvent
    }

    /// The codepoint the key would produce with no modifiers (including Shift).
    /// Required by Ghostty's Kitty keyboard protocol encoder: for Ctrl+letter
    /// it builds `CSI <codepoint>;<mods> u` from this field. ASCII letters are
    /// lowercased so Ctrl+Shift+C reports base 'c' the same as Ctrl+C does.
    ///
    /// Uses `characters(byApplyingModifiers: [])` rather than
    /// `charactersIgnoringModifiers` — the latter returns the control byte
    /// (e.g. "\u{03}" for Ctrl+C) instead of the base letter, so unshifted
    /// codepoint would be 3 instead of 99 and Ghostty would emit ESC[3;5u.
    /// Mirrors Ghostty's own apprt (`NSEvent+Extension.swift`).
    private func unshiftedCodepoint(for event: NSEvent) -> UInt32 {
        guard let chars = event.characters(byApplyingModifiers: []),
              let scalar = chars.unicodeScalars.first else { return 0 }
        if scalar.value >= 0x41, scalar.value <= 0x5A {
            return scalar.value + 0x20
        }
        return scalar.value
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
