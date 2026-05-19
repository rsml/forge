# Browser Panes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Commits are user-gated.** Forge's CLAUDE.md says only commit when asked. The "Suggested commit" step at the end of each task contains the recommended message — present it to the user; don't auto-run unless they say go.

**Goal:** Add WebKit-backed browser panes to Forge as a first-class pane content-type (alongside terminal), driven by the design in `docs/superpowers/specs/2026-05-19-browser-pane-design.md`.

**Architecture:** Refactor `Pane` to carry a `PaneContent` tagged union (`.terminal(TerminalState)` | `.browser(BrowserState)`) with reference-typed sub-states. Hoist a `PaneRenderer` parent protocol so terminal and browser renderers coexist in `paneRenderers`. Add `WebKitBrowserRenderer` adapter. New right-click submenu for split-as-Terminal/Browser; bidirectional convert flow reuses existing active-process confirmation. Three chrome modes (Full / Slim / None) configurable in Settings → General → Browser, defaulting to None. New URL Palette with localhost-port suggestions sourced from sibling panes via a pure `PortDetector` helper.

**Tech Stack:** Swift 6.0, Swift Testing, SwiftUI (macOS 14+), AppKit, WebKit (`WKWebView`), ForgeCore SPM target.

**Scope:** Native PTY only (`nativePTY: true`). No tmux-mode support.

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `Sources/Core/Models/Pane.swift` | Replace flat terminal fields with `PaneContent` enum + reference sub-states |
| Create | `Sources/Core/PortDetector.swift` | Pure regex scan for `host:port` patterns in pane scrollback |
| Create | `Sources/Infrastructure/PaneRenderer.swift` | Parent protocol — `view`, `setFocused` |
| Modify | `Sources/Infrastructure/Terminal/TerminalRenderer.swift` | Refine `TerminalRenderer` to extend `PaneRenderer` |
| Create | `Sources/Infrastructure/Browser/BrowserRenderer.swift` | Browser protocol — `loadURL`, `goBack`, `reload`, callbacks |
| Create | `Sources/Infrastructure/Browser/NavigationIntent.swift` | Enum: `.sameTabBlank`, `.popupWindow`, `.modifierNewPane` |
| Create | `Sources/Infrastructure/Browser/WebKitBrowserRenderer.swift` | `WKWebView` adapter conforming to `BrowserRenderer` |
| Create | `Sources/Infrastructure/Browser/BrowserPopupWindow.swift` | `NSPanel` for `window.open()` popups |
| Create | `Sources/Features/Browser/BrowserPaneView.swift` | SwiftUI host; selects chrome view by config |
| Create | `Sources/Features/Browser/BrowserChromeFull.swift` | Mode A view |
| Create | `Sources/Features/Browser/BrowserChromeSlim.swift` | Mode B view |
| Create | `Sources/Features/Browser/BrowserChromeNone.swift` | Mode C view + floating URL pill |
| Create | `Sources/Features/Browser/BrowserURLPalette.swift` | Centered URL input sheet with suggestions |
| Create | `Sources/Features/Browser/BrowserFindBar.swift` | ⌘F find-in-page bar |
| Modify | `Sources/Infrastructure/Config/ForgeConfig.swift` | Add `browserChromeType: String?` to `GeneralSettings` |
| Modify | `Sources/Features/Settings/GeneralSettingsPane.swift` | Add `Section("Browser")` with picker + dynamic subtext |
| Modify | `Sources/WorkspaceController.swift` | Retype `paneRenderers` to `[String: any PaneRenderer]` |
| Modify | `Sources/WorkspaceController+Actions.swift` | Split-as-Browser, convert flows, browser pane lifecycle |
| Modify | `Sources/WorkspaceController+Rendering.swift` | Renderer creation dispatches on `pane.kind` |
| Modify | `Sources/Features/TabBar/WindowTab.swift` | Context menu: Split submenus + dynamic Convert |
| Modify | `Sources/Features/Sidebar/SidebarTabRow.swift` | Mirror tab-bar context menu |
| Modify | `Sources/Infrastructure/Config/UIStatePersistence.swift` (or workspace persistence) | `workspace.json` schema: `content: {kind, url?}` |
| Create | `Tests/ForgeTests/PaneContentTests.swift` | Codec + accessor tests |
| Create | `Tests/ForgeTests/PortDetectorTests.swift` | Regex correctness, false-positive resistance |
| Modify | Existing tests touching `pane.currentCommand` etc. | Migrate to `pane.terminalState?.currentCommand` |

Total: ~20 new/modified files. Plan tasks are sized so each ends in a buildable, testable state.

---

### Task 1: Extract `TerminalState` from `Pane`

**Goal:** Move all terminal-specific fields off `Pane` into a new `TerminalState` reference type, with `pane.terminalState: TerminalState` as the accessor. No browser fields yet — this is a pure refactor.

**Files:**
- Modify: `Sources/Core/Models/Pane.swift`
- Modify: all callsites reading `pane.currentCommand`, `pane.currentPath`, `pane.pid`, `pane.status`, `pane.hasBell`, `pane.hasContentMatch`, `pane.previousCommand`, `pane.width`, `pane.height`
- Test: `Tests/ForgeTests/PaneContentTests.swift` (new)

- [ ] **Step 1: Update `Pane.swift` to introduce `TerminalState`**

Replace `Sources/Core/Models/Pane.swift` with:

```swift
import Foundation
import Observation

public enum PaneStatus: String, Sendable, Codable {
    case idle, running, needsAttention, error

    public static func from(command: String) -> PaneStatus {
        let lower = command.lowercased()
        let shells: Set<String> = ["zsh", "bash", "fish", "sh", "nu", "pwsh"]
        if lower.isEmpty || shells.contains(lower) { return .idle }
        return .running
    }
}

public enum PaneKind: String, Sendable, Codable { case terminal, browser }

@Observable @MainActor
public final class TerminalState {
    public var currentCommand: String
    public var currentPath: String
    public var width: Int
    public var height: Int
    public var pid: Int
    public var status: PaneStatus
    public var hasBell: Bool
    public var hasContentMatch: Bool
    public var previousCommand: String

    public var needsAttention: Bool {
        status == .idle || hasBell || hasContentMatch || status == .needsAttention || status == .error
    }

    public init(currentCommand: String = "", currentPath: String = "",
                width: Int = 80, height: Int = 24, pid: Int = 0) {
        self.currentCommand = currentCommand
        self.currentPath = currentPath
        self.width = width
        self.height = height
        self.pid = pid
        self.status = PaneStatus.from(command: currentCommand)
        self.hasBell = false
        self.hasContentMatch = false
        self.previousCommand = ""
    }
}

@Observable @MainActor
public final class Pane: Identifiable {
    public let id: String
    public let tabId: String
    public var index: Int
    public var active: Bool
    public let terminalState: TerminalState   // for now: every pane is a terminal

    public var kind: PaneKind { .terminal }

    public var needsAttention: Bool { terminalState.needsAttention }

    public init(id: String, tabId: String, index: Int = 0, active: Bool = false,
                currentCommand: String = "", currentPath: String = "",
                width: Int = 80, height: Int = 24, pid: Int = 0) {
        self.id = id
        self.tabId = tabId
        self.index = index
        self.active = active
        self.terminalState = TerminalState(
            currentCommand: currentCommand, currentPath: currentPath,
            width: width, height: height, pid: pid
        )
    }
}
```

