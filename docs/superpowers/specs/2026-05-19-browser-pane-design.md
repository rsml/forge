# Browser Panes

A Forge pane can hold a WebKit browser instead of a terminal. Browser is a first-class pane content-type — splits, focus, persistence, the split tree, and the existing pane container all work unchanged. Targeted at developers who want a localhost-preview pane next to their dev server without leaving the workspace.

## Scope

- Native PTY only (`nativePTY: true`). Browser panes are not exposed in tmux mode. No `config.isNativePTY` guard sprinkled through the new code — the new code simply assumes native PTY is the world.
- One URL per pane. No browser-tabs-inside-a-pane abstraction; use Forge's existing tab/pane primitives for "multiple things at once."
- macOS only. Engine is `WKWebView` (system WebKit, GPU-accelerated, free DevTools).

## Domain Model

Today `Pane` carries ~11 terminal-specific fields. They get extracted into a `TerminalState` reference type and a parallel `BrowserState` is added. `Pane.content` becomes the canonical tagged union.

```swift
// Sources/Core/Models/Pane.swift

@Observable @MainActor
public final class TerminalState {
    public var currentCommand: String = ""
    public var currentPath: String = ""
    public var width: Int = 80
    public var height: Int = 24
    public var pid: Int = 0
    public var status: PaneStatus = .idle
    public var hasBell: Bool = false
    public var hasContentMatch: Bool = false
    public var previousCommand: String = ""

    public var needsAttention: Bool {
        status == .idle || hasBell || hasContentMatch || status == .needsAttention || status == .error
    }
}

@Observable @MainActor
public final class BrowserState {
    public var url: URL? = nil
    public var pageTitle: String = ""
    public var canGoBack: Bool = false
    public var canGoForward: Bool = false
    public var isLoading: Bool = false
    public var loadingProgress: Double = 0.0
    public var favicon: NSImage? = nil
}

public enum PaneContent {
    case terminal(TerminalState)
    case browser(BrowserState)
}

@Observable @MainActor
public final class Pane: Identifiable {
    public let id: String
    public let tabId: String
    public var index: Int
    public var active: Bool
    public var content: PaneContent

    // Convenience accessors — keep callsites free of `if case let`.
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
        terminalState?.needsAttention ?? false   // browser panes never need attention
    }
}

public enum PaneKind: String, Sendable, Codable { case terminal, browser }
```

Reference semantics on the sub-states: `pane.terminalState?.currentCommand = "vim"` propagates through `@Observable` without reassigning `pane.content`. The enum is a discriminator; the data lives in the referenced class.

Migration: existing callsites accessing `pane.currentCommand` etc. become `pane.terminalState?.currentCommand`. Mechanical refactor; the compiler enforces completeness.

## Renderer Architecture

Hoist a parent `PaneRenderer` protocol. `TerminalRenderer` refines it for terminal-specific concerns; new `BrowserRenderer` refines it for browser-specific concerns. Single `paneRenderers: [String: any PaneRenderer]` dictionary keeps lifecycle bookkeeping uniform.

```swift
// Sources/Infrastructure/PaneRenderer.swift
@MainActor
protocol PaneRenderer: AnyObject {
    var view: NSView { get }
    func setFocused(_ focused: Bool)
}

// Sources/Infrastructure/Terminal/TerminalRenderer.swift  (existing, now refines PaneRenderer)
@MainActor
protocol TerminalRenderer: PaneRenderer {
    func feed(_ data: Data)
    func feedScrollback(_ content: String)
    var onInput: ((Data) -> Void)? { get set }
    var onResize: ((Int, Int) -> Void)? { get set }
}

// Sources/Infrastructure/Browser/BrowserRenderer.swift  (new)
@MainActor
protocol BrowserRenderer: PaneRenderer {
    var url: URL? { get }
    func loadURL(_ url: URL)
    func goBack()
    func goForward()
    func reload()
    func find(_ query: String)
    func toggleDevTools()

    var onURLChange: ((URL) -> Void)? { get set }
    var onTitleChange: ((String) -> Void)? { get set }
    var onLoadProgress: ((Bool, Double) -> Void)? { get set }   // (isLoading, progress)
    var onFaviconChange: ((NSImage?) -> Void)? { get set }
    var onNavigationRequest: ((NavigationIntent) -> Void)? { get set }
}

enum NavigationIntent {
    case sameTabBlank(URL)          // target=_blank with no size hints — same pane
    case popupWindow(URL, size: NSSize?)  // window.open() with size — floating mini-window
    case modifierNewPane(URL)       // cmd+click — split right as new browser pane
}
```

