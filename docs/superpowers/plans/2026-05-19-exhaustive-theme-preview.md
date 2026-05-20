# Exhaustive Theme Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make theme hover preview update every visible surface in Forge, including the title bar (the surface that currently doesn't update).

**Architecture:** Research (`docs/superpowers/research/2026-05-19-theme-preview-coverage.md`) identified a single root cause: AppKit-bound surfaces refresh on the `.forgeConfigChanged` notification, but the preview path doesn't fire it. The fix is to have `ForgeConfigStore.previewTheme` post `.forgeConfigChanged` in its `didSet`. Every SwiftUI view already auto-updates via `@Observable`. Every AppKit observer (TitleBarManager) already does the right work in response to `.forgeConfigChanged`. The change is minimal because the wiring already exists — it's just not connected to the preview signal yet.

**Cleanup opportunity:** With the `didSet` posting the notification, the hover observers in `AppDelegate` no longer need to call `applyGhosttyTheme()` directly — they can just set `previewTheme` and let the existing `.forgeConfigChanged` observer in the same `AppDelegate` do the libghostty re-apply. Removes a duplicate path.

**Tech Stack:** Swift 6 `@Observable`, NotificationCenter, AppKit.

---

## File Structure

**Modified files (two):**
- `Sources/Infrastructure/Config/ForgeConfigStore.swift` — wrap `previewTheme` in a `didSet` that posts `.forgeConfigChanged`.
- `Sources/ForgeApp.swift` — hover observers stop calling `applyGhosttyTheme()` directly (the config-changed observer will handle it via the didSet cascade).

**No new files. No new notifications.**

---

## Task 1: Add `didSet` to `previewTheme`

**File:** `Sources/Infrastructure/Config/ForgeConfigStore.swift`

- [ ] **Step 1: Wrap `previewTheme` in `didSet`**

Currently:

```swift
var previewTheme: ThemeDefinition?
```

Becomes:

```swift
var previewTheme: ThemeDefinition? {
    didSet {
        // Fires the same signal that config-save uses, so every AppKit
        // observer (TitleBarManager) and the libghostty re-apply hook in
        // AppDelegate both run. SwiftUI views update automatically via
        // @Observable on the property itself.
        NotificationCenter.default.post(name: .forgeConfigChanged, object: nil)
    }
}
```

Notes:
- Don't gate the post on `oldValue != newValue`. Equality on `ThemeDefinition` is undefined (no `Equatable` conformance), and redundant posts on rapid hover are cheap (the resulting work is idempotent).
- Don't invalidate `_resolvedTheme` — the preview check in `resolvedTheme` short-circuits before the cache anyway.

- [ ] **Step 2: Build**

```bash
swift build
```

Must succeed. Pure additive change to the existing property.

- [ ] **Step 3: Commit**

```bash
git add Sources/Infrastructure/Config/ForgeConfigStore.swift
git commit -m "feat: previewTheme posts forgeConfigChanged so AppKit surfaces refresh"
```

---

## Task 2: Drop redundant `applyGhosttyTheme()` calls from hover observers

**File:** `Sources/ForgeApp.swift`

The hover observers currently set `previewTheme` AND call `applyGhosttyTheme()`. With Task 1, the `previewTheme` `didSet` posts `.forgeConfigChanged`, which the existing observer (line 149) already turns into an `applyGhosttyTheme()` call. The direct call is now redundant.

- [ ] **Step 1: Simplify `.forgeThemeHoverPreview` observer**

Replace:

```swift
NotificationCenter.default.addObserver(
    forName: .forgeThemeHoverPreview, object: nil, queue: .main
) { [weak self] note in
    let themeId = note.userInfo?["themeId"] as? String
    MainActor.assumeIsolated {
        guard let self,
              let id = themeId,
              let theme = ThemeParser.loadTheme(id: id) else { return }
        self.configStore.previewTheme = theme
        self.applyGhosttyTheme()
    }
}
```

with:

```swift
NotificationCenter.default.addObserver(
    forName: .forgeThemeHoverPreview, object: nil, queue: .main
) { [weak self] note in
    let themeId = note.userInfo?["themeId"] as? String
    MainActor.assumeIsolated {
        guard let self,
              let id = themeId,
              let theme = ThemeParser.loadTheme(id: id) else { return }
        self.configStore.previewTheme = theme
    }
}
```

(Removed the `applyGhosttyTheme()` call. The didSet → notification → existing observer cascade handles it.)

- [ ] **Step 2: Simplify `.forgeThemeHoverEnded` observer**

Replace:

```swift
NotificationCenter.default.addObserver(
    forName: .forgeThemeHoverEnded, object: nil, queue: .main
) { [weak self] _ in
    MainActor.assumeIsolated {
        self?.configStore.previewTheme = nil
        self?.applyGhosttyTheme()
    }
}
```

with:

```swift
NotificationCenter.default.addObserver(
    forName: .forgeThemeHoverEnded, object: nil, queue: .main
) { [weak self] _ in
    MainActor.assumeIsolated {
        self?.configStore.previewTheme = nil
    }
}
```

- [ ] **Step 3: Build + test**

```bash
swift build
swift test
```

Both must succeed.

- [ ] **Step 4: Commit**

```bash
git add Sources/ForgeApp.swift
git commit -m "refactor: hover observers rely on previewTheme didSet for cascade"
```

---

## Manual verification (post-implementation)

`make restart`, then in the running app:

1. Open Settings → Theme.
2. Hover a card with a clearly contrasting background (e.g., Catppuccin Latte if you're on Tokyo Night).
3. Confirm **all four** surfaces repaint together:
   - **Sidebar** (theme bg + white overlay) — already worked before this fix
   - **Terminal panes** (libghostty cells) — already worked before this fix
   - **Title bar** (`NSTitlebarView.layer.backgroundColor` + `window.appearance` light/dark) — **NEW**
   - **Window background visible at edges** (`window.backgroundColor`) — **NEW**
4. Move mouse off the card. All four revert together.
5. Hover, then click. Theme commits; UI stays in the clicked colors with no flicker.
6. Verify light/dark mode switches correctly: hover a light theme on a dark base, the title bar text colors and traffic lights should flip to light-mode equivalents (this is `window.appearance` doing its job).

---

## Open risks

1. **`.forgeConfigChanged` semantic drift.** The notification now fires on hover, not just on config-save. Existing observers (`TitleBarManager`, the `applyGhosttyTheme` hook) treat it as "something theme-relevant changed," which is correct for both cases. No observer is assumed to mean "config was persisted to disk." If a future observer adds save-related side effects (e.g., backup, sync, version increment), it must either gate on "did the saved config actually change" or listen to a different signal. Document this in the `didSet` comment to flag the contract.

2. **Repeated rapid posts on hover-across-cards.** Mouse-out of card A and mouse-in of card B fire two notifications in quick succession. Both observers run twice. The work is idempotent (sync window appearance, repaint libghostty, repaint SwiftUI). No visible flicker risk because both calls converge on the same end state. If it ever becomes a perf issue, we could coalesce via `DispatchQueue.main.async` debounce — not needed today.

3. **Title bar chrome stripping side effect.** `syncAppearance()` calls `stripTitleBarChrome()` which calls `applyTitleBarBackground()`. The strip runs on every hover. Per `MEMORY.md`: "Title bar managed by TitleBarManager. Stripping runs on a 100ms repeating timer for 3s at launch, plus on `didBecomeKeyNotification` and after fullscreen exit." Adding hover doesn't change the strip cadence dangerously — strip is idempotent (it hides the same private views each time). If you see flicker around the title bar chrome on rapid hover, that's the strip thrashing; defer the strip behind a "first call only" guard in `syncAppearance()` if it shows up.

4. **No tests added.** The behavior is integration-level (notification → AppKit refresh → visual change). Unit-testing it would require a fake notification center and a mock NSWindow — high cost, low value. Verification is by hand per the checklist above.