- [ ] **Step 2: Migrate all callsites**

Use the compiler. After Step 1, `swift build` will flag every `pane.currentCommand`, `pane.pid`, etc. Rewrite each to `pane.terminalState.currentCommand` etc. Expected hot spots:
- `Sources/Core/StateMerger.swift`
- `Sources/Infrastructure/Tmux/TmuxStateParser.swift`
- `Sources/Infrastructure/Tmux/TmuxSyncEngine.swift`
- `Sources/Features/Attention/AttentionManager.swift`
- `Sources/Features/Sidebar/SidebarTabRow.swift` (status dot)
- `Sources/Features/Terminal/*` (any pane-status display)
- `Sources/WorkspaceController*.swift`

Run `swift build` repeatedly; fix until clean.

- [ ] **Step 3: Verify tests still pass**

Run: `swift test`
Expected: PASS. The refactor is purely additive — same data, different shape.

- [ ] **Step 4: Suggested commit**

```bash
git add Sources Tests
git commit -m "refactor: extract TerminalState from Pane (no behavior change)"
```

---

### Task 2: Introduce `PaneContent` enum + `BrowserState`

**Goal:** Replace `pane.terminalState: TerminalState` with `pane.content: PaneContent` (enum-with-payload). Add `BrowserState` reference type for the browser case. Keep `pane.kind`, add `pane.browserState` accessor.

**Files:**
- Modify: `Sources/Core/Models/Pane.swift`
- Create: `Tests/ForgeTests/PaneContentTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/ForgeTests/PaneContentTests.swift`:

```swift
import Testing
import Foundation
@testable import ForgeCore

@MainActor
struct PaneContentTests {
    @Test("terminal pane exposes terminalState, not browserState")
    func testTerminalAccessor() {
        let pane = Pane(id: "p1", tabId: "t1", currentCommand: "zsh")
        #expect(pane.terminalState != nil)
        #expect(pane.browserState == nil)
        #expect(pane.kind == .terminal)
    }

    @Test("browser pane exposes browserState, not terminalState")
    func testBrowserAccessor() {
        let pane = Pane.browser(id: "p2", tabId: "t1", url: URL(string: "https://localhost:3000"))
        #expect(pane.terminalState == nil)
        #expect(pane.browserState != nil)
        #expect(pane.browserState?.url?.absoluteString == "https://localhost:3000")
        #expect(pane.kind == .browser)
    }

    @Test("browser pane never needsAttention")
    func testBrowserNeverAttention() {
        let pane = Pane.browser(id: "p3", tabId: "t1", url: nil)
        #expect(pane.needsAttention == false)
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

Run: `swift test`
Expected: COMPILE ERROR — `terminalState` is non-optional today, `Pane.browser(...)` factory doesn't exist.

- [ ] **Step 3: Update `Pane.swift`**

```swift
public enum PaneContent {
    case terminal(TerminalState)
    case browser(BrowserState)
}

@Observable @MainActor
public final class BrowserState {
    public var url: URL?
    public var pageTitle: String
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var isLoading: Bool
    public var loadingProgress: Double
    public var favicon: NSImage?

    public init(url: URL? = nil) {
        self.url = url
        self.pageTitle = ""
        self.canGoBack = false
        self.canGoForward = false
        self.isLoading = false
        self.loadingProgress = 0.0
        self.favicon = nil
    }
}

@Observable @MainActor
public final class Pane: Identifiable {
    public let id: String
    public let tabId: String
    public var index: Int
    public var active: Bool
    public var content: PaneContent

    public var terminalState: TerminalState? {
        if case let .terminal(s) = content { return s } else { return nil }
    }
    public var browserState: BrowserState? {
        if case let .browser(s) = content { return s } else { return nil }
    }
    public var kind: PaneKind {
        switch content { case .terminal: .terminal; case .browser: .browser }
    }

    public var needsAttention: Bool {
        terminalState?.needsAttention ?? false
    }

    public init(id: String, tabId: String, index: Int = 0, active: Bool = false,
                currentCommand: String = "", currentPath: String = "",
                width: Int = 80, height: Int = 24, pid: Int = 0) {
        self.id = id
        self.tabId = tabId
        self.index = index
        self.active = active
        self.content = .terminal(TerminalState(
            currentCommand: currentCommand, currentPath: currentPath,
            width: width, height: height, pid: pid
        ))
    }

    public static func browser(id: String, tabId: String, index: Int = 0,
                                active: Bool = false, url: URL? = nil) -> Pane {
        let p = Pane(id: id, tabId: tabId, index: index, active: active)
        p.content = .browser(BrowserState(url: url))
        return p
    }
}

// NSImage is AppKit; for Core purity, gate behind canImport.
#if canImport(AppKit)
import AppKit
#endif
```

**Note on `NSImage`:** Core is supposed to be framework-free per CLAUDE.md, but `NSImage` is needed for favicon. Two options: (a) wrap with `#if canImport(AppKit)`; (b) use raw `Data` in `BrowserState`, convert at the renderer boundary. Prefer **(b)** for purity:

```swift
public var faviconData: Data?    // PNG/JPEG bytes; renderer converts to NSImage
```

Update tests accordingly.

- [ ] **Step 4: Migrate `pane.terminalState` callsites**

`pane.terminalState` is now `Optional<TerminalState>`. Every site needs `?` or `!` or guard. Use the compiler.

- [ ] **Step 5: Run tests — expect PASS**

Run: `swift test`
Expected: PASS, including the new `PaneContentTests`.

- [ ] **Step 6: Suggested commit**

```bash
git add Sources Tests
git commit -m "feat: add PaneContent enum and BrowserState (no UI yet)"
```

---

### Task 3: Hoist `PaneRenderer` parent protocol

**Goal:** Introduce a shared parent protocol so the `paneRenderers` dict can hold both terminal and browser renderers via a common interface.

