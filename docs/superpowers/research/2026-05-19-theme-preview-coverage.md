# Theme Preview Coverage — Research Findings

## Category A — SwiftUI views reading `configStore.resolvedTheme` (auto-update via `@Observable`)

These work today with the previewTheme observable from this morning. Sidebar repaints because of them.

| File | Line | Surface |
| --- | --- | --- |
| `Features/Shared/MainView.swift` | 24 | `sidebarBackground` (sidebar bg) |
| `Features/Shared/MainView.swift` | 34 | `themeForeground` (foreground tint) |
| `Features/Sidebar/StatusDot.swift` | 17 | attention status dot |
| `Features/Terminal/TerminalArea.swift` | 35 | terminal pane area background |
| `Features/Terminal/ProjectDetailView.swift` | 22 | project detail container |
| `Features/Terminal/WindowTabBar.swift` | 121 | window tab bar background |
| `Features/Stack/StackView.swift` | 22 | stack mode background |
| `Features/Stack/StackToolbar.swift` | 22 | stack mode toolbar |
| `Features/Settings/NotificationsSettingsPane.swift` | 76 | notification preview fill |
| `Features/Settings/ListModeSettingsPane.swift` | 48 | list-mode preview fill |
| `Infrastructure/Config/ForgeConfigStore.swift` | 23 | `tabHighlightColor` derived from theme |

## Category B — AppKit, needs explicit refresh — currently broken on preview path

**TitleBarManager** is the entire problem.

| File | Line | What it does | Current trigger | Preview-broken? |
| --- | --- | --- | --- | --- |
| `Features/TitleBar/TitleBarManager.swift` | 114 | `syncAppearance()`: sets `window.backgroundColor`, `window.appearance` (light/dark), calls `stripTitleBarChrome()` | `.forgeConfigChanged` observer (line 95) | **Yes** — `.forgeConfigChanged` is never fired by preview |
| `Features/TitleBar/TitleBarOverlay.swift` | 38 | `applyTitleBarBackground()`: sets `NSTitlebarView.layer.backgroundColor` and `NSTitlebarBackgroundView.layer.backgroundColor` | Called from `stripTitleBarChrome()` (line 11), which is called from `syncAppearance()` | **Yes** (transitively — depends on syncAppearance) |

`updateOverlayConstraints()` and `updateSplitIconVisibility()` also fire from the same observer, but they don't depend on the theme — firing them on preview is harmless idempotent work.

## Category C — Hardcoded grays and overlays

| File | Line | What | Theme-bound? |
| --- | --- | --- | --- |
| `Features/Terminal/PaneSplitView.swift` | 18 | `Color(red: 0.1, green: 0.1, blue: 0.1)` placeholder when renderer is missing | No (rare edge case, OK) |
| `Features/Terminal/TerminalArea.swift` | 14 | Same — fallback layer | No (only shown when theme is nil) |
| `Features/Shared/MainView.swift` | 26 | `Color.white.opacity(0.06)` overlay | No, it layers on top of `theme.background.color` — already reactive |
| `Features/Stack/StackView.swift`, `StackToolbar.swift` | 23, 24 | Same overlay pattern | No, already reactive |
| `Features/Shared/ModalContainer.swift`, `ModalOverlays.swift` | 24, 73 | `Color.white.opacity(0.1)` border stroke | No, theme-independent |
| `Features/Stack/StackNewTabPicker.swift` | 77 | hover state | No, theme-independent |
| `Features/Settings/*.swift` fallbacks | various | `?? Color(red: 0.1, green: 0.1, blue: 0.1)` after a `?.` chain | No, only fallback when `resolvedTheme` is nil |
| `Features/TitleBar/TitleBarOverlay.swift` | 48 | Same fallback pattern in NSColor form | No, only fallback |

All hardcoded grays are either fallbacks (used only when no theme is set) or theme-independent overlays. None block preview correctness.

## Sidebar/content "divider" diagnosis

The user reports the divider between sidebar and content doesn't update.

- `MainView.swift:133` `sidebarDivider` is `Color.clear` with a 16px hit region for the drag gesture. **There is no colored divider line** — the visible boundary is purely the contrast between the sidebar's `Color.white.opacity(0.06)` overlay and the content's plain theme bg.

Both sides ARE theme-bound and ARE updating during preview today. **What the user is most likely seeing is the title bar boundary above them**, which doesn't update because TitleBarManager observes `.forgeConfigChanged`-only. From a user's visual perspective, the unchanging title bar reads as a stale horizontal stripe at the top of both the sidebar and the content — easy to perceive as "the divider didn't update."

Fixing TitleBarManager fixes both.

## Other findings

- `ForgeConfigStore.shared` is referenced only in `ForgeApp.swift:61` (composition root) — no other code uses `.shared` directly, so no `@Observable` bypass risk.
- `.forgeConfigChanged` has exactly two observers (`ForgeApp.swift:149` calls `applyGhosttyTheme()`, `TitleBarManager.swift:95` calls `syncAppearance()` + two layout updates). Firing it on preview triggers only theme-relevant + idempotent layout work — safe.
- No accidental theme caches found outside `ForgeConfigStore._resolvedTheme` (which is bypassed by `previewTheme` already).

## Conclusion

**Single root cause:** `.forgeConfigChanged` is the existing "everything that depends on theme repaint yourself" signal, but the preview path doesn't fire it.

**Fix:** make `ForgeConfigStore.previewTheme` post `.forgeConfigChanged` in `didSet`. Every AppKit refresh wired to `.forgeConfigChanged` (i.e., TitleBarManager) wakes up. Every SwiftUI view that reads `resolvedTheme` already reacts via `@Observable`.

No other surfaces require attention. The fix is one observable property + one notification post.
