# In-House Theme System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Forge own its theme catalog end-to-end. Bundle a curated set of ~30 themes inside the .app, drop the Ghostty-app filesystem fallback, fix the live-reapply bug, watch the user override directory, and add hover-to-preview in the settings picker.

**Architecture:** Stay Ghostty-format-compatible (`background=`, `foreground=`, `palette=N=#RRGGBB`, `cursor-color=`). Themes are imported from `mbadolato/iTerm2-Color-Schemes` via a re-runnable script pinned to a commit, written into `Resources/themes/` with attribution headers, and bundled into the `.app` by the existing Makefile flow. `ThemeParser` searches the bundle resource dir first, then `~/.config/forge/themes/` for user overrides. A `forgeConfigChanged` observer in `AppDelegate` re-applies font + colors to libghostty whenever settings change. A `ThemeWatcher` (`DispatchSource.makeFileSystemObjectSource`) reloads the picker when the user adds/removes files in `~/.config/forge/themes/`. Hover-to-preview applies a transient theme to libghostty without touching `ForgeConfigStore`; mouse-exit reverts to the persisted theme.

**Tech Stack:** Swift 6, SwiftUI, AppKit, libghostty via GhosttyKit.xcframework, Foundation `FileManager` + `DispatchSource`, bash for the import script, `git clone` + pinned commit for theme provenance.

---

## File Structure

**New files:**
- `scripts/curated-themes.txt` — newline-delimited list of theme filenames to import (~30 entries). Lines starting with `#` are comments.
- `scripts/import-themes.sh` — bash. Clones iTerm2-Color-Schemes at pinned commit, copies each curated `.conf` into `Resources/themes/` with a prepended attribution header.
- `Resources/themes/*.conf` — generated; gitignored only if you choose to keep them out of git (we commit them).
- `Sources/Infrastructure/Theme/ThemeWatcher.swift` — `@MainActor` class that wraps `DispatchSource.makeFileSystemObjectSource` on `~/.config/forge/themes/`, posts `.forgeThemesChanged` on writes.
- `docs/adr/0005-ghostty-theme-format-compatibility.md` — ADR locking in the format decision.
- `docs/THEMES.md` — attribution doc crediting `mbadolato/iTerm2-Color-Schemes` plus per-theme authors.

**Modified files:**
- `Sources/Infrastructure/Theme/ThemeParser.swift` — replace `searchPaths` with bundle path + user override path. Drop the Ghostty paths entirely.
- `Sources/ForgeApp.swift` — extract the "build theme args + applyConfig" logic into a private `reapplyGhosttyTheme()` method. Add `.forgeConfigChanged`, `.forgeThemeHoverPreview`, `.forgeThemeHoverEnded` observers that call it. Start `ThemeWatcher`. Add About-pane Acknowledgments link.
- `Sources/Features/Settings/ThemeSettingsPane.swift` — add `@State hoveredThemeId: String?`; observe `.forgeThemesChanged` to reload the catalog; reload picker when watcher fires.
- `Sources/Features/Settings/ThemePreviewCard.swift` — add `.onHover` handler that posts hover notifications.
- `Makefile` — bundle target copies `Resources/themes/` into `.app/Contents/Resources/themes/`.
- `Sources/Features/Settings/AboutPane.swift` — add an "Acknowledgments" disclosure that links to/shows `THEMES.md`.

**Non-changes (intentionally):**
- `ThemeDefinition` / `ThemeColor` stay in `Sources/Infrastructure/Theme/`. Moving them to Core is a refactor outside this plan's scope.
- No new port protocol for theme application; the existing `GhosttyApp.applyConfig` is the seam. Hover preview is driven by notifications, not by a new port.

---

## Task 1: ADR for Ghostty Theme Format Compatibility

**Files:**
- Create: `docs/adr/0005-ghostty-theme-format-compatibility.md`

- [ ] **Step 1: Write the ADR**