**Files:**
- Create: `Sources/Infrastructure/PaneRenderer.swift`
- Modify: `Sources/Infrastructure/Terminal/TerminalRenderer.swift`
- Modify: `Sources/WorkspaceController.swift` (type of `paneRenderers`)
- Modify: all callsites doing `as? GhosttyRenderer` (no behavior change)

- [ ] **Step 1: Create `Sources/Infrastructure/PaneRenderer.swift`**

```swift
import AppKit

/// Common interface for any pane-content renderer (terminal, browser, future kinds).
/// Concrete adapters refine this protocol with kind-specific methods.
@MainActor
protocol PaneRenderer: AnyObject {
    var view: NSView { get }
    func setFocused(_ focused: Bool)
}
```

- [ ] **Step 2: Refine `TerminalRenderer`**

`Sources/Infrastructure/Terminal/TerminalRenderer.swift`:

```swift
import AppKit

@MainActor
protocol TerminalRenderer: PaneRenderer {
    func feed(_ data: Data)
    func feedScrollback(_ content: String)
    var onInput: ((Data) -> Void)? { get set }
    var onResize: ((Int, Int) -> Void)? { get set }
}
```

(Drop redundant `view` and `setFocused` — inherited.)

- [ ] **Step 3: Retype `paneRenderers`**

In `Sources/WorkspaceController.swift:24`:

```swift
var paneRenderers: [String: any PaneRenderer] = [:]
```

- [ ] **Step 4: Fix callsites**

Compile and fix. Most `as? GhosttyRenderer` casts already work (they downcast from `any TerminalRenderer` before; now from `any PaneRenderer`).

- [ ] **Step 5: Build + run**

```
swift build           # expect success
swift test            # expect PASS
make dev              # launch app, verify terminals still render
```

- [ ] **Step 6: Suggested commit**

```bash
git add Sources
git commit -m "refactor: hoist PaneRenderer parent protocol"
```

---

### Task 4: `PortDetector` pure-Core helper

**Goal:** Regex-based detection of `host:port` URLs in pane scrollback. Pure function; testable in isolation.

**Files:**
- Create: `Sources/Core/PortDetector.swift`
- Create: `Tests/ForgeTests/PortDetectorTests.swift`

- [ ] **Step 1: Write failing tests**

`Tests/ForgeTests/PortDetectorTests.swift`:

```swift
import Testing
import Foundation
@testable import ForgeCore

struct PortDetectorTests {
    @Test("detects localhost:3000 in vite output")
    func testVite() {
        let out = """
        VITE v5.0.0  ready in 84 ms
        ➜  Local:   http://localhost:5173/
        ➜  Network: use --host to expose
        """
        let ports = PortDetector.detect(in: out)
        #expect(ports.contains { $0.host == "localhost" && $0.port == 5173 })
    }

    @Test("detects npm run dev port via 'ready on :3000' pattern")
    func testNpmReadyOn() {
        let out = "ready - started server on 0.0.0.0:3000, url: http://localhost:3000"
        let ports = PortDetector.detect(in: out)
        #expect(ports.contains { $0.port == 3000 })
    }

    @Test("ignores timestamps like 12:34:56")
    func testTimestampNoise() {
        let out = "[12:34:56] some log line"
        let ports = PortDetector.detect(in: out)
        #expect(ports.isEmpty)
    }

    @Test("deduplicates repeated ports")
    func testDedup() {
        let out = """
        ready on http://localhost:3000
        listening on http://localhost:3000
        """
        let ports = PortDetector.detect(in: out)
        #expect(ports.filter { $0.port == 3000 }.count == 1)
    }

    @Test("preserves first-seen order")
    func testOrder() {
        let out = """
        backend ready on :8080
        frontend ready on :3000
        """
        let ports = PortDetector.detect(in: out)
        #expect(ports.map(\.port) == [8080, 3000])
    }
}
```

- [ ] **Step 2: Run tests — expect compile error (no PortDetector)**

Run: `swift test --filter PortDetectorTests`
Expected: COMPILE ERROR.

- [ ] **Step 3: Implement `PortDetector`**

`Sources/Core/PortDetector.swift`:

```swift
import Foundation

public struct DetectedPort: Hashable, Sendable {
    public let host: String
    public let port: Int
    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
}

public enum PortDetector {
    private static let strictRegex = try! NSRegularExpression(
        pattern: #"\b(localhost|127\.0\.0\.1|0\.0\.0\.0):(\d{2,5})\b"#,
        options: []
    )
    /// Loose pattern: `:NNNN` preceded by common dev-server keywords. Avoids matching timestamps.
    private static let looseRegex = try! NSRegularExpression(
        pattern: #"(?i)\b(?:ready|listening|started|running|Local|url)\b[^\n]{0,40}?:(\d{4,5})\b"#,
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
            let p = DetectedPort(host: "localhost", port: port)
            if seen.insert(p).inserted { result.append(p) }
        }
        return result
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `swift test --filter PortDetectorTests`
Expected: PASS, all 5 tests.

- [ ] **Step 5: Suggested commit**

```bash
git add Sources/Core/PortDetector.swift Tests/ForgeTests/PortDetectorTests.swift
git commit -m "feat: add PortDetector for sibling-pane URL suggestions"
```

---

### Task 5: `BrowserRenderer` protocol + `NavigationIntent`

**Goal:** Define the contract for any browser adapter. No implementation yet.

**Files:**
- Create: `Sources/Infrastructure/Browser/BrowserRenderer.swift`
- Create: `Sources/Infrastructure/Browser/NavigationIntent.swift`

- [ ] **Step 1: Create `NavigationIntent.swift`**

```swift
import AppKit
import Foundation

enum NavigationIntent {
    case sameTabBlank(URL)
    case popupWindow(URL, size: NSSize?)
    case modifierNewPane(URL)
}
```

- [ ] **Step 2: Create `BrowserRenderer.swift`**

```swift
import AppKit
import Foundation

@MainActor
protocol BrowserRenderer: PaneRenderer {
    var url: URL? { get }

    func loadURL(_ url: URL)
    func goBack()
    func goForward()
    func reload()
    func find(_ query: String)
    func toggleDevTools()
    func setMuted(_ muted: Bool)

