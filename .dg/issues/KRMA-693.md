---
id: KRMA-693
title: Tahoe-only baseline and Xcode-grade window chrome
type: feature
status: backlog
priority: high
creation_provenance:
  runner: pi
  model: unknown
  actor: pi
labels:
  - app-shell
  - tahoe
  - epic
created: 2026-09-28T22:18:39.078Z
updated: 2026-09-28T22:42:06.237Z
depends_on:
  - KRMA-694
  - KRMA-695
  - KRMA-696
  - KRMA-697
  - KRMA-699
blockers: []
order: s
board: product
---

## Objective

Move Kromora to a macOS 26 (Tahoe) and Apple Silicon only baseline and rebuild the window chrome so the toolbar, sidebar, and inspector match Xcode-grade Liquid Glass quality: traffic lights inline in a full-width unified bar, functionally grouped glass pills with light-but-solid material, sidebar and inspector docked below the bar. No macOS 14/15 or Intel fallback paths remain.

Reference: `.context/Screenshot 2026-09-28 at 4.07.42 PM.png` (Xcode: full-width bar, `[sidebar,sparkle]` / `[play,stop]` pills, fused center breadcrumb pill, right layout pills, navigator and inspector starting below the bar).

## Why a parent

The deployment-floor raise touches the manifest, bundle, scripts, docs, availability guards, toolbar construction, and window layout. Each child is independently reviewable and independently revertible. Keep this parent in `backlog` as the tracker; implement children one at a time.

When you update the notes -- ideally state how many lines you removed

## Children

- Raise deployment floor to macOS 26 (manifest, bundle, scripts, docs) — KRMA-694, done
- Remove pre-Tahoe availability guards and dead fallback paths — KRMA-695
- Drop Intel and universal release builds; ship Apple Silicon only — KRMA-699
- Rebuild window toolbar as Xcode-grade Liquid Glass groups — KRMA-696
- Dock sidebar and inspector below unified toolbar (remove titlebar bleed hacks) — KRMA-697

## Acceptance criteria

- [ ] `Package.swift`, `Sources/Kromora/Info.plist`, `scripts/build-macos-app.sh` all declare 26.x; no `14.0` floor remains in product sources, scripts, or user-facing docs.
- [ ] Release packaging produces an arm64-only app. No `x86_64` slice, `lipo` universal path, or Intel fallback remains in product scripts or packaging docs.
- [ ] Zero `#available(macOS 12/13/14/15)` workarounds in `Sources/`; zero `if #available(macOS 26)` branches that are now always-true.
- [ ] Toolbar reads as Xcode-grade: inline stoplights, 2-3 functional glass pills (edit / view / import-export) plus crop-mode pill, `ToolbarSpacer(.fixed)` rhythm between pills, `.toolbarBackgroundVisibility(.visible)` with `.regular` solid-light glass in both appearances.
- [ ] Sidebar and inspector start below the toolbar; no transparent-titlebar bleed, no histogram under glass, no 1px drag gap.
- [ ] `swift build` zero warnings, Swift 6 zero escape hatches (`@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency` absent), `scripts/ci-tests.sh fast` + `serial` clean.
- [ ] Light/dark, reduce-motion, VoiceOver labels/help, min 800x500 and default 1200x800 verified; drag/resize/tab show no transparency or separator glitches.

## Quality bar

Apple-shipped feel: consistent pill geometry and spacing, correct vibrancy under glass, no custom fills fighting the system material, no leftover compat comments referencing macOS 14. Every child updates or removes its stale comments and docs.

## Implementation notes

Key files: `Sources/KromoraKit/Views/ContentView.swift` (toolbar, `TitlebarSeparatorSuppression`, `mainContent`, `detailContent`), `Sources/KromoraKit/Views/InfoInspectorView.swift` (histogram bleed), `Sources/KromoraKit/Views/KromoraTheme.swift` (toolbar-material comment), `Sources/Kromora/KromoraApp.swift` (`.windowStyle`), `Package.swift`, `Sources/Kromora/Info.plist`, `scripts/build-macos-app.sh`, `docs/PACKAGING.md`, `docs/ENGINEERING_GUIDE.md`, `CLAUDE.md`.
