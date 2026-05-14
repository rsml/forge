# Native Pane Rendering — Phases 1 & 2

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route tmux `%output` events to per-pane SwiftTerm views, proving the data flow end-to-end with single-pane rendering.

**Architecture:** `TmuxControlMode` stops discarding `%output` lines and passes them to a new `onOutput` callback. `OutputRouter` dispatches decoded bytes to `SwiftTermRenderer` instances (one per pane). `PaneTerminalView` embeds the renderer's `TerminalView` in SwiftUI. A feature flag gates between old (`tmux attach`) and new (per-pane) rendering.

**Tech Stack:** Swift 6.0, SwiftTerm (`TerminalView` base class, not `LocalProcessTerminalView`), ForgeCore SPM target

**Spec:** `docs/superpowers/specs/2026-05-13-native-pane-rendering-design.md`

---

### Task 1: Feature flag

**Files:**
- Modify: `Sources/Infrastructure/Config/ForgeConfig.swift`
- Modify: `Sources/Infrastructure/Config/ForgeConfigStore.swift`

- [ ] **Step 1: Add `nativePaneRendering` to GeneralSettings**

In `ForgeConfig.swift`, add to `GeneralSettings`:

```swift
var nativePaneRendering: Bool?
```

- [ ] **Step 2: Add convenience accessor to ForgeConfigStore**

In `ForgeConfigStore.swift`, add a computed property:

```swift
var isNativePaneRendering: Bool {
    config.general?.nativePaneRendering ?? false
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Sources/Infrastructure/Config/ForgeConfig.swift Sources/Infrastructure/Config/ForgeConfigStore.swift
git commit -m "feat: add nativePaneRendering feature flag"
```

---

### Task 2: Tmux output escape decoder (TDD)

**Files:**
- Create: `Sources/Core/TmuxOutputDecoder.swift`
- Create: `Tests/ForgeTests/TmuxOutputDecoderTests.swift`

Tmux control mode encodes `%output` payloads with its own escaping: `\015` for CR, `\012` for LF, `\\` for backslash. This is NOT URL percent-encoding. We need a decoder in Core (pure function, no framework imports).

- [ ] **Step 1: Write failing tests**

```swift
import Testing
@testable import ForgeCore

@Suite("TmuxOutputDecoder")
struct TmuxOutputDecoderTests {

    @Test("plain text passes through unchanged")
    func plainText() {
        let result = TmuxOutputDecoder.decode("hello world")
        #expect(result == [UInt8]("hello world".utf8))
    }

    @Test("decodes octal-escaped newline")
    func octalNewline() {
        let result = TmuxOutputDecoder.decode("hello\\012world")
        #expect(result == [UInt8]("hello".utf8) + [0x0A] + [UInt8]("world".utf8))
    }

    @Test("decodes octal-escaped carriage return")
    func octalCR() {
        let result = TmuxOutputDecoder.decode("line\\015\\012")
        #expect(result == [UInt8]("line".utf8) + [0x0D, 0x0A])
    }

    @Test("decodes escaped backslash")
    func escapedBackslash() {
        let result = TmuxOutputDecoder.decode("path\\\\dir")
        #expect(result == [UInt8]("path\\dir".utf8))
    }

    @Test("handles mixed content")
    func mixedContent() {
        let result = TmuxOutputDecoder.decode("\\033[1mBold\\033[0m\\012")
        #expect(result == [0x1B] + [UInt8]("[1mBold".utf8) + [0x1B] + [UInt8]("[0m".utf8) + [0x0A])
    }

    @Test("empty string returns empty array")
    func emptyString() {
        let result = TmuxOutputDecoder.decode("")
        #expect(result.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TmuxOutputDecoder 2>&1 | tail -5`
Expected: Compilation error — `TmuxOutputDecoder` does not exist

- [ ] **Step 3: Implement decoder**

```swift
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
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter TmuxOutputDecoder 2>&1 | tail -10`
Expected: All 6 tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/TmuxOutputDecoder.swift Tests/ForgeTests/TmuxOutputDecoderTests.swift
git commit -m "feat: add TmuxOutputDecoder for control mode %output escaping"
```

---

### Task 3: TmuxControlMode — route `%output` events

**Files:**
- Modify: `Sources/Core/Ports/TmuxPort.swift`
- Modify: `Sources/Infrastructure/Tmux/TmuxControlMode.swift`
- Modify: `Sources/Infrastructure/Tmux/TmuxAdapter.swift`
- Modify: `Sources/WorkspaceController.swift`

- [ ] **Step 1: Add `onOutput` to TmuxControlPort**

In `TmuxPort.swift`, update the protocol:

```swift
public protocol TmuxControlPort {
    var configPath: String? { get }