Use the same format as `docs/adr/0004-eventual-consistency-for-tmux-commands.md`. Sections: Status (accepted), Date (2026-05-18), Context (terminal cell colors come from libghostty, which has its own config grammar; user themes are sourced from `mbadolato/iTerm2-Color-Schemes`), Decision (Forge themes are Ghostty-format-compatible — `background`, `foreground`, `palette=N=#hex`, `cursor-color`; no extensions for now; revisit if we want selection colors, cursor accent, per-pane overrides, or semantic colors), Consequences (good: portable, zero-conversion imports, users can share themes with Ghostty/iTerm2 users; bad: can't express features Ghostty doesn't support without forking the format later).

- [ ] **Step 2: Commit**

```bash
git add docs/adr/0005-ghostty-theme-format-compatibility.md
git commit -m "docs: ADR 0005 — Ghostty theme format compatibility"
```

---

## Task 2: Curated Theme List + Import Script

**Files:**
- Create: `scripts/curated-themes.txt`
- Create: `scripts/import-themes.sh`
- Create (generated, but committed): `Resources/themes/*.conf`

- [ ] **Step 1: Write the curated theme list**

Create `scripts/curated-themes.txt`. Use one filename per line, no path prefix. Filenames must match files in `mbadolato/iTerm2-Color-Schemes` under `ghostty/`. The list must include `ghostty-seti` (the current default in `ForgeConfig.swift`).

Start with these (verify each exists in the upstream repo before committing — if a name has shifted, fix the entry):

```
# Curated theme catalog. One Ghostty-format theme name per line.
# Source: https://github.com/mbadolato/iTerm2-Color-Schemes/tree/main/ghostty
# Add/remove entries here, then re-run scripts/import-themes.sh.

# Defaults / Forge legacy
ghostty-seti

# Solarized family
Solarized Dark - Patched
Solarized Light

# Dracula
Dracula

# Nord
Nord

# Gruvbox
Gruvbox Dark
Gruvbox Light

# Tokyo Night
Tokyo Night
Tokyo Night Storm
Tokyo Night Light

# Catppuccin
Catppuccin Mocha
Catppuccin Macchiato
Catppuccin Frappe
Catppuccin Latte

# One Dark / One Half
One Dark
One Half Dark
One Half Light

# Rose Pine
Rose Pine
Rose Pine Moon
Rose Pine Dawn

# GitHub
GitHub Dark
GitHub Light

# Monokai
Monokai Pro
Monokai Soda

# Ayu
Ayu
Ayu Mirage
Ayu Light

# Everforest
Everforest Dark - Hard
Everforest Light - Hard

# Misc favorites
Snazzy
Material
```

- [ ] **Step 2: Write the import script**

Create `scripts/import-themes.sh`. It must (a) be re-runnable, (b) fail loudly on missing themes, (c) prepend an attribution header to each output file, (d) be deterministic given a pinned commit.

```bash
#!/usr/bin/env bash
set -euo pipefail

# Pinned commit. Bump this deliberately when you want fresh themes.
PINNED_COMMIT="REPLACE_WITH_ACTUAL_COMMIT_SHA"
REPO_URL="https://github.com/mbadolato/iTerm2-Color-Schemes.git"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$SCRIPT_DIR/../Resources/themes"
CURATED_LIST="$SCRIPT_DIR/curated-themes.txt"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Cloning $REPO_URL at $PINNED_COMMIT..."
git clone --filter=blob:none --no-checkout "$REPO_URL" "$WORK_DIR/repo"
git -C "$WORK_DIR/repo" sparse-checkout init --cone
git -C "$WORK_DIR/repo" sparse-checkout set ghostty
git -C "$WORK_DIR/repo" checkout "$PINNED_COMMIT"

mkdir -p "$DEST_DIR"
# Clean previous imports (only .conf files; preserve any future README).
find "$DEST_DIR" -maxdepth 1 -name '*.conf' -delete 2>/dev/null || true

missing=()
imported=0
while IFS= read -r raw; do
  # Strip comments and trim whitespace
  name="${raw%%#*}"
  name="$(echo "$name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [[ -z "$name" ]] && continue

  src="$WORK_DIR/repo/ghostty/$name"
  if [[ ! -f "$src" ]]; then
    missing+=("$name")
    continue
  fi

  # Output file uses the source name verbatim (no extension change — Ghostty
  # themes are extension-less in upstream). We append .conf for clarity.
  out="$DEST_DIR/$name.conf"
  {
    echo "# Theme: $name"
    echo "# Source: $REPO_URL"
    echo "# Pinned commit: $PINNED_COMMIT"
    echo "# Imported by scripts/import-themes.sh — do not edit by hand."
    echo ""
    cat "$src"
  } > "$out"
  imported=$((imported + 1))
done < "$CURATED_LIST"

if [[ ${#missing[@]} -gt 0 ]]; then
  echo ""
  echo "ERROR: the following curated themes were not found in the upstream repo:" >&2
  for m in "${missing[@]}"; do echo "  - $m" >&2; done
  echo "Update scripts/curated-themes.txt or bump PINNED_COMMIT." >&2
  exit 1
fi

echo "Imported $imported themes into $DEST_DIR"
```

