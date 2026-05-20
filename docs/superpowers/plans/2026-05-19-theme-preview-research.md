# Theme Preview Exhaustiveness — Research Plan

**Goal:** Find every place in Forge where a theme-derived color, font, appearance, or other config-derived visual property is rendered, and classify each by how it reacts to a theme change today. Then we know exactly what's missing from the preview path and can design a fix that's actually exhaustive.

**Why research first:** the previous "full-UI preview" fix touched only what I assumed mattered (SwiftUI views reading `configStore.resolvedTheme`). The user reports the title bar and the sidebar/content divider don't update — proof that there are theme-bound surfaces I don't know about. Guessing again would miss more.

---

## Research dimensions

A theme-bound surface falls into one of three categories. Each category requires a different repaint mechanism. I need a complete inventory by category before I can design an exhaustive fix.

### Category A — Pure SwiftUI views reading `configStore.resolvedTheme`

Should update for free via `@Observable` (already proven to work for the sidebar). Inventory exists to confirm coverage and rule out missed cases.

### Category B — AppKit / NSWindow / NSView with explicit refresh

These don't observe Swift state — they need an explicit method call to repaint (e.g., `TitleBarManager.syncAppearance()`). Today, those methods are wired to `.forgeConfigChanged` only. Need to find all of them and decide if the preview path should fire `.forgeConfigChanged` or a new event.

### Category C — One-shot computations cached during setup

Things computed once at init from the theme and never re-read (e.g., a color baked into a view's `init`, an NSColor assigned to a layer at app start). These are the trickiest because they don't have an obvious refresh hook — fixing them may require refactoring to make the property `@Observable`.

---

## Task 1: Inventory all `configStore.resolvedTheme` reads

**Tool:** `grep -rn "resolvedTheme" Sources/`

**Expected output per match:** file path, line, surrounding context (1–2 lines).

For each, classify:
- **SwiftUI view body** (auto-updates) → Category A
- **Helper function called from view body** (auto-updates via re-invocation) → Category A
- **Init / setup / one-shot** → Category C
- **AppKit context** (e.g., inside an `NSView` subclass `draw` or `viewDidMoveToWindow`) → Category B

## Task 2: Inventory all `.forgeConfigChanged` observers

**Tool:** `grep -rn "forgeConfigChanged" Sources/`

These are the surfaces that currently get refreshed when the user clicks a theme. They're the AppKit/imperative refresh sites — exactly the ones the preview path is missing today. Document what each one does so we know whether posting `.forgeConfigChanged` on preview is safe (vs. needing a separate event).

## Task 3: Find AppKit-bound theme surfaces by searching for NSWindow/NSColor + theme

**Tools:**
- `grep -rn "NSColor\|backgroundColor\|layer.backgroundColor\|appearance" Sources/` — narrow to lines that look theme-related.
- `grep -rn "TitleBarManager\|syncAppearance" Sources/` — direct title bar refresh entry points.
- `grep -rn "window.appearance\|NSAppearance\|effectiveAppearance" Sources/` — light/dark mode wiring.

Document the call sites and the trigger conditions (when do they re-run?).

## Task 4: Find the sidebar/content divider specifically

The user called out this one explicitly.

**Tools:**
- `grep -rn "Divider\|divider\|HSplitView\|NavigationSplitView" Sources/Features/Sidebar Sources/Features/Shared Sources/`
- Inspect `MainView.swift` for the sidebar/content layout — likely a `HSplitView` or a custom split with a manual divider view.

Identify the color/material used for the divider and which category it falls into.

## Task 5: Find hard-coded theme-derived colors

**Tool:** `grep -rn "Color.white.opacity\|Color(red:" Sources/`

Per CLAUDE.md:
> UI surfaces (sidebar, toolbars, title bar spacers) layer `Color.white.opacity(0.06)` on top of the theme background for subtle depth.

That `Color.white.opacity(0.06)` is theme-independent (it's an overlay), but the *underlying* color comes from theme. Need to verify each occurrence reads `resolvedTheme` for the base color and applies the overlay on top, vs. just using a static dark gray.

Also look for fallback default backgrounds — `Color(red: 0.1, green: 0.1, blue: 0.1)` — that might be rendering when `resolvedTheme` returns nil. Not a preview issue, but worth noting.

## Task 6: Find places where `ForgeConfigStore.shared` is referenced directly (bypassing @Environment)

**Tool:** `grep -rn "ForgeConfigStore.shared\|store.shared\|configStore.shared" Sources/`

If any view reads `.shared` directly inside a non-View context (e.g., an AppKit helper), `@Observable` updates won't propagate. Document these.

## Task 7: Spot-check live state via the debug server (post-research)

If the app is running with the preview fix from this morning, hover over a theme card and:

```bash
curl -s localhost:7654/state | jq '...'
```

…to see whether `configStore.previewTheme` actually flips. (Tests the wiring, not the rendering.)

This is optional — primarily useful if research turns up ambiguity about whether a given site is reading the store correctly.

---

## Deliverable

After Tasks 1–6, produce a single research-findings doc — `docs/superpowers/research/2026-05-19-theme-preview-coverage.md` — with three sections:

1. **Category A inventory** (SwiftUI, auto-updates) — files + lines + confirmation it works.
2. **Category B inventory** (AppKit, needs explicit refresh) — files + lines + the current refresh trigger + whether the preview path needs to invoke it.
3. **Category C inventory** (one-shot at setup) — files + lines + what would need to change to make it preview-responsive.

The implementation plan (separate doc, written after research) will reference this inventory directly.

---

## Open questions to resolve during research

1. Does `.forgeConfigChanged` semantically imply "config was saved" anywhere? If so, posting it on preview (which doesn't save) could fire bogus persistence-style side effects. The alternative is a new `.forgeThemeApplied` event that fires for both save *and* preview, with `.forgeConfigChanged` retained for save-only signaling. Research Task 2 informs this.

2. Is the divider a SwiftUI `Divider()` (auto-color from system), a manual `Rectangle()` with theme color, or a built-in split-view chrome? Each has a different fix.

3. Are there themed colors that get computed in the `AppDelegate.applicationDidFinishLaunching` block (once, at startup) and never re-derived? `applyGhosttyTheme()` covers libghostty, but other startup-time theme reads would need similar re-application hooks.