    func startControlMode(
        onEvent: @escaping @Sendable (String) -> Void,
        onOutput: (@Sendable (String, Data) -> Void)?,
        onDisconnect: (@Sendable () -> Void)?,
        onReconnect: (@Sendable () -> Void)?
    )
    func stopControlMode()
}
```

- [ ] **Step 2: Update TmuxControlMode.start to accept `onOutput`**

In `TmuxControlMode.swift`, add the stored property and update `start`:

```swift
private var onOutput: (@Sendable (String, Data) -> Void)?
```

In `start(...)`:
```swift
func start(
    onEvent: @escaping @Sendable (String) -> Void,
    onOutput: (@Sendable (String, Data) -> Void)? = nil,
    onDisconnect: (@Sendable () -> Void)? = nil,
    onReconnect: (@Sendable () -> Void)? = nil
) {
    lock.lock()
    self.onEvent = onEvent
    self.onOutput = onOutput
    self.onDisconnect = onDisconnect
    self.onReconnect = onReconnect
    // ... rest unchanged
```

- [ ] **Step 3: Update `handleOutput` to parse and route `%output` lines**

Replace the current `handleOutput` method:

```swift
private func handleOutput(_ text: String) {
    buffer += text
    while let idx = buffer.firstIndex(of: "\n") {
        let line = String(buffer[buffer.startIndex..<idx])
        buffer = String(buffer[buffer.index(after: idx)...])
        if line.hasPrefix("%output ") {
            parseAndRouteOutput(line)
        } else if line.hasPrefix("%") {
            onEvent?(line)
        }
    }
}

private func parseAndRouteOutput(_ line: String) {
    // Format: %output %<pane_id> <escaped_data>
    // Example: %output %5 hello\012world
    guard let firstSpace = line.index(line.startIndex, offsetBy: 8, limitedBy: line.endIndex),
          let secondSpace = line[firstSpace...].firstIndex(of: " ") else { return }
    let paneId = String(line[firstSpace..<secondSpace])
    let payload = String(line[line.index(after: secondSpace)...])
    let decoded = TmuxOutputDecoder.decode(payload)
    guard !decoded.isEmpty else { return }
    onOutput?(paneId, Data(decoded))
}
```

- [ ] **Step 4: Update TmuxAdapter.startControlMode to pass through `onOutput`**

```swift
func startControlMode(
    onEvent: @escaping @Sendable (String) -> Void,
    onOutput: (@Sendable (String, Data) -> Void)?,
    onDisconnect: (@Sendable () -> Void)?,
    onReconnect: (@Sendable () -> Void)?
) {
    controlMode.start(onEvent: onEvent, onOutput: onOutput, onDisconnect: onDisconnect, onReconnect: onReconnect)
}
```

- [ ] **Step 5: Update WorkspaceController.startControlMode to pass `onOutput: nil` for now**

In `WorkspaceController.swift`, update the call in `startControlMode()`:

```swift
tmux.startControlMode(
    onEvent: { [weak self] event in
        Task { @MainActor in
            self?.handleEvent(event)
        }
    },
    onOutput: nil,  // Wired in Phase 2
    onDisconnect: { ... },  // existing
    onReconnect: { ... }    // existing
)
```

- [ ] **Step 6: Build and test**

Run: `swift build && swift test 2>&1 | tail -5`
Expected: Build succeeds, all tests pass

- [ ] **Step 7: Commit**

```bash
git add Sources/Core/Ports/TmuxPort.swift Sources/Infrastructure/Tmux/TmuxControlMode.swift Sources/Infrastructure/Tmux/TmuxAdapter.swift Sources/WorkspaceController.swift
git commit -m "feat: route %output events through TmuxControlPort"
```

---

### Task 4: TerminalRenderer protocol and SwiftTermRenderer

**Files:**
- Create: `Sources/Infrastructure/Terminal/TerminalRenderer.swift`
- Create: `Sources/Infrastructure/Terminal/SwiftTermRenderer.swift`

- [ ] **Step 1: Create the TerminalRenderer protocol**

```swift
import AppKit

/// Swappable terminal rendering abstraction.
/// SwiftTerm today, libghostty later. Lives in Infrastructure (not Core)
/// because terminal rendering is not a domain concern.
@MainActor
protocol TerminalRenderer: AnyObject {
    /// The NSView to embed in the view hierarchy.
    var view: NSView { get }

    /// Feed raw terminal output bytes for rendering.
    func feed(_ data: Data)

    /// Seed scrollback with captured content (on reconnect).
    func feedScrollback(_ content: String)

    /// Resize the terminal to the given dimensions.
    func resize(cols: Int, rows: Int)
}
```

- [ ] **Step 2: Create SwiftTermRenderer**

```swift
import AppKit
import SwiftTerm

/// SwiftTerm implementation of TerminalRenderer.
/// Uses the base `TerminalView` (not `LocalProcessTerminalView`) — no process needed.
/// Keystrokes are reported via `onInput`, resize via `onResize`.
@MainActor
final class SwiftTermRenderer: NSObject, TerminalRenderer, TerminalViewDelegate {
    let terminalView: TerminalView
    var onInput: ((Data) -> Void)?
    var onResize: ((Int, Int) -> Void)?

    var view: NSView { terminalView }

    init(font: NSFont, foreground: NSColor, background: NSColor, colors: [SwiftTerm.Color]?) {
        terminalView = TerminalView(frame: .zero)
        super.init()
        terminalView.autoresizingMask = [.width, .height]
        terminalView.font = font
        terminalView.nativeForegroundColor = foreground
        terminalView.nativeBackgroundColor = background
        if let colors, colors.count == 16 {
            terminalView.installColors(colors)
        }
        terminalView.terminalDelegate = self
    }

    func feed(_ data: Data) {
        let bytes = ArraySlice([UInt8](data))
        terminalView.feed(byteArray: bytes)
    }

    func feedScrollback(_ content: String) {
        terminalView.feed(text: content)
    }

    func resize(cols: Int, rows: Int) {
        terminalView.resize(cols: cols, rows: rows)
    }

    // MARK: - TerminalViewDelegate

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        onInput?(Data(data))
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        onResize?(newCols, newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func clipboardCopy(source: TerminalView, content: Data) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(content, forType: .string)
    }
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func bell(source: TerminalView) {}
}
```

Note: `TerminalViewDelegate` has many methods. Only `send` and `sizeChanged` are functionally required. The rest are stubs. `clipboardCopy` and `requestOpenLink` provide basic clipboard and URL support for free.

- [ ] **Step 3: Create Infrastructure/Terminal directory and build**

Run: `mkdir -p Sources/Infrastructure/Terminal && swift build 2>&1 | tail -5`

The build may fail on missing `TerminalViewDelegate` methods — SwiftTerm's protocol may have additional required methods. Check the compiler errors and add stubs as needed.

- [ ] **Step 4: Fix any missing delegate methods and rebuild**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add Sources/Infrastructure/Terminal/
git commit -m "feat: add TerminalRenderer protocol and SwiftTermRenderer"
```

---

### Task 5: OutputRouter

**Files:**
- Create: `Sources/Infrastructure/Terminal/OutputRouter.swift`

- [ ] **Step 1: Implement OutputRouter**

```swift
import Foundation
import AppKit

/// Routes decoded %output data to per-pane TerminalRenderer instances.
/// Pane lifecycle managed via register/unregister — wired at the composition root.
@MainActor
final class OutputRouter {
    private var renderers: [String: TerminalRenderer] = [:]

    func register(paneId: String, renderer: TerminalRenderer) {
        renderers[paneId] = renderer
    }

    func unregister(paneId: String) {
        renderers.removeValue(forKey: paneId)
    }

    func unregisterAll() {
        renderers.removeAll()
    }

    /// Called from the onOutput callback. Must be dispatched to main thread by caller.
    func route(paneId: String, data: Data) {
        renderers[paneId]?.feed(data)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/Infrastructure/Terminal/OutputRouter.swift
git commit -m "feat: add OutputRouter for per-pane %output dispatch"
```

---

### Task 6: PaneTerminalView — SwiftUI wrapper

**Files:**
- Create: `Sources/Features/Terminal/PaneTerminalView.swift`

- [ ] **Step 1: Implement PaneTerminalView**

```swift
import SwiftUI
import SwiftTerm

/// Embeds a single TerminalRenderer's NSView in SwiftUI. One per pane.
struct PaneTerminalView: NSViewRepresentable {
    let renderer: SwiftTermRenderer

    func makeNSView(context: Context) -> NSView {
        let view = renderer.view
        view.autoresizingMask = [.width, .height]
        // Grab focus
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/Features/Terminal/PaneTerminalView.swift
git commit -m "feat: add PaneTerminalView SwiftUI wrapper"
```

---

### Task 7: Wire it up — TerminalArea feature flag + composition root

**Files:**
- Modify: `Sources/Features/Terminal/TerminalArea.swift`
- Modify: `Sources/ForgeApp.swift` (AppDelegate)
- Modify: `Sources/WorkspaceController.swift`
- Modify: `Sources/Infrastructure/Tmux/TmuxControlMode.swift`

This is the integration task. It wires the output router at the composition root, gates TerminalArea on the feature flag, and configures control mode init commands based on the flag.

- [ ] **Step 1: Add OutputRouter to AppDelegate**

In `ForgeApp.swift`, add to `AppDelegate`:

```swift
let outputRouter = OutputRouter()
```

- [ ] **Step 2: Wire `onOutput` in WorkspaceController**

Add `outputRouter` as a property on `WorkspaceController`:

```swift
var outputRouter: OutputRouter?
```

In `WorkspaceController.startControlMode()`, wire the `onOutput` callback:

```swift
onOutput: { [weak self] paneId, data in
    Task { @MainActor in
        self?.outputRouter?.route(paneId: paneId, data: data)
    }
},
```

In `AppDelegate.applicationDidFinishLaunching`, after creating the controller:

```swift
controller.outputRouter = outputRouter
```

- [ ] **Step 3: Update TmuxControlMode init commands based on feature flag**

The control mode currently sends `refresh-client -C 1,1` on connect. With native rendering, this must be skipped (the control mode client size is irrelevant when there's no `tmux attach` view).

In `TmuxControlMode`, add a `nativeRendering` flag:

```swift
var nativeRendering = false
```

In `launchProcess()`, change the init commands:

```swift
var initCommands = "refresh-client -B \"silence:@*:#{window_silence_flag}\""
if !nativeRendering {
    initCommands = "refresh-client -C 1,1\n" + initCommands
}
```

In `TmuxAdapter`, set the flag before starting:

```swift
func startControlMode(...) {
    controlMode.nativeRendering = // read from config
    controlMode.start(...)
}
```

Pass the config flag through — add a `nativeRendering` property to `TmuxAdapter` that `AppDelegate` sets.

- [ ] **Step 4: Gate TerminalArea on feature flag**

In `TerminalArea.swift`:

```swift
struct TerminalArea: View {
    var project: Project
    @Environment(ForgeConfigStore.self) private var configStore

    var body: some View {
        if configStore.isNativePaneRendering {
            nativeTerminalView
        } else {
            legacyTerminalView
        }
    }

    private var legacyTerminalView: some View {
        ForgeTerminalView(sessionName: project.name)
            .padding(.trailing, -15)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: [.bottom, .trailing])
            .id(project.id)
            .background(Color(red: 0.1, green: 0.1, blue: 0.1))
    }

    @ViewBuilder
    private var nativeTerminalView: some View {
        // Phase 2: single-pane rendering — show the first pane of the active tab
        // Full multi-pane layout comes in Phase 3
        Text("Native rendering — Phase 2")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.1, green: 0.1, blue: 0.1))
    }
}
```

This is a placeholder — Task 8 wires the actual renderer.

- [ ] **Step 5: Build and test**

Run: `swift build && swift test 2>&1 | tail -5`
Expected: Build succeeds, all tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/Features/Terminal/TerminalArea.swift Sources/ForgeApp.swift Sources/WorkspaceController.swift Sources/Infrastructure/Tmux/TmuxControlMode.swift Sources/Infrastructure/Tmux/TmuxAdapter.swift
git commit -m "feat: wire OutputRouter and feature flag for native pane rendering"
```

---

### Task 8: Single-pane rendering end-to-end

**Files:**
- Modify: `Sources/Features/Terminal/TerminalArea.swift`
- Modify: `Sources/WorkspaceController.swift`

This replaces the placeholder in Task 7 with actual per-pane rendering. For Phase 2, we render only the first pane of the active tab.

- [ ] **Step 1: Create and register renderer when project changes**

In `WorkspaceController`, add a method to create a renderer for a pane and register it:

```swift
func createRenderer(for paneId: String) -> SwiftTermRenderer? {
    let font = FontResolver.resolveTerminalFont(
        family: config.config.terminalFont?.family ?? config.config.terminal?.fontFamily,
        size: CGFloat(config.config.terminalFont?.size ?? config.config.terminal?.fontSize ?? 13)
    )
    let fg: NSColor
    let bg: NSColor
    var colors: [SwiftTerm.Color]?
    if let theme = config.resolvedTheme {
        fg = NSColor(theme.foreground.color)
        bg = NSColor(theme.background.color)
        let palette = theme.ansiColors.prefix(16).map { ForgeTerminalView.themeColorToTermColor($0) }
        colors = palette.count == 16 ? palette : nil
    } else {
        fg = NSColor(red: 0.77, green: 0.78, blue: 0.78, alpha: 1.0)
        bg = NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
    }
    let renderer = SwiftTermRenderer(font: font, foreground: fg, background: bg, colors: colors)
    renderer.onInput = { [weak self] data in
        let hex = data.map { String(format: "%02x", $0) }.joined()
        self?.tmux.controlModeSend("send-keys -H -t \(paneId) \(hex)")
    }
    renderer.onResize = { [weak self] cols, rows in
        self?.tmux.controlModeSend("resize-pane -t \(paneId) -x \(cols) -y \(rows)")
    }
    outputRouter?.register(paneId: paneId, renderer: renderer)
    return renderer
}
```

Note: This requires exposing `controlMode.send` through a new method on `TmuxAdapter` (or reusing the existing one). The `send-keys -H` and `resize-pane` commands go through `controlMode.send()` for sub-ms latency.

Add a `controlModeSend` method to `TmuxCommandPort` or directly expose it:

In `TmuxAdapter.swift`:
```swift
func controlModeSend(_ command: String) {
    controlMode.send(command)
}
```

- [ ] **Step 2: Expose the active renderer for TerminalArea**

In `WorkspaceController`, add an observable property:

```swift
var activeRenderer: SwiftTermRenderer?
```

Update it when the active pane changes. For Phase 2, create the renderer lazily when `TerminalArea` needs it (via a method the view calls).

- [ ] **Step 3: Wire native rendering in TerminalArea**

Replace the Phase 2 placeholder:

```swift
@ViewBuilder
private var nativeTerminalView: some View {
    if let renderer = controller.activeRenderer {
        PaneTerminalView(renderer: renderer)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(renderer.terminalView.hashValue)
    } else {
        Color(red: 0.1, green: 0.1, blue: 0.1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

Add `@Environment(WorkspaceController.self) private var controller` to `TerminalArea`.

- [ ] **Step 4: Seed scrollback on connect**

In `WorkspaceController.connect()`, after sync engine refresh and before starting control mode, seed renderers for existing panes:

```swift
if config.isNativePaneRendering {
    for project in workspace.projects {
        for tab in project.tabs {
            for pane in tab.panes {
                if let renderer = createRenderer(for: pane.id) {
                    // Seed scrollback from tmux
                    if let content = await tmux.capturePaneContent(id: pane.id, lastN: 5000) {
                        renderer.feedScrollback(content)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: Build succeeds. Compiler may flag issues with `ForgeTerminalView.themeColorToTermColor` access level — make it `static` and `internal` if needed.

- [ ] **Step 6: Commit**

```bash
git add Sources/WorkspaceController.swift Sources/Features/Terminal/TerminalArea.swift Sources/Infrastructure/Tmux/TmuxAdapter.swift
git commit -m "feat: single-pane native rendering via %output"
```

---

### Task 9: Manual verification

- [ ] **Step 1: Enable the feature flag**

Add to `~/.config/forge/config.json`:
```json
{
  "general": {
    "nativePaneRendering": true
  }
}
```

- [ ] **Step 2: Build and launch**

Run: `make dev`

- [ ] **Step 3: Test basic output**

Open a single-tab, single-pane project. Run commands:
- `echo hello` — text appears
- `ls --color` — colors render correctly
- `htop` or `top` — full-screen TUI renders

- [ ] **Step 4: Test input**

- Type commands — keystrokes appear with no perceptible lag
- Arrow keys, tab completion, Ctrl+C work
- Backspace, delete work

- [ ] **Step 5: Test resize**

Resize the Forge window. Terminal content reflows correctly.

- [ ] **Step 6: Test text selection**

Click and drag to select text. Selection wraps correctly within the pane (the original motivation).

- [ ] **Step 7: Verify with old path**

Remove the feature flag (or set to false). Verify the old `tmux attach` path still works unchanged.

- [ ] **Step 8: Check logs**

```bash
tail -30 /tmp/forge.log
```
No errors related to output routing.

- [ ] **Step 9: Screenshot**

```bash
curl localhost:7654/screenshot > /tmp/forge-screenshot.png
```
Read to visually confirm terminal renders correctly.
