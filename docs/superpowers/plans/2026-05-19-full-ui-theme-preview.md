# Full-UI Theme Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make theme hover-preview update the *entire* UI (sidebar, title bar, modals, terminal) instead of just the terminal cells. Today only libghostty is repainted on hover; chrome stays on the committed theme until click.

**Architecture:** Move preview state from a one-off `overrideTheme:` parameter on `applyGhosttyTheme` into a first-class observable property on `ForgeConfigStore`. `resolvedTheme` returns `previewTheme ?? configResolvedTheme`. Every SwiftUI view that reads `configStore.resolvedTheme` automatically picks up the preview via `@Observable`. The terminal still needs an explicit `applyGhosttyTheme()` call because libghostty is a C surface, but it now reads from the same source of truth.

**Tech Stack:** Swift 6 `@Observable`, SwiftUI environment-driven invalidation, NotificationCenter.

---

## File Structure

**Modified files:**
- `Sources/Infrastructure/Config/ForgeConfigStore.swift` — add `var previewTheme: ThemeDefinition?` and update `resolvedTheme` to prefer it.
- `Sources/ForgeApp.swift` — observers now set/clear `configStore.previewTheme` in addition to calling `applyGhosttyTheme()`. Drop the `overrideTheme:` parameter from `applyGhosttyTheme`.

**No new files. No deletions.**

---

## Task 1: Add `previewTheme` to ForgeConfigStore

**Files:**
- Modify: `Sources/Infrastructure/Config/ForgeConfigStore.swift`

- [ ] **Step 1: Add the property**

After the existing `var isStackMode: Bool = false` (around line 56), add:

```swift
/// Transient hover-preview theme. When non-nil, shadows the config-resolved
/// theme everywhere `resolvedTheme` is read — sidebar, title bar, modals,
/// terminal. Set by the hover observer in AppDelegate; cleared on hover-out
/// or settings pane disappear. Not persisted.
var previewTheme: ThemeDefinition?
```

- [ ] **Step 2: Update `resolvedTheme` to consult preview first**

Replace the existing `resolvedTheme` computed property (around line 75-80) with:

```swift
var resolvedTheme: ThemeDefinition? {
    if let preview = previewTheme { return preview }
    if let cached = _resolvedTheme { return cached }
    let result = resolveThemeFromConfig()
    _resolvedTheme = .some(result)
    return result
}
```

Key points:
- Preview check happens **before** the cache lookup — preview is by definition transient, no caching.
- The cache still serves the config-resolved path (which is the common case when no hover is active).

- [ ] **Step 3: Build**

```bash
swift build
```

Must succeed cleanly. The change is purely additive on the store side.

- [ ] **Step 4: Commit**

```bash
git add Sources/Infrastructure/Config/ForgeConfigStore.swift
git commit -m "feat: add previewTheme observable to ForgeConfigStore"
```

---

## Task 2: Wire the hover observers to set/clear `previewTheme` and drop the parameter

**Files:**
- Modify: `Sources/ForgeApp.swift`

- [ ] **Step 1: Drop `overrideTheme:` parameter from `applyGhosttyTheme`**

The method signature becomes `private func applyGhosttyTheme()`. The body changes one line — replace `let theme = overrideTheme ?? configStore.resolvedTheme` with `let theme = configStore.resolvedTheme`.

This works because preview, if active, is already inside `resolvedTheme` from Task 1.

- [ ] **Step 2: Update the `.forgeThemeHoverPreview` observer**

Replace the existing observer block:

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

The key change: set `configStore.previewTheme = theme` *before* calling `applyGhosttyTheme()`. The order matters — `applyGhosttyTheme()` reads `resolvedTheme`, which now sees the preview.

- [ ] **Step 3: Update the `.forgeThemeHoverEnded` observer**

Replace with:

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

Order: clear preview first, then re-apply — terminal repaints to config-resolved theme.

- [ ] **Step 4: Confirm `.forgeConfigChanged` observer still works**

The existing `.forgeConfigChanged` observer just calls `self?.applyGhosttyTheme()`. No change needed — `applyGhosttyTheme()` will read the current `resolvedTheme`, which respects whatever state `previewTheme` is in.

**Subtle behavior to verify (mental check, not code):** when the user clicks a card while hovering it:
1. Click handler calls `store.update { $0.theme = ... }` — saves config, invalidates `_resolvedTheme`, posts `.forgeConfigChanged`.
2. `.forgeConfigChanged` observer fires `applyGhosttyTheme()`. Inside `resolvedTheme`, `previewTheme` is still set (hover-out hasn't fired yet) — so the returned theme is the preview, which happens to equal the just-clicked theme. No visual change. Correct.
3. Mouse moves off the card → `.forgeThemeHoverEnded` fires → `previewTheme = nil` → re-apply → reads config-resolved theme (the just-clicked one). Still no visual change. Correct.

Both paths converge on the right end state. No special coordination needed.

- [ ] **Step 5: Build + test**

```bash
swift build
swift test
```

Both must succeed.

- [ ] **Step 6: Commit**

```bash
git add Sources/ForgeApp.swift
git commit -m "feat: hover-preview now updates entire UI, not just terminal"
```

---

## Manual verification (post-merge)

`make restart`, then:

1. Open Settings → Theme.
2. Hover a theme card with a clearly different background — sidebar, title bar, AND terminal repaint simultaneously.
3. Move mouse off the card — everything reverts.
4. Hover a card, click it — UI stays in the clicked theme; no flicker as hover-out fires.
5. Hover a card, close Settings (cmd+W or click X) — UI reverts (the `.onDisappear` in ThemeSettingsPane fires `.forgeThemeHoverEnded`).

If step 5 doesn't revert, the `.onDisappear` in `ThemeSettingsPane` isn't firing — verify the modifier is on the outermost view.

---

## Open risks / notes

1. **Settings sheet vs. modal:** If Settings is presented as an inactive sheet (window covered by main window), `.onHover { false }` may not fire reliably when the user clicks back to the main window. Mitigated by the `.onDisappear` cleanup — preview clears when the Settings tab/pane is dismissed entirely. If users notice "stuck" preview when clicking past Settings without closing it, add an `NSApplication.didResignActiveNotification` observer that clears `previewTheme`. Not doing it preemptively (YAGNI).

2. **previewTheme is not Codable / not persisted:** That's deliberate. It's transient UI state. If the app crashes mid-hover, the next launch starts with `previewTheme = nil`. No special handling needed.

3. **No tests added:** The behavior is integration-level (Notification dispatch + SwiftUI re-render + libghostty re-apply). Verifying it in `swift test` would require a fake notification center and a render-counter on `ForgeConfigStore`. Manual verification is the right tool here.