    var onURLChange: ((URL) -> Void)? { get set }
    var onTitleChange: ((String) -> Void)? { get set }
    var onLoadProgress: ((Bool, Double) -> Void)? { get set }   // (isLoading, progress)
    var onFaviconChange: ((Data?) -> Void)? { get set }
    var onNavigationRequest: ((NavigationIntent) -> Void)? { get set }
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: PASS (no implementations yet, but protocols compile).

- [ ] **Step 4: Suggested commit**

```bash
git add Sources/Infrastructure/Browser
git commit -m "feat: add BrowserRenderer protocol and NavigationIntent"
```

---

### Task 6: `WebKitBrowserRenderer` adapter

**Goal:** Concrete `BrowserRenderer` backed by `WKWebView`. Minimum: can load a URL, fires callbacks on URL/title/loading change.

**Files:**
- Create: `Sources/Infrastructure/Browser/WebKitBrowserRenderer.swift`

- [ ] **Step 1: Implement the renderer**

```swift
import AppKit
import WebKit

@MainActor
final class WebKitBrowserRenderer: NSObject, BrowserRenderer {
    let view: NSView
    private let webView: WKWebView
    private var observers: [NSKeyValueObservation] = []

    var url: URL? { webView.url }
    var onURLChange: ((URL) -> Void)?
    var onTitleChange: ((String) -> Void)?
    var onLoadProgress: ((Bool, Double) -> Void)?
    var onFaviconChange: ((Data?) -> Void)?
    var onNavigationRequest: ((NavigationIntent) -> Void)?

    init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        self.webView = wv
        self.view = wv
        super.init()
        wv.navigationDelegate = self
        wv.uiDelegate = self
        installObservers()
    }

    private func installObservers() {
        observers.append(webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
            if let u = wv.url { self?.onURLChange?(u) }
        })
        observers.append(webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            self?.onTitleChange?(wv.title ?? "")
        })
        observers.append(webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
            self?.onLoadProgress?(wv.isLoading, wv.estimatedProgress)
        })
        observers.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            self?.onLoadProgress?(wv.isLoading, wv.estimatedProgress)
        })
    }

    func setFocused(_ focused: Bool) {
        if focused { view.window?.makeFirstResponder(webView) }
    }

    func loadURL(_ url: URL) { webView.load(URLRequest(url: url)) }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func setMuted(_ muted: Bool) {
        webView.setValue(muted, forKey: "_muted")   // private API, stable
    }

    func find(_ query: String) {
        let config = WKFindConfiguration()
        webView.find(query, configuration: config) { _ in }
    }

    func toggleDevTools() {
        // Private API — stable across recent macOS versions. Cmux uses the same path.
        guard let inspector = webView.value(forKey: "_inspector") as? NSObject else { return }
        if inspector.value(forKey: "isVisible") as? Bool == true {
            _ = inspector.perform(NSSelectorFromString("hide:"), with: nil)
        } else {
            _ = inspector.perform(NSSelectorFromString("show:"), with: nil)
        }
    }
}

extension WebKitBrowserRenderer: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // ⌘+click → split right as new browser pane
        let cmd = navigationAction.modifierFlags.contains(.command)
        if cmd, let url = navigationAction.request.url, navigationAction.navigationType == .linkActivated {
            onNavigationRequest?(.modifierNewPane(url))
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

extension WebKitBrowserRenderer: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }

        // target="_blank" with no size hints → same pane
        if windowFeatures.width == nil && windowFeatures.height == nil {
            onNavigationRequest?(.sameTabBlank(url))
            return nil
        }

        // window.open() with size → popup window
        let w = windowFeatures.width?.doubleValue ?? 600
        let h = windowFeatures.height?.doubleValue ?? 700
        onNavigationRequest?(.popupWindow(url, size: NSSize(width: w, height: h)))
        return nil
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: PASS.

- [ ] **Step 3: Suggested commit**

```bash
git add Sources/Infrastructure/Browser/WebKitBrowserRenderer.swift
git commit -m "feat: WebKitBrowserRenderer adapter"
```

---

### Task 7: `BrowserPaneView` skeleton (mode None only)

**Goal:** SwiftUI host view for a browser pane. Wraps the WKWebView. Hardcoded to mode None — no chrome, just the page. Verifies end-to-end rendering before chrome work.

**Files:**
- Create: `Sources/Features/Browser/BrowserPaneView.swift`
- Create: `Sources/Features/Browser/BrowserChromeNone.swift`

- [ ] **Step 1: Create `BrowserChromeNone.swift`**

```swift
import SwiftUI
import AppKit

struct BrowserChromeNone: NSViewRepresentable {
    let renderer: any BrowserRenderer