- [ ] **Step 3: Make the script executable, run it, verify output**

```bash
chmod +x scripts/import-themes.sh
# Replace PINNED_COMMIT in the script with a recent SHA from
# https://github.com/mbadolato/iTerm2-Color-Schemes/commits/main first.
scripts/import-themes.sh
ls Resources/themes/ | wc -l   # should be ~30
head -10 Resources/themes/Dracula.conf   # attribution header + key=value lines
```

Expected: ~30 `.conf` files in `Resources/themes/`, each beginning with the four `#` comment lines.

If any theme name fails to resolve, fix `curated-themes.txt` (the upstream uses specific casing/spacing — e.g., `Solarized Dark - Patched` has spaces and a dash) and re-run.

- [ ] **Step 4: Update Makefile to bundle themes**

Modify `Makefile` `bundle:` target. After the existing `cp` lines, add:

```makefile
	@mkdir -p $(BUILD)/Forge.app/Contents/Resources/themes
	@cp -R Resources/themes/* $(BUILD)/Forge.app/Contents/Resources/themes/ 2>/dev/null || true
```

- [ ] **Step 5: Build and verify the .app contains themes**

```bash
make dev
ls .build/debug/Forge.app/Contents/Resources/themes/ | head
```

Expected: `.conf` files visible inside the bundled .app.

- [ ] **Step 6: Commit**

```bash
git add scripts/curated-themes.txt scripts/import-themes.sh Resources/themes/ Makefile
git commit -m "feat: vendor curated theme catalog from iTerm2-Color-Schemes"
```

---

## Task 3: Repoint ThemeParser at Bundle + User Override

**Files:**
- Modify: `Sources/Infrastructure/Theme/ThemeParser.swift`

- [ ] **Step 1: Replace `searchPaths` with bundle resource path + user override**

The parser currently hard-codes two Ghostty paths. Replace them with a computed property that returns the bundled `themes/` directory (looked up via `Bundle.main.resourceURL` with the same fallback pattern used by `bundleResource(_:)` in `ForgeApp.swift`) and `~/.config/forge/themes/`. Themes are stored with a `.conf` extension after Task 2, so `parseThemeFile` must accept that suffix as part of the filename (the `id` keeps the extension; the display `name` strips it).

