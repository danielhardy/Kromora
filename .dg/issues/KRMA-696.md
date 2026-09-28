---
id: KRMA-696
title: Rebuild window toolbar as Xcode-grade Liquid Glass groups
type: task
status: backlog
priority: high
creation_provenance:
  runner: pi
  model: unknown
  actor: pi
labels:
  - app-shell
  - tahoe
  - liquid-glass
  - toolbar
created: 2026-09-28T22:19:35.030Z
updated: 2026-09-28T22:20:13.558Z
depends_on:
  - KRMA-694
blockers: []
order: y
board: product
---

## Objective

Rebuild the window toolbar as Xcode-grade Liquid Glass: inline traffic lights in a full-width unified bar, functionally grouped glass pills with light-but-solid material, correct spacing rhythm, full accessibility. This is the visual centerpiece of the Tahoe move.

Parent: KRMA-693. Sequencing: after KRMA-694 (floor raise); parallel with KRMA-695 and KRMA-697 but coordinate `ContentView.swift` edits — this ticket owns the `.toolbar` block, the sibling owns the window-hack removal.

## Context

Today (`Sources/KromoraKit/Views/ContentView.swift:53-80`, `toolbarContent ~:150-260`):

- Eight loose `.edit` items (Crop, Auto `ZStack` crossfade, zoom `Menu`, Compare, Info, Reset `Menu`, Import `Menu`, Export) in one `ToolbarItemGroup(placement:.primaryAction)` plus a `.navigation` Library/Edit segmented picker. No grouping — AppKit spaces them as flat items.
- Duplicated `#available(macOS 26.0, *)` branches differing only by `ToolbarSpacer(.flexible)`.
- Transparent titlebar via `TitlebarSeparatorSuppression`; `KromoraTheme.swift` rule "do not paint a custom fill"; `.tint(KromoraTheme.primaryAccent)`.

Target (`.context/Screenshot 2026-09-28 at 4.07.42 PM.png` — Xcode): `[sidebar,sparkle]` / `[play,stop]` pills left, fused breadcrumb pill center, layout pills right; `.regular` solid-light glass — blurs but never reads through.

## Acceptance criteria

- [ ] Toolbar uses Tahoe APIs unconditionally: `ToolbarSpacer`, `GlassEffectContainer` + `glassEffectUnion` for fused pills, `.glass` button style inside pills, `.glassProminent` reserved for crop `Save`. No `#available` branches.
- [ ] Grouping by function, e.g. edit cluster (Crop/Auto/Zoom/Compare), view cluster (Info/Reset), transfer cluster (Import/Export); `ToolbarSpacer(.fixed)` between pills, `.flexible` only around the center; crop mode gets its own Save/Cancel/Undo pill.
- [ ] Background is solid-light glass: `.toolbarBackgroundVisibility(.visible, for: .windowToolbar)` with `.regularMaterial` (or `windowBackground.opacity(~0.75)` + `.regularMaterial` if the raw material reads too thin); verified in light and dark against `KromoraTheme.primaryAccent` tint.
- [ ] Traffic lights inline and vertically centered via standard `.windowStyle(.titleBar)` unified bar (no custom title); no floating-over-content artifacts.
- [ ] All actions keep `help`, `accessibilityLabel/Value/Hint` (Auto crossfade stays `accessibilityHidden` with the stable button label above, as today); shortcuts unchanged (`⌘S` stays on the File menu item only).
- [ ] Aperture-level finish: consistent pill geometry, correct vibrancy under glass, no clipped `Label` footprints (`AutoToolbarButton` widest-state layout preserved), no hover/press morph glitches.
- [ ] `swift build` zero warnings; focused UI tests + `scripts/ci-tests.sh fast` clean; manual pass at 800x500, 1200x800, light/dark, reduce-motion.

## Implementation notes

Files: `ContentView.swift` (toolbar block, `workspaceModePicker`, `toolbarContent`, `AutoToolbarButton`, `CanvasToolbarControls`, `CropToolbarControls`), `KromoraTheme.swift` (rewrite the toolbar-material comment to specify the glass recipe), `KromoraApp.swift` (confirm `.windowStyle(.titleBar)`). Keep all coordinator call sites identical — grouping only. If `KromoraTheme` needs a glass-tint token, add one dynamic color there rather than scattering literals.