`WebKitBrowserRenderer` is the only adapter. It owns one `WKWebView` plus KVO observers that fire the `on*` callbacks. Lives in `Sources/Infrastructure/Browser/WebKitBrowserRenderer.swift`.

`paneRenderers` type changes from `[String: any TerminalRenderer]` to `[String: any PaneRenderer]`. Callsites that need terminal-specific operations downcast (`as? TerminalRenderer` / `as? GhosttyRenderer`) — same pattern that already exists for `as? GhosttyRenderer`.

## Pane Creation Flows

### Split as Browser

User picks **Split pane right ▸ Browser** (or down/left/up).

1. `WorkspaceController.splitPaneNativePTY(direction:as: .browser)` clones the focused leaf in `SplitNode`, allocates a new `Pane.id`.
2. New `Pane` constructed with `content = .browser(BrowserState())`.
3. `WebKitBrowserRenderer` instantiated synchronously and inserted into `paneRenderers[pane.id]` *before* the model update (matches existing pattern: rule #12 — avoid SwiftUI rendering a frame with no renderer).
4. After the split lays out, the URL palette auto-opens on the new pane (see *URL Palette* below).
5. Persisted to `workspace.json` immediately (URL is `nil` until user enters one).

### Convert to Browser (terminal → browser)

User right-clicks a terminal pane → **Convert to Browser**.

1. Query `PaneActivityPort.query([pane.id])` (already exists, used by close-confirmation).
2. If `isActive == true`: present `NSAlert` sheet, HIG-style — *"Converting this pane to a browser will terminate **\<command\>**."* Default button: Cancel. Destructive button: Convert. (Reuses the exact pattern from `Active-Process Close Confirmation` spec.)
3. On confirm: close PTY fd via daemon `release` op. Tear down `GhosttyRenderer`, remove from `paneRenderers`.
4. `pane.content = .browser(BrowserState())`. `WebKitBrowserRenderer` created, inserted into `paneRenderers[pane.id]`. `pane.id` is unchanged — only content + renderer swapped.
5. URL palette auto-opens (same flow as Split as Browser).

### Convert to Terminal (browser → terminal)

User right-clicks a browser pane → **Convert to Terminal**.

1. If `pane.browserState?.url != nil`: present `NSAlert` sheet — *"Converting this pane to a terminal will discard the current page."* Default: Cancel. Destructive: Convert.
2. On confirm: WKWebView destroyed, `BrowserRenderer` removed from `paneRenderers`.
3. `pane.content = .terminal(TerminalState())`. A fresh shell is spawned in `pane`'s cwd (defaults to project root) — identical to a new terminal pane.
4. `GhosttyRenderer` (EXEC mode) created and inserted into `paneRenderers[pane.id]`. Daemon `store` op registers the new pid.

## Right-Click Context Menu

```
Split pane right  ▸ Terminal
                  ▸ Browser
Split pane down   ▸ Terminal
                  ▸ Browser
Split pane left   ▸ Terminal
                  ▸ Browser
Split pane up     ▸ Terminal
                  ▸ Browser
─────────────────
Rename tab
Convert to Browser              ← or "Convert to Terminal" depending on current pane
─────────────────
Close tab
```

- Top-level click on `Split pane <direction>` defaults to Terminal. Drill-down required for Browser.
- `Convert to Browser/Terminal` is dynamic based on `pane.kind`.
- Confirmation alerts only fire when there's something to lose (active terminal process, or loaded URL).

## Chrome Modes

User-selectable via `Settings → General → Browser → Browser chrome type`. Default: **None**. Stored as `ForgeConfig.GeneralSettings.browserChromeType: String?` with values `"full" | "slim" | "none"`.

Mode changes live-update — existing browser panes restyle on config change (panes observe `configStore.config.general?.browserChromeType`).

### Full

Persistent 28px chrome strip at top of pane:

`[ ← ] [ → ] [ ⟳ ]  [ 🔒 https://localhost:3000 ─────────── ]  [ ⋯ ]`

- Buttons styled as Forge `IconButton` (hover: secondary → primary, with tooltip + shortcut hint).
- URL bar is a `TextField` with `border-radius: 12px`, focusable on ⌘L.
- 1px progress bar at the top edge of the URL field during load.

### Slim

Single 18px strip at top: lock icon, URL, separator dot, page title, right-aligned reload + menu glyphs:

`🔒 localhost:3000 · Dashboard · Acme                              ⟳  ⋯`

- No back/forward buttons. Use ⌘[ / ⌘]. Reload glyph is a tap target.
- Click URL or ⌘L → field expands inline to editable for the duration of editing.
- Progress bar appears as 1px line below the strip during load.

### None

No persistent chrome. The pane is pure content.

- ⌘L opens a centered **URL Palette** (see below).
- A tiny `🔒 localhost:3000` floating pill appears in the top-left corner on hover or focus, dismisses after 1.5s of inactivity. Provides a "where am I" affordance without permanent chrome.

## URL Palette

The URL palette is the canonical URL-input affordance for all chrome modes. Opens via:
- Automatically when a new browser pane is created (split or convert).
- ⌘L when focused on a browser pane (any chrome mode).

Layout: centered floating sheet, 480px wide, attached to the pane's view (sheet position inside the pane, not window).

```
┌──────────────────────────────────────────────────┐
│  [ URL or search                                ] │
│                                                   │
│  Suggestions                                      │
│  ─────────────────                                │
│  localhost:3000      from `npm run dev` in 'web' │
│  localhost:5173      from `vite` in 'site'       │
│  localhost:8080      from `python -m http.server'│
└──────────────────────────────────────────────────┘
```

### Port suggestions

A new pure-Core helper scans sibling panes (same Tab) for localhost-port patterns in recent output:

```swift
// Sources/Core/PortDetector.swift
public enum PortDetector {
    /// Returns detected `host:port` URLs in the order they appear, deduplicated.
    public static func detect(in scrollback: String) -> [DetectedPort] { ... }
}

public struct DetectedPort: Hashable, Sendable {
    public let host: String   // "localhost" | "127.0.0.1" | "0.0.0.0"
    public let port: Int
    public let sourceCommand: String?   // e.g. "npm run dev"
    public let sourcePaneName: String?  // e.g. tab name or pane index
}
```

Regex (rough): `\b(localhost|127\.0\.0\.1|0\.0\.0\.0):\d{2,5}\b` plus `\b:\d{4,5}\b` when preceded by typical dev-server output words ("ready", "running", "listening", "started", "Local:").

Source: the `outputScrollback` already retained by `WorkspaceController` rendering (see CLAUDE.md — `OutputRouter` keeps scrollback buffers). New port-detection scan runs once when the palette opens, not continuously.

### Palette behavior

- Input is empty by default; suggestions list rendered below.
- ↑/↓ to navigate suggestions; Enter to load. Typing filters suggestions and replaces the URL value.
- Free-form input: `Enter` triggers `URL(string:)`; if invalid, attempts `https://<input>`; if still invalid, defaults to a search URL (DuckDuckGo or system default; see *Out of scope*).
- Esc cancels; if the pane has no current URL, the pane remains blank.

## Navigation Intents

WKWebView triggers `WKUIDelegate.webView(_:createWebViewWith:for:windowFeatures:)` and `WKNavigationDelegate.decidePolicyFor:` events. `WebKitBrowserRenderer` translates them into `NavigationIntent`s and emits via `onNavigationRequest`. The renderer's owner (typically `BrowserPaneController` or `WorkspaceController` extension) executes the intent.

| Trigger | Intent | Action |
|---|---|---|
| `target="_blank"` link, no window features | `.sameTabBlank(url)` | Replace current pane URL. |
| `window.open(url, "_blank", "width=600,height=700,...")` | `.popupWindow(url, size)` | Open a floating Forge-owned `NSPanel` with a `WKWebView`, sized per features. OAuth flows work. Auto-closes when JS calls `window.close()`. |
| ⌘+click on any link | `.modifierNewPane(url)` | `WorkspaceController` splits right with a new browser pane preloaded to `url`. |
| Plain link click | (no intent) | Standard same-pane navigation. |

⌘+click detection: `NSEvent.modifierFlags.contains(.command)` checked in `WKNavigationDelegate.decidePolicyFor:` — if cmd is held and the request is link-activation, cancel the policy and emit `.modifierNewPane`.

## Find in Page (⌘F)

Native WKWebView search. Shown as a 32px-tall floating bar attached to the top of the pane (overlays content, doesn't push it down):

`[ Find: query ____________ ]  3 of 12   [ ↑ ] [ ↓ ]   [ × ]`

- ⌘F focuses field. ⌘G / Enter for next. ⌘⇧G / Shift+Enter for prev. Esc closes.
- Implemented via `WKWebView.find(_:configuration:)` and `WKFindResult`.

## DevTools (⌘⌥I)

`WKWebView` ships a built-in Web Inspector. Enabled with `webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")` and toggled with `_inspector.show()`/`hide()` (private API, but well-known and stable). Floating window. Persistent across pane re-focus.

Acceptable risk: private API may break in future WebKit releases. Cmux uses the same approach.

## Cookies / Storage / Profile

One shared `WKWebsiteDataStore.default()` for the entire app. Persistent. Cookies, localStorage, IndexedDB shared across all browser panes — sign in once, available everywhere.

User-Agent: stock WKWebView (matches Safari on this macOS version). No custom UA string.

Per-project profiles are explicitly out of scope for v1. Future enhancement would add a `WKWebsiteDataStore(forIdentifier:)` keyed on project id.

## Background Pane Behavior

Browser panes are **never destroyed** while their `Pane` exists. Hidden panes (project switch, tab switch) keep their `WKWebView` alive, just like terminal renderers (CLAUDE.md rule #4). 

- Audio: when a pane is not in the active tab/project, `wkWebView.setMuted(true)`. Re-muted on visibility change.
- No occlusion API calls (`setOccluded:` was destructive for Ghostty surfaces; same conservative posture for WKWebView).
- No memory-budget killing in v1. If memory becomes an issue, a future setting can opt-in to "unload pages after N minutes of inactivity."

## Focus & Keyboard

- WKWebView owns keystrokes when focused — same as a Ghostty terminal view.
- Forge-level shortcuts (⌘W close pane, ⌘T new tab, ⌘1-9 project switch, etc.) are intercepted at the app's `NSEvent` local monitor before reaching the WKWebView, identical to how terminal panes already work.
- Browser-pane-only shortcuts handled in the browser-pane view's key handler when focused:
  - ⌘L → open URL palette (chrome modes Full/Slim: focus URL field; mode None: centered palette)
  - ⌘R → reload
  - ⌘[ → back
  - ⌘] → forward
  - ⌘F → find in page
  - ⌘⌥I → toggle DevTools
- All browser shortcuts are user-customizable via the existing `KeyboardShortcuts` infrastructure (`Sources/Infrastructure/Config/KeyboardShortcuts.swift`).

## Persistence

`workspace.json` per-pane block gains a `content` field:

```json
{
  "id": "pane-abc-123",
  "tabId": "tab-xyz-789",
  "index": 0,
  "active": true,
  "content": {
    "kind": "browser",
    "url": "https://localhost:3000/dashboard"
  }
}
```

For terminal panes:

```json
{
  "content": {
    "kind": "terminal"
  }
}
```

Migration: a missing `content` field defaults to `{ "kind": "terminal" }` — existing workspaces upgrade silently.

Persisted: URL only. Not persisted: scroll position, form state, history stack, devtools state. Reload restores the page by calling `loadURL(savedURL)`; users implicitly accept that scroll/forms reset, matching how every browser handles "kill the process."

## Settings UI

New section in `GeneralSettingsPane`, placed below the existing **Confirmations** section:

```swift
Section("Browser") {
    Picker("Browser chrome type", selection: generalBinding(\.browserChromeType, default: "none")) {
        Text("Full").tag("full")
        Text("Slim").tag("slim")
        Text("None").tag("none")
    }
    .padding(.vertical, -4)

    // Dynamic subtext driven by selected value.
    Text(chromeSubtext(for: store.config.general?.browserChromeType ?? "none"))
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.vertical, -4)
}
```

Subtext (HIG-style — explains consequences, not just labels):

| Selection | Subtext |
|---|---|
| Full | *Back, forward, reload buttons and the URL bar are always visible. Most space cost.* |
| Slim | *Compact strip showing URL and page title. Use ⌘L to focus URL, ⌘[ ⌘] for back/forward, ⌘R to reload, ⌘F to find in page.* |
| None | *No persistent chrome. Use ⌘L to enter a URL, ⌘[ ⌘] for back/forward, ⌘R to reload, ⌘F to find in page.* |

Dropdown labels themselves can append a parenthetical hint without crowding:

- **Full** (back, forward, reload + URL)
- **Slim** (URL + title only)
- **None** (keyboard shortcuts only)

## Config Schema Additions

```swift
// Sources/Infrastructure/Config/ForgeConfig.swift
extension ForgeConfig.GeneralSettings {
    public var browserChromeType: String?   // "full" | "slim" | "none" (default "none")
}
```

Default value handled in the binding (`default: "none"`), same pattern as existing settings.

## File Structure

```
Sources/
  Core/
    Models/
      Pane.swift                  # gains PaneContent enum, accessors, sub-state classes
    PortDetector.swift            # NEW — pure regex scan for dev-server ports

  Infrastructure/
    PaneRenderer.swift            # NEW — parent protocol
    Terminal/
      TerminalRenderer.swift      # refined to extend PaneRenderer
    Browser/                      # NEW directory
      BrowserRenderer.swift       # protocol
      WebKitBrowserRenderer.swift # WKWebView adapter
      BrowserPopupWindow.swift    # floating NSPanel for window.open()
      NavigationIntent.swift      # enum

  Features/
    Browser/                      # NEW feature folder
      BrowserPaneView.swift       # SwiftUI host
      BrowserChromeFull.swift     # mode A view
      BrowserChromeSlim.swift     # mode B view
      BrowserChromeNone.swift     # mode C view (the floating pill)
      BrowserURLPalette.swift     # centered URL input + suggestions
      BrowserFindBar.swift        # ⌘F bar
    Settings/
      GeneralSettingsPane.swift   # adds Section("Browser")
    TabBar/
      WindowTab.swift             # context menu spec extended (split→Terminal/Browser submenu, dynamic Convert)
    Sidebar/
      SidebarTabRow.swift         # context menu spec extended (mirror)
```

Each chrome-mode view is its own file to keep them under the 300-line limit and surgically swappable. The active mode is selected at the `BrowserPaneView` level based on `configStore.config.general?.browserChromeType`.

## Testing Strategy

Following Forge's testing pattern (`ForgeTests` SPM target, Swift Testing `@Test`/`#expect`):

- **Pure Core**: `PortDetector` is fully tested with input/output pairs covering `npm run dev`, `vite`, `python -m http.server`, false positives (timestamps like `12:34:56`), deduplication.
- **Pure Core**: `PaneContent` migration / encoding tests — JSON in, JSON out.
- **Integration**: a Pane-creation pipeline test that exercises Split-as-Browser without WKWebView (using a fake `BrowserRenderer` conforming to the protocol). Verifies `paneRenderers` lifecycle and URL palette trigger.
- **Visual verification**: the existing debug server (`localhost:7654/screenshot`) is used to manually verify each chrome mode and the URL palette layout against the mockups.

No tests for WKWebView itself — we trust Apple's implementation. The seam is the protocol; we test the contract.

## Out of Scope (v1)

Explicitly deferred to future versions:

- **Bookmarks / history UI.** Sidebar list of bookmarks, recently-visited pages.
- **Per-project profiles.** Isolated cookies/storage per project.
- **Reader mode / mute-by-default for unfocused tabs (audio toggle).**
- **Browser extensions** — neither Safari Web Extensions nor anything Chrome-style. WKWebView's extension support is limited and adds significant API surface.
- **Custom User-Agent string** per pane.
- **Auto-reload on file change in sibling terminal.** "When `npm run dev` recompiles, reload the browser pane." Tempting but adds a sibling-pane communication channel; v2.
- **Multi-URL panes / browser tabs inside a pane.** Use Forge's existing split/tab primitives.
- **Search engine choice in the URL palette.** v1: fallback to DuckDuckGo for free-form input that doesn't parse as a URL. User-configurable engine is v2.
- **Print, screenshot of page, save-as.** Not relevant to dev-preview workflow.
- **Tmux-mode support.** Native PTY only; tmux mode never gets browser panes.

## Risk & Open Concerns

- **Private DevTools API**: `_inspector.show()` is private. Cmux uses it without issues; risk is moderate. If it breaks in a future macOS, fall back to "right-click → Inspect Element" (the only public escape hatch in WKWebView).
- **Cookies shared across all panes**: a user logged into work GitHub in one pane is also logged in in another pane in another project. Acceptable for v1; per-project profile in v2.
- **WKWebView memory footprint**: each pane ~ 100-200 MB resident under load. With 5+ browser panes, this is real. v1 ships without mitigation; if reported, opt-in unload-after-N-minutes setting in v2.
- **Domain refactor blast radius**: extracting `TerminalState` touches every existing reader of terminal-specific Pane fields. Compiler-enforced refactor, but the diff is large. Plan it as its own PR or first step of the implementation.

## Implementation Order

1. Domain model refactor: introduce `PaneContent`, `TerminalState`, `BrowserState`. Mechanical refactor of all `pane.currentCommand` etc. callsites. Tests pass.
2. Hoist `PaneRenderer` protocol. `TerminalRenderer` refines it. `paneRenderers` retypes to `[String: any PaneRenderer]`. No new behavior yet.
3. `PortDetector` (pure Core, fully tested).
4. `WebKitBrowserRenderer` adapter + `BrowserRenderer` protocol.
5. `BrowserPaneView` skeleton with chrome mode "None" only. Hard-coded URL load to verify rendering.
6. Right-click menu wiring for Split-as-Browser. Convert-to-Browser/Terminal flows.
7. URL Palette UI + port suggestions.
8. Settings UI: chrome type picker.
9. Chrome modes Full and Slim.
10. Navigation intents (target=_blank, window.open(), ⌘+click). Floating popup window.
11. Find in page + DevTools wiring.
12. Persistence migration in `workspace.json`.

Each step ships independently, with a working app at the end of each.