    func makeNSView(context: Context) -> NSView { renderer.view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
```

- [ ] **Step 2: Create `BrowserPaneView.swift`**

```swift
import SwiftUI

struct BrowserPaneView: View {
    let pane: Pane
    let renderer: any BrowserRenderer

    var body: some View {
        // Mode dispatch will land in Task 14; mode None only for now.
        BrowserChromeNone(renderer: renderer)
    }
}
```

- [ ] **Step 3: Wire `BrowserPaneView` into `TerminalArea` / pane host**

Find the view that currently picks `GhosttyRenderer.view` for each pane. Branch on `pane.kind`:

```swift
if pane.kind == .browser, let renderer = paneRenderers[pane.id] as? any BrowserRenderer {
    BrowserPaneView(pane: pane, renderer: renderer)
} else if let renderer = paneRenderers[pane.id] as? GhosttyRenderer {
    TerminalPaneNSView(renderer: renderer)
}
```

(Exact location: `Sources/Features/Terminal/TerminalArea.swift` or equivalent. Find via `grep -rn "GhosttyRenderer.view\|NSViewRepresentable" Sources/Features/Terminal/`.)

- [ ] **Step 4: Smoke-test manually**

Temporarily hardcode a browser pane creation in `WorkspaceController` (will be removed in Task 8). Build and `make dev`. Manually verify a page loads. Remove the hardcode after verification.

- [ ] **Step 5: Suggested commit**

```bash
git add Sources/Features/Browser
git commit -m "feat: BrowserPaneView skeleton (mode None hardcoded)"
```

---

### Task 8: Split-as-Browser plumbing

**Goal:** Add a new `PaneKind` parameter to the split flow. When kind=browser, create a browser pane + WebKitBrowserRenderer instead of a terminal.

**Files:**
- Modify: `Sources/WorkspaceController+Actions.swift` (split flow)
- Modify: `Sources/WorkspaceController+Rendering.swift` (renderer creation dispatch)

- [ ] **Step 1: Extend the split signature**

Find the existing `splitPaneNativePTY` method. Add a `kind: PaneKind = .terminal` parameter:

```swift
func splitPaneNativePTY(direction: SplitDirection, position: SplitPosition, as kind: PaneKind = .terminal) {
    // ... existing logic ...
    let newPane: Pane
    switch kind {
    case .terminal:
        newPane = Pane(id: newPaneId, tabId: tab.id)
        // Existing terminal renderer creation
    case .browser:
        newPane = Pane.browser(id: newPaneId, tabId: tab.id)
        let renderer = WebKitBrowserRenderer()
        wireBrowserCallbacks(renderer: renderer, pane: newPane)
        paneRenderers[newPaneId] = renderer
        // URL palette will auto-open in Task 11
    }
    // ... insert into split tree, update workspace.json ...
}
```

- [ ] **Step 2: Implement `wireBrowserCallbacks`**

In a new extension `Sources/WorkspaceController+Browser.swift`:

```swift
import Foundation

extension WorkspaceController {
    @MainActor
    func wireBrowserCallbacks(renderer: any BrowserRenderer, pane: Pane) {
        renderer.onURLChange = { [weak pane] url in
            pane?.browserState?.url = url
        }
        renderer.onTitleChange = { [weak pane] title in
            pane?.browserState?.pageTitle = title
        }
        renderer.onLoadProgress = { [weak pane] loading, progress in
            pane?.browserState?.isLoading = loading
            pane?.browserState?.loadingProgress = progress
        }
        renderer.onFaviconChange = { [weak pane] data in
            pane?.browserState?.faviconData = data
        }
        renderer.onNavigationRequest = { [weak self] intent in
            self?.handleNavigationIntent(intent, sourcePane: pane)
        }
    }

    @MainActor
    func handleNavigationIntent(_ intent: NavigationIntent, sourcePane: Pane) {
        // Task 16 implements the body. For now: no-op.
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: PASS.

- [ ] **Step 4: Suggested commit**

```bash
git add Sources
git commit -m "feat: split-as-browser plumbing in WorkspaceController"
```

---

### Task 9: Right-click menu — Split submenu + dynamic Convert

**Goal:** Update the pane/tab context menu to match the spec.

**Files:**
- Modify: `Sources/Features/TabBar/WindowTab.swift`
- Modify: `Sources/Features/Sidebar/SidebarTabRow.swift`

- [ ] **Step 1: Update WindowTab context menu**

Find the existing `.contextMenu { ... }` block. Replace split items with submenus:

```swift
.contextMenu {
    Menu("Split pane right") {
        Button("Terminal") { workspace.splitPaneNativePTY(direction: .horizontal, position: .right, as: .terminal) }
        Button("Browser") { workspace.splitPaneNativePTY(direction: .horizontal, position: .right, as: .browser) }
    }
    Menu("Split pane down") {
        Button("Terminal") { workspace.splitPaneNativePTY(direction: .vertical, position: .down, as: .terminal) }
        Button("Browser") { workspace.splitPaneNativePTY(direction: .vertical, position: .down, as: .browser) }
    }
    Menu("Split pane left") { /* mirror */ }
    Menu("Split pane up") { /* mirror */ }

    Divider()

    Button("Rename tab") { appState.startTabRename(tabId: tab.id) }
    Button(convertLabel) { workspace.convertFocusedPane() }

    Divider()

    Button("Close tab", role: .destructive) { workspace.closeTab(tabId: tab.id) }
}
```

`convertLabel` is a computed string:

```swift
private var convertLabel: String {
    guard let focusedPane = workspace.focusedPane(in: tab) else { return "Convert" }
    return focusedPane.kind == .terminal ? "Convert to Browser" : "Convert to Terminal"
}
```

(Adjust `workspace.focusedPane(in:)` to whatever the codebase calls it; might be `workspace.activePaneFor(tab:)`.)

- [ ] **Step 2: Mirror in `SidebarTabRow.swift`**

Same context menu structure on the sidebar tab row.

- [ ] **Step 3: Implement `convertFocusedPane` (stub for now)**

In `WorkspaceController+Actions.swift`:

```swift
@MainActor
func convertFocusedPane() {
    guard let pane = activePane else { return }
    switch pane.kind {
    case .terminal: convertToBrowser(pane: pane)
    case .browser:  convertToTerminal(pane: pane)
    }
}

@MainActor
func convertToBrowser(pane: Pane) {
    // Implemented in Task 10
}
@MainActor
func convertToTerminal(pane: Pane) {
    // Implemented in Task 10
}
```

- [ ] **Step 4: Build + visual smoke test**

```
swift build
make dev
```

Right-click a tab. Verify submenus appear with Terminal / Browser items. Click `Split pane right → Browser` — should create a browser pane (mode None, blank — palette in Task 11).

- [ ] **Step 5: Suggested commit**

```bash
git add Sources/Features/TabBar Sources/Features/Sidebar Sources/WorkspaceController+Actions.swift
git commit -m "feat: context menu — split submenus + dynamic Convert"
```

---

### Task 10: Convert flows (Terminal ↔ Browser)

**Goal:** Implement `convertToBrowser` and `convertToTerminal` with active-process / loaded-URL confirmation.

**Files:**
- Modify: `Sources/WorkspaceController+Actions.swift` (or `+Browser.swift`)

- [ ] **Step 1: Implement `convertToBrowser`**

```swift
@MainActor
func convertToBrowser(pane: Pane) {
    Task {
        let activities = await paneActivity.query(paneIds: [pane.id])
        let isActive = activities.first?.isActive ?? false
        let command = activities.first?.command

        let proceed: Bool
        if isActive {
            proceed = await confirmConvert(
                message: "Converting this pane to a browser will terminate “\(command ?? "the running process")”.",
                destructiveLabel: "Convert to Browser"
            )
        } else {
            proceed = true
        }

        guard proceed else { return }
        await doConvertToBrowser(pane: pane)
    }
}

@MainActor
private func doConvertToBrowser(pane: Pane) async {
    // Tear down terminal
    if let renderer = paneRenderers[pane.id] as? GhosttyRenderer {
        renderer.dispose()   // closes PTY fd
        paneRenderers.removeValue(forKey: pane.id)
    }
    await daemon.release(paneId: pane.id)

    // Swap content
    pane.content = .browser(BrowserState())

    // Create browser renderer
    let r = WebKitBrowserRenderer()
    wireBrowserCallbacks(renderer: r, pane: pane)
    paneRenderers[pane.id] = r

    // Auto-open URL palette (Task 11)
    appState.openURLPalette(for: pane)

    saveWorkspace()
}
```

- [ ] **Step 2: Implement `convertToTerminal`**

```swift
@MainActor
func convertToTerminal(pane: Pane) {
    Task {
        let hasURL = pane.browserState?.url != nil
        let proceed: Bool
        if hasURL {
            proceed = await confirmConvert(
                message: "Converting this pane to a terminal will discard the current page.",
                destructiveLabel: "Convert to Terminal"
            )
        } else {
            proceed = true
        }
        guard proceed else { return }

        if let renderer = paneRenderers[pane.id] {
            paneRenderers.removeValue(forKey: pane.id)
            // WKWebView deinit handles cleanup
            _ = renderer
        }

        pane.content = .terminal(TerminalState())

        let cwd = pane.terminalState?.currentPath ?? activeProject?.path ?? NSHomeDirectory()
        let renderer = GhosttyRenderer(ghosttyApp: ghosttyApp, cwd: cwd)
        paneRenderers[pane.id] = renderer
        scheduleDaemonRegister(paneId: pane.id, cwd: cwd)

        saveWorkspace()
    }
}
```

- [ ] **Step 3: Implement `confirmConvert` helper**

Mirror the existing close-confirmation helper. Use `NSAlert.beginSheetModal(for: window)` with Cancel as the default button and the destructive button with `hasDestructiveAction = true`.

```swift
@MainActor
private func confirmConvert(message: String, destructiveLabel: String) async -> Bool {
    await withCheckedContinuation { cont in
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        let cancel = alert.addButton(withTitle: "Cancel")
        let confirm = alert.addButton(withTitle: destructiveLabel)
        cancel.keyEquivalent = "\r"   // Enter cancels
        confirm.hasDestructiveAction = true
        guard let window = NSApp.keyWindow else { cont.resume(returning: false); return }
        alert.beginSheetModal(for: window) { response in
            cont.resume(returning: response == .alertSecondButtonReturn)
        }
    }
}
```

- [ ] **Step 4: Smoke test**

```
make dev
```

Right-click pane → `Convert to Browser`. Verify alert appears with correct wording. Cancel works. Confirm converts. Reverse with `Convert to Terminal`.

- [ ] **Step 5: Suggested commit**

```bash
git add Sources
git commit -m "feat: bidirectional convert (terminal ↔ browser) with HIG confirmations"
```

---

### Task 11: URL Palette + port suggestions

**Goal:** Centered floating sheet on a browser pane. Empty input + port suggestions from sibling panes. ⌘L opens, Esc cancels.

**Files:**
- Create: `Sources/Features/Browser/BrowserURLPalette.swift`
- Modify: `Sources/Features/Shared/AppState.swift` — add `urlPalettePane: Pane?` state
- Modify: `Sources/Features/Browser/BrowserPaneView.swift` — overlay palette

- [ ] **Step 1: Add palette state to `AppState`**

```swift
public var urlPalettePane: Pane? = nil

@MainActor
public func openURLPalette(for pane: Pane) { urlPalettePane = pane }
@MainActor
public func closeURLPalette() { urlPalettePane = nil }
```

- [ ] **Step 2: Implement `BrowserURLPalette`**

```swift
struct BrowserURLPalette: View {
    let pane: Pane
    let suggestions: [DetectedPort]
    @State private var input: String = ""
    @State private var highlighted: Int = -1
    let onSubmit: (URL) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("URL or search", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .onSubmit { submit() }
            if !suggestions.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { i, port in
                        suggestionRow(port: port, isHighlighted: i == highlighted)
                            .onTapGesture { onSubmit(url(for: port)) }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
    }

    private func suggestionRow(port: DetectedPort, isHighlighted: Bool) -> some View {
        HStack {
            Text("\(port.host):\(port.port)")
                .font(.system(size: 12, design: .monospaced))
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(isHighlighted ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
    }

    private func url(for port: DetectedPort) -> URL {
        URL(string: "http://\(port.host):\(port.port)")!
    }

    private func submit() {
        if highlighted >= 0 && highlighted < suggestions.count {
            onSubmit(url(for: suggestions[highlighted]))
        } else if let parsed = parseInput(input) {
            onSubmit(parsed)
        }
    }

    private func parseInput(_ s: String) -> URL? {
        if let u = URL(string: s), u.scheme != nil { return u }
        if let u = URL(string: "https://\(s)"), u.host != nil { return u }
        return URL(string: "https://duckduckgo.com/?q=\(s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s)")
    }
}
```

- [ ] **Step 3: Compute suggestions from sibling panes**

In `WorkspaceController` add:

```swift
@MainActor
func detectedPortsForTab(_ tab: Tab) -> [DetectedPort] {
    var combined = ""
    for pane in tab.panes where pane.kind == .terminal {
        combined += outputScrollback[pane.id] ?? ""
        combined += "\n"
    }
    return PortDetector.detect(in: combined)
}
```

(Find or wire up `outputScrollback` — the `OutputRouter` already buffers output per pane per CLAUDE.md memory. If not exposed, expose a getter.)

- [ ] **Step 4: Overlay the palette in `BrowserPaneView`**

```swift
struct BrowserPaneView: View {
    @Environment(AppState.self) private var appState
    @Environment(WorkspaceController.self) private var workspace
    let pane: Pane
    let renderer: any BrowserRenderer

    var body: some View {
        ZStack {
            // chrome dispatch (Task 14) — for now mode None
            BrowserChromeNone(renderer: renderer)

            if appState.urlPalettePane?.id == pane.id, let tab = workspace.tab(for: pane) {
                BrowserURLPalette(
                    pane: pane,
                    suggestions: workspace.detectedPortsForTab(tab),
                    onSubmit: { url in
                        renderer.loadURL(url)
                        appState.closeURLPalette()
                    },
                    onCancel: { appState.closeURLPalette() }
                )
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
    }
}
```

- [ ] **Step 5: ⌘L keybinding**

Add to `Sources/Infrastructure/Config/KeyboardShortcuts.swift` (or `MenuCommands.swift`):

```swift
.keyboardShortcut("l", modifiers: .command) { 
    if let pane = workspace.activePane, pane.kind == .browser {
        appState.openURLPalette(for: pane)
    }
}
```

- [ ] **Step 6: Visual verification**

```
make dev
```

Split a tab → Browser. Verify palette pops automatically. Type a URL, hit Enter — page loads. ⌘L while focused on a browser pane re-opens palette.

Start `npm run dev` (or any localhost dev server) in a sibling terminal pane. Open palette in browser pane → verify port suggestion appears.

- [ ] **Step 7: Suggested commit**

```bash
git add Sources
git commit -m "feat: URL Palette with sibling-pane port suggestions"
```

---

### Task 12: Settings UI — Browser section

**Goal:** New `Section("Browser")` in `GeneralSettingsPane` with picker + dynamic subtext.

**Files:**
- Modify: `Sources/Infrastructure/Config/ForgeConfig.swift`
- Modify: `Sources/Features/Settings/GeneralSettingsPane.swift`

- [ ] **Step 1: Add config field**

In `ForgeConfig.GeneralSettings`:

```swift
public var browserChromeType: String?   // "full" | "slim" | "none"; default "none"
```

- [ ] **Step 2: Add Section in GeneralSettingsPane**

After the existing `Section("Confirmations")` block:

```swift
Section("Browser") {
    Picker("Browser chrome type", selection: generalBinding(\.browserChromeType, default: "none")) {
        Text("Full").tag("full")
        Text("Slim").tag("slim")
        Text("None").tag("none")
    }
    .padding(.vertical, -4)

    Text(chromeSubtext(for: store.config.general?.browserChromeType ?? "none"))
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.vertical, -4)
}
```

```swift
private func chromeSubtext(for value: String) -> String {
    switch value {
    case "full":
        return "Back, forward, reload buttons and the URL bar are always visible. Most space cost."
    case "slim":
        return "Compact strip showing URL and page title. Use ⌘L to focus URL, ⌘[ ⌘] for back/forward, ⌘R to reload, ⌘F to find in page."
    default:
        return "No persistent chrome. Use ⌘L to enter a URL, ⌘[ ⌘] for back/forward, ⌘R to reload, ⌘F to find in page."
    }
}
```

- [ ] **Step 3: Visual verification**

```
make dev
```

Open Settings → General. Verify Browser section appears below Confirmations. Picker has three options. Subtext changes when selection changes.

- [ ] **Step 4: Suggested commit**

```bash
git add Sources
git commit -m "feat: Settings → General → Browser section with chrome type picker"
```

---

### Task 13: Chrome modes Full and Slim

**Goal:** Implement modes A and B. `BrowserPaneView` dispatches on `configStore.config.general?.browserChromeType`.

**Files:**
- Create: `Sources/Features/Browser/BrowserChromeFull.swift`
- Create: `Sources/Features/Browser/BrowserChromeSlim.swift`
- Modify: `Sources/Features/Browser/BrowserPaneView.swift`

- [ ] **Step 1: Implement `BrowserChromeFull`**

```swift
struct BrowserChromeFull: View {
    let pane: Pane
    let renderer: any BrowserRenderer

    var body: some View {
        VStack(spacing: 0) {
            chromeBar
            BrowserChromeNone(renderer: renderer)
        }
    }

    @ViewBuilder
    private var chromeBar: some View {
        HStack(spacing: 6) {
            IconButton(systemName: "chevron.left") { renderer.goBack() }
                .disabled(!(pane.browserState?.canGoBack ?? false))
            IconButton(systemName: "chevron.right") { renderer.goForward() }
                .disabled(!(pane.browserState?.canGoForward ?? false))
            IconButton(systemName: "arrow.clockwise") { renderer.reload() }
            urlField
            IconButton(systemName: "ellipsis") { /* menu */ }
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(Color.white.opacity(0.06))
        .overlay(progressBar, alignment: .bottom)
    }

    @ViewBuilder
    private var urlField: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.green.opacity(0.7))
            Text(pane.browserState?.url?.absoluteString ?? "")
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1).truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.black.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var progressBar: some View {
        if pane.browserState?.isLoading == true {
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .scaleEffect(x: pane.browserState?.loadingProgress ?? 0, y: 1, anchor: .leading)
        }
    }
}
```

- [ ] **Step 2: Implement `BrowserChromeSlim`**

Same structure with a single-line strip:

```swift
struct BrowserChromeSlim: View {
    let pane: Pane
    let renderer: any BrowserRenderer

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(.green.opacity(0.7))
                Text(pane.browserState?.url?.host() ?? "")
                    .font(.system(size: 10, design: .monospaced))
                if !(pane.browserState?.pageTitle.isEmpty ?? true) {
                    Text("·").foregroundStyle(.secondary)
                    Text(pane.browserState?.pageTitle ?? "")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer()
                IconButton(systemName: "arrow.clockwise") { renderer.reload() }
                IconButton(systemName: "ellipsis") { /* menu */ }
            }
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color.white.opacity(0.04))

            BrowserChromeNone(renderer: renderer)
        }
    }
}
```

- [ ] **Step 3: Dispatch in `BrowserPaneView`**

```swift
struct BrowserPaneView: View {
    @Environment(ForgeConfigStore.self) private var configStore
    let pane: Pane
    let renderer: any BrowserRenderer

    var body: some View {
        ZStack {
            switch configStore.config.general?.browserChromeType ?? "none" {
            case "full": BrowserChromeFull(pane: pane, renderer: renderer)
            case "slim": BrowserChromeSlim(pane: pane, renderer: renderer)
            default:     BrowserChromeNone(renderer: renderer)
            }
            // Palette overlay from Task 11
            paletteOverlay
        }
    }
}
```

- [ ] **Step 4: Visual verification — all three modes**

```
make dev
```

Toggle Settings → Browser chrome type between Full / Slim / None. Verify existing browser panes restyle live. Take a screenshot in each mode via `curl localhost:7654/screenshot > /tmp/forge-screenshot.png` and `Read` to confirm spacing matches the mockups.

- [ ] **Step 5: Suggested commit**

```bash
git add Sources/Features/Browser
git commit -m "feat: browser chrome modes Full and Slim"
```

---

### Task 14: Navigation intents

**Goal:** Implement the `handleNavigationIntent` stub from Task 8.

**Files:**
- Modify: `Sources/WorkspaceController+Browser.swift`
- Create: `Sources/Infrastructure/Browser/BrowserPopupWindow.swift`

- [ ] **Step 1: Implement `handleNavigationIntent`**

```swift
@MainActor
func handleNavigationIntent(_ intent: NavigationIntent, sourcePane: Pane) {
    switch intent {
    case .sameTabBlank(let url):
        (paneRenderers[sourcePane.id] as? any BrowserRenderer)?.loadURL(url)
    case .modifierNewPane(let url):
        splitPaneNativePTY(direction: .horizontal, position: .right, as: .browser)
        // Find the just-created pane and load URL
        if let newPane = activeTab?.panes.last, newPane.kind == .browser,
           let r = paneRenderers[newPane.id] as? any BrowserRenderer {
            r.loadURL(url)
            appState.closeURLPalette()   // don't auto-pop palette for cmd+click flow
        }
    case .popupWindow(let url, let size):
        let popup = BrowserPopupWindow(url: url, size: size ?? NSSize(width: 600, height: 700))
        popup.show()
    }
}
```

- [ ] **Step 2: Implement `BrowserPopupWindow`**

```swift
import AppKit
import WebKit

@MainActor
final class BrowserPopupWindow {
    private let panel: NSPanel
    private let webView: WKWebView

    init(url: URL, size: NSSize) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let wv = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: config)
        wv.load(URLRequest(url: url))
        self.webView = wv

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.contentView = wv
        p.title = "Forge"
        p.isFloatingPanel = true
        p.center()
        self.panel = p
        wv.uiDelegate = self
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
        BrowserPopupWindow.active.append(self)
    }

    private static var active: [BrowserPopupWindow] = []
}

extension BrowserPopupWindow: WKUIDelegate {
    func webViewDidClose(_ webView: WKWebView) {
        panel.close()
        BrowserPopupWindow.active.removeAll { $0 === self }
    }
}
```

- [ ] **Step 3: Manual verification**

In a browser pane, navigate to a page with `target="_blank"` links (e.g. github.com README). Click a link — should navigate in same pane. ⌘+click — should split right with that URL. Trigger an OAuth flow (e.g. github sign-in) — should open in floating window.

- [ ] **Step 4: Suggested commit**

```bash
git add Sources
git commit -m "feat: navigation intents (same pane / new pane / floating popup)"
```

---

### Task 15: Find in page (⌘F)

**Goal:** ⌘F shows a find bar overlay on the browser pane.

**Files:**
- Create: `Sources/Features/Browser/BrowserFindBar.swift`
- Modify: `Sources/Features/Browser/BrowserPaneView.swift`
- Modify: `Sources/Features/Shared/AppState.swift` (`findActiveForPane: String?`)

- [ ] **Step 1: Add find state to AppState**

```swift
public var findActivePane: String? = nil   // pane id
```

- [ ] **Step 2: Implement `BrowserFindBar`**

A horizontal HStack overlaid at the top of the pane. Text field for query, count display (`3 of 12`), prev/next buttons, close button. `onChange(of: query)` calls `renderer.find(query)`. Esc dismisses.

(Implementation similar to URL palette; ~60 lines. Full code omitted — follow the palette pattern.)

- [ ] **Step 3: Wire ⌘F**

```swift
.keyboardShortcut("f", modifiers: .command) {
    if let pane = workspace.activePane, pane.kind == .browser {
        appState.findActivePane = pane.id
    }
}
```

- [ ] **Step 4: Manual verification**

⌘F on a browser pane → bar appears. Type query → highlights appear. Enter advances. Esc closes.

- [ ] **Step 5: Suggested commit**

```bash
git add Sources
git commit -m "feat: find in page (⌘F) for browser panes"
```

---

### Task 16: DevTools (⌘⌥I)

**Goal:** Toggle WKWebView's built-in inspector.

**Files:**
- Modify: app-level keyboard shortcuts (existing menu commands or NSEvent monitor)

- [ ] **Step 1: Wire shortcut**

```swift
.keyboardShortcut("i", modifiers: [.command, .option]) {
    if let pane = workspace.activePane, pane.kind == .browser,
       let r = workspace.paneRenderers[pane.id] as? any BrowserRenderer {
        r.toggleDevTools()
    }
}
```

- [ ] **Step 2: Verify**

⌘⌥I on a browser pane → inspector window appears. Again → hides.

- [ ] **Step 3: Suggested commit**

```bash
git add Sources
git commit -m "feat: DevTools toggle (⌘⌥I) for browser panes"
```

---

### Task 17: Persistence — `workspace.json` migration

**Goal:** Save and restore browser panes via `workspace.json`. Existing terminal-only workspaces upgrade silently.

**Files:**
- Modify: whichever file currently encodes Pane to JSON. Find via `grep -rn "JSONEncoder\|workspace.json\|encode(_:" Sources/Infrastructure/Config/ Sources/`

- [ ] **Step 1: Update Pane codec**

When encoding, write:

```json
{
  "id": "...",
  "tabId": "...",
  "index": 0,
  "active": true,
  "content": {
    "kind": "terminal"
  }
}
```

Or for browser:

```json
{
  "content": {
    "kind": "browser",
    "url": "https://localhost:3000"
  }
}
```

Decoding: if `content` field missing, default to `{ "kind": "terminal" }`. This is the silent migration.

- [ ] **Step 2: On startup, restore browser panes**

In `connectNativePTY()` or equivalent — when iterating saved panes:

```swift
switch savedPane.content.kind {
case .terminal:
    // existing path: spawn shell, create GhosttyRenderer
case .browser:
    let pane = Pane.browser(id: savedPane.id, tabId: savedPane.tabId, url: savedPane.content.url)
    let r = WebKitBrowserRenderer()
    wireBrowserCallbacks(renderer: r, pane: pane)
    paneRenderers[pane.id] = r
    if let url = savedPane.content.url { r.loadURL(url) }
}
```

- [ ] **Step 3: Auto-save on URL change**

In `wireBrowserCallbacks`, after updating `pane.browserState?.url`, debounce a `saveWorkspace()` call (1s).

- [ ] **Step 4: Verification**

Open a browser pane, load a URL, quit Forge, relaunch. Verify the pane comes back with the same URL.

- [ ] **Step 5: Suggested commit**

```bash
git add Sources
git commit -m "feat: persist browser pane URLs in workspace.json with silent migration"
```

---

## Acceptance Criteria

The feature is done when, with `nativePTY: true`:

1. Right-click a tab → submenu shows `Split pane right ▸ Terminal / Browser` etc.
2. Selecting `Browser` from a submenu creates a new browser pane with the URL palette auto-open.
3. URL palette shows localhost-port suggestions from sibling terminal panes' recent output.
4. Settings → General → Browser → Browser chrome type picker has three options (Full, Slim, None) with default None. Subtext explains keyboard shortcuts for Slim and None.
5. `Convert to Browser` on a terminal pane with an active process shows a HIG-compliant alert; on confirm, terminates the process and converts.
6. `Convert to Terminal` on a browser pane with a loaded URL shows a confirmation; on confirm, opens a fresh shell.
7. Pages with `target="_blank"` navigate in the same pane. `window.open()` with size hints opens a floating Forge window. ⌘+click on a link splits right.
8. ⌘L opens the URL palette (or focuses the URL bar in Full/Slim). ⌘R reloads. ⌘[ ⌘] navigate. ⌘F finds. ⌘⌥I toggles DevTools.
9. Quitting Forge and relaunching restores browser panes with their last URL.
10. Existing tmux-mode workspaces never see browser panes; nothing in the menu offers them.

## Verification Commands

After each task that ships UI, run:

```bash
swift build                                                  # must succeed
swift test                                                   # must pass
make dev                                                     # launch app
curl localhost:7654/screenshot > /tmp/forge-screenshot.png   # screenshot
# then Read /tmp/forge-screenshot.png to confirm visuals
tail -20 /tmp/forge.log                                      # check for errors
```

## Out of Scope (do not implement)

See spec § *Out of Scope (v1)*. In short: bookmarks/history UI, per-project profiles, auto-reload on file change, multi-URL panes, search-engine choice, browser extensions, print/save-as, custom User-Agent.