```swift
import Foundation

struct ThemeParser {
    /// Resolves theme search paths. Bundled themes come first (authoritative
    /// for the default catalog); user overrides in ~/.config/forge/themes/
    /// take precedence by matching id first when explicitly loaded via
    /// loadTheme(id:), and appear alongside bundled themes in loadAllThemes().
    private static var searchPaths: [String] {
        var paths: [String] = []
        // User override comes first so loadTheme(id:) prefers it.
        let userOverride = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".config/forge/themes")
        paths.append(userOverride)
        // Bundled themes (inside .app or next to the SPM executable).
        if let resource = Bundle.main.resourceURL?
            .appendingPathComponent("themes").path {
            paths.append(resource)
        }
        if let exec = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("themes").path {
            paths.append(exec)
        }
        return paths
    }

    static func loadTheme(id: String) -> ThemeDefinition? {
        for searchPath in searchPaths {
            let path = (searchPath as NSString).appendingPathComponent(id)
            if let theme = parseThemeFile(path: path, id: id) { return theme }
        }
        return nil
    }

    static func loadAllThemes() -> [ThemeDefinition] {
        var themes: [ThemeDefinition] = []
        let fm = FileManager.default
        for searchPath in Self.searchPaths {
            guard let files = try? fm.contentsOfDirectory(atPath: searchPath) else { continue }
            for file in files.sorted() {
                let fullPath = (searchPath as NSString).appendingPathComponent(file)
                guard !file.hasPrefix("."),
                      let theme = parseThemeFile(path: fullPath, id: file) else { continue }
                if !themes.contains(where: { $0.id == theme.id }) {
                    themes.append(theme)
                }
            }
        }
        return themes
    }

    // parseThemeFile and parseColor unchanged, except the display-name
    // derivation should strip a trailing ".conf" if present:
    //
    //     let name = id
    //         .replacingOccurrences(of: ".conf", with: "")
    //         .replacingOccurrences(of: "_", with: " ")
    //         .replacingOccurrences(of: "-", with: " ")
    //
    // (only that one line of parseThemeFile changes)
}
```

- [ ] **Step 2: Update the default theme id in `ForgeConfig.swift`**

Because filenames now end in `.conf`, change `ThemeConfig(source: "ghostty-seti")` to `ThemeConfig(source: "ghostty-seti.conf")` in `Sources/Infrastructure/Config/ForgeConfig.swift`. The previous value is now stale — existing user configs will fail to resolve a theme until they re-select one. That is acceptable (the picker will still show the catalog; users just need to click once).

- [ ] **Step 3: Build and launch**

```bash
swift build
make dev
sleep 3
curl -s localhost:7654/screenshot > /tmp/forge-screenshot.png
```

- [ ] **Step 4: Open Settings → Theme and verify**

Use the debug server or manual interaction. The picker must show the curated catalog (~30 themes). The active theme should still be ghostty-seti (with the `.conf` source).

```bash
tail -40 /tmp/forge.log | grep -i "theme\|error"
```

Expected: no theme-related errors. If `resolvedTheme` returns nil for ghostty-seti, the default migration didn't work — fix the `ForgeConfig.swift` default.

- [ ] **Step 5: Commit**

```bash
git add Sources/Infrastructure/Theme/ThemeParser.swift Sources/Infrastructure/Config/ForgeConfig.swift
git commit -m "feat: read themes from bundle + ~/.config/forge/themes only"
```

---

## Task 4: Live Re-Apply on `forgeConfigChanged`

**Files:**
- Modify: `Sources/ForgeApp.swift`

- [ ] **Step 1: Extract the theme-application logic into a private helper**

In `AppDelegate`, factor the inline block from `applicationDidFinishLaunching` (the 25 lines that build `fontFamily`, `fontSize`, `fgHex`, `bgHex`, `ansiHex` and call `ghosttyApp.applyConfig(...)`) into a private method that takes an optional override theme. The override is used by hover preview in Task 7; nil means "use the currently configured theme".

```swift
private func applyGhosttyTheme(overrideTheme: ThemeDefinition? = nil) {
    guard let ga = ghosttyApp else { return }
    let fontFamily = configStore.config.terminalFont?.family
        ?? configStore.config.terminal?.fontFamily
        ?? configStore.config.appearance?.fontFamily
    let fontSize = configStore.config.terminalFont?.size
        ?? configStore.config.terminal?.fontSize
        ?? configStore.config.appearance?.fontSize ?? 13
    let theme = overrideTheme ?? configStore.resolvedTheme
    var fgHex: String?
    var bgHex: String?
    var ansiHex: [String]?
    if let theme {
        fgHex = String(format: "#%02x%02x%02x",
            Int(theme.foreground.red * 255),
            Int(theme.foreground.green * 255),
            Int(theme.foreground.blue * 255))
        bgHex = String(format: "#%02x%02x%02x",
            Int(theme.background.red * 255),
            Int(theme.background.green * 255),
            Int(theme.background.blue * 255))
        ansiHex = theme.ansiColors.prefix(16).map { c in
            String(format: "#%02x%02x%02x", Int(c.red * 255), Int(c.green * 255), Int(c.blue * 255))
        }
    }
    ga.applyConfig(fontFamily: fontFamily, fontSize: fontSize,
                   foreground: fgHex, background: bgHex, ansiColors: ansiHex)
}
```

Replace the inline block at the launch site with `applyGhosttyTheme()`.

- [ ] **Step 2: Observe `.forgeConfigChanged` and re-apply**

In `applicationDidFinishLaunching`, after the existing appearance observers, register a new observer:

```swift
NotificationCenter.default.addObserver(
    forName: .forgeConfigChanged, object: nil, queue: .main
) { [weak self] _ in
    MainActor.assumeIsolated { self?.applyGhosttyTheme() }
}
```

- [ ] **Step 3: Build, launch, verify live re-apply**

```bash
make dev
sleep 3
```

Open Settings → Theme, pick a clearly-different theme (e.g., Tokyo Night), close settings. The terminal panes must repaint immediately. Take a screenshot to confirm:

```bash
curl -s localhost:7654/screenshot > /tmp/forge-screenshot.png
# inspect via Read tool
```

Then pick a light theme (e.g., Catppuccin Latte). Verify panes repaint to light colors.

- [ ] **Step 4: Commit**

```bash
git add Sources/ForgeApp.swift
git commit -m "fix: re-apply Ghostty theme on settings change"
```

---

## Task 5: THEMES.md Attribution Doc

**Files:**
- Create: `docs/THEMES.md`
- Modify: `Sources/Features/Settings/AboutPane.swift`

- [ ] **Step 1: Write `docs/THEMES.md`**

Structure: top section credits `mbadolato/iTerm2-Color-Schemes` (link + license note: "Schemes are not subject to copyright unless otherwise stated"); table of bundled themes with original author/source where known (Solarized → Ethan Schoonover; Dracula → Zeno Rocha; Nord → Arctic Ice Studio; Gruvbox → morhetz; Tokyo Night → enkia; Catppuccin → catppuccin org; One Dark → Atom team; Rose Pine → rose-pine org; Tinacious / Ayu / Everforest authors; etc.). Note that Forge does not modify the underlying color values — only prepends an attribution header.

A single markdown file. No need to enumerate every theme exhaustively if the source provenance is clear — but credit the named-brand ones individually.

- [ ] **Step 2: Add an Acknowledgments link in About pane**

Open `Sources/Features/Settings/AboutPane.swift`. Add a small button or link section labeled "Theme Acknowledgments" that opens the GitHub URL for `docs/THEMES.md` in the project repo (or opens the file via `NSWorkspace.shared.open(...)` if the repo URL is unknown). Keep it minimal — one line.

- [ ] **Step 3: Build + screenshot**

```bash
make dev
sleep 3
curl -s localhost:7654/screenshot > /tmp/forge-screenshot.png
```

Open Settings → About; verify the link is present.

- [ ] **Step 4: Commit**

```bash
git add docs/THEMES.md Sources/Features/Settings/AboutPane.swift
git commit -m "docs: theme attribution + About-pane link"
```

---

## Task 6: ThemeWatcher (`~/.config/forge/themes/`)

**Files:**
- Create: `Sources/Infrastructure/Theme/ThemeWatcher.swift`
- Modify: `Sources/ForgeApp.swift` (start watcher, post notification)
- Modify: `Sources/Features/Settings/ThemeSettingsPane.swift` (observe + reload)

- [ ] **Step 1: Add `.forgeThemesChanged` notification name**

In `Sources/ForgeApp.swift`, in the `extension Notification.Name` block:

```swift
static let forgeThemesChanged = Notification.Name("forgeThemesChanged")
```

- [ ] **Step 2: Write `ThemeWatcher`**

```swift
import Foundation

/// Watches ~/.config/forge/themes/ for file changes and posts
/// .forgeThemesChanged. The directory is created lazily on init so
/// users can opt in by simply dropping files into it.
@MainActor
final class ThemeWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    init() {
        let dir = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".config/forge/themes")
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)

        fd = open(dir, O_EVTONLY)
        guard fd >= 0 else {
            ForgeLog.log("[theme] watcher failed to open \(dir): \(errno)")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .extend, .rename],
            queue: .main)
        src.setEventHandler { [weak self] in
            guard self != nil else { return }
            NotificationCenter.default.post(name: .forgeThemesChanged, object: nil)
        }
        src.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fd >= 0 { close(self.fd); self.fd = -1 }
        }
        src.resume()
        source = src
    }

    deinit {
        source?.cancel()
    }
}
```

- [ ] **Step 3: Own a `ThemeWatcher` instance in `AppDelegate`**

In `AppDelegate`, add a stored property:

```swift
private var themeWatcher: ThemeWatcher?
```

In `applicationDidFinishLaunching`, after the GhosttyApp setup block:

```swift
themeWatcher = ThemeWatcher()
```

- [ ] **Step 4: Reload the picker on `.forgeThemesChanged`**

In `Sources/Features/Settings/ThemeSettingsPane.swift`, change `themes` from `@State` loaded once-on-appear to also reload on `.forgeThemesChanged`. Simplest: add an `.onReceive(NotificationCenter.default.publisher(for: .forgeThemesChanged))` modifier that calls the same load block.

```swift
.onReceive(NotificationCenter.default.publisher(for: .forgeThemesChanged)) { _ in
    Task.detached {
        let loaded = ThemeParser.loadAllThemes()
        await MainActor.run { themes = loaded }
    }
}
```

- [ ] **Step 5: Build, launch, manual test**

```bash
make dev
sleep 3
mkdir -p ~/.config/forge/themes
# Copy one of the bundled themes as a "user" theme with a tweak so it's distinguishable:
cp .build/debug/Forge.app/Contents/Resources/themes/Dracula.conf ~/.config/forge/themes/MyDracula.conf
sleep 1
```

Open Settings → Theme. The "MyDracula" theme must appear in the grid without restart.

```bash
rm ~/.config/forge/themes/MyDracula.conf
sleep 1
```

After deletion, re-open Settings → Theme (or with the pane already open): the entry disappears.

- [ ] **Step 6: Commit**

```bash
git add Sources/Infrastructure/Theme/ThemeWatcher.swift Sources/ForgeApp.swift Sources/Features/Settings/ThemeSettingsPane.swift
git commit -m "feat: watch ~/.config/forge/themes for live picker reload"
```

---

## Task 7: Hover-to-Preview

**Files:**
- Modify: `Sources/ForgeApp.swift` (notifications + observers)
- Modify: `Sources/Features/Settings/ThemePreviewCard.swift` (onHover)
- Modify: `Sources/Features/Settings/ThemeSettingsPane.swift` (post hover-ended on disappear)

- [ ] **Step 1: Add two new notification names**

In `Sources/ForgeApp.swift`:

```swift
static let forgeThemeHoverPreview = Notification.Name("forgeThemeHoverPreview")
static let forgeThemeHoverEnded = Notification.Name("forgeThemeHoverEnded")
```

- [ ] **Step 2: Observers in `AppDelegate` that call `applyGhosttyTheme(overrideTheme:)`**

After the `.forgeConfigChanged` observer:

```swift
NotificationCenter.default.addObserver(
    forName: .forgeThemeHoverPreview, object: nil, queue: .main
) { [weak self] note in
    MainActor.assumeIsolated {
        guard let id = note.userInfo?["themeId"] as? String,
              let theme = ThemeParser.loadTheme(id: id) else { return }
        self?.applyGhosttyTheme(overrideTheme: theme)
    }
}
NotificationCenter.default.addObserver(
    forName: .forgeThemeHoverEnded, object: nil, queue: .main
) { [weak self] _ in
    MainActor.assumeIsolated { self?.applyGhosttyTheme() }
}
```

- [ ] **Step 3: Wire `.onHover` in `ThemePreviewCard`**

In `ThemePreviewCard.swift`, add the hover modifier to the outer `VStack`:

```swift
.onHover { hovering in
    if hovering {
        NotificationCenter.default.post(
            name: .forgeThemeHoverPreview,
            object: nil,
            userInfo: ["themeId": theme.id])
    } else {
        NotificationCenter.default.post(
            name: .forgeThemeHoverEnded, object: nil)
    }
}
```

Note: SwiftUI fires `.onHover { false }` reliably on mouse exit for the card's bounds, which gives natural revert behavior when moving between cards or out of the grid.

- [ ] **Step 4: Post `.forgeThemeHoverEnded` on pane disappear**

In `ThemeSettingsPane.swift`, add to the outermost view:

```swift
.onDisappear {
    NotificationCenter.default.post(name: .forgeThemeHoverEnded, object: nil)
}
```

This guarantees the theme reverts to the persisted choice if the user closes settings while hovering over a card.

- [ ] **Step 5: Build + interactive verification**

```bash
make dev
sleep 3
```

Manually: open Settings → Theme; mouse over a card whose colors are obviously different from the active theme. The terminal pane behind the settings window must repaint in real time. Move off the card — pane reverts. Click a card — pane stays in the new theme (persisted). Close settings while hovering — pane reverts (because `.forgeThemeHoverEnded` fires on disappear).

```bash
curl -s localhost:7654/screenshot > /tmp/forge-screenshot.png
# inspect with Read
tail -30 /tmp/forge.log | grep -i theme
```

- [ ] **Step 6: Commit**

```bash
git add Sources/ForgeApp.swift Sources/Features/Settings/ThemePreviewCard.swift Sources/Features/Settings/ThemeSettingsPane.swift
git commit -m "feat: hover-to-preview themes in settings picker"
```

---

## Verification Checklist (run before merging)

- [ ] `swift build` succeeds
- [ ] `swift test` passes (no test changes expected; just verify no regressions)
- [ ] `make dev` launches; `tail -20 /tmp/forge.log` shows no theme-related errors
- [ ] Settings → Theme shows the curated catalog (~30 entries)
- [ ] Picking a theme repaints the terminal immediately (Task 4)
- [ ] Hovering a card previews the terminal; mouse-out reverts (Task 7)
- [ ] Dropping a `.conf` into `~/.config/forge/themes/` makes it appear without restart (Task 6)
- [ ] About → Theme Acknowledgments link works (Task 5)
- [ ] No code path still references `/Applications/Ghostty.app` or `~/.config/ghostty/themes` (`grep -r "ghostty/themes" Sources/`)

---

## Open Risks / Notes for the Executor

1. **Upstream filename drift.** `mbadolato/iTerm2-Color-Schemes` occasionally renames themes (case, dashes vs. spaces). The import script fails loudly when a curated entry doesn't exist — fix the curated list, not the script. Pin to a known-good commit before importing.

2. **`.conf` extension migration.** Existing user configs reference `"ghostty-seti"` without extension. Task 3 Step 2 changes the default to `"ghostty-seti.conf"`. Existing users with a saved config will see their theme not resolve until they reselect; that's a one-time minor regression for early adopters and the trade-off is preferred over special-case extension stripping in the parser.

3. **Trademark sensitivity.** Themes like Dracula and Nord have brand/trademark considerations. We're shipping the original (unmodified) palettes with attribution — the safe path. Do not rename, "fix", or recolor any bundled theme; if you want a variant, ship it under a clearly different name.

4. **Hover preview during typing.** If the user types while a hover preview is active, libghostty receives input normally — the hover only affects rendering config, not input plumbing. No special handling needed.

5. **Bundled themes vs. user override precedence.** `searchPaths` puts the user override first; a `MyTheme.conf` in `~/.config/forge/themes/` with the same name as a bundled theme will shadow the bundled one in `loadTheme(id:)`. `loadAllThemes()` dedupes by id, so the picker shows whichever is loaded first — user override wins. This is intentional.

6. **No new tests.** The work in this plan is heavily integration-level (file system, libghostty, AppKit notifications). Unit tests would require extracting pure-logic seams that don't currently exist; that refactor is out of scope. Verification is via the manual checklist above.
