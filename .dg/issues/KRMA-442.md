---
id: KRMA-442
title: Group monochrome starter Looks together and drop color-skewed presets (Forest, Midnight, Neon)
type: task
status: done
priority: medium
labels:
  - ui
  - looks
  - ux
created: 2026-09-18T02:23:02.036Z
updated: 2026-09-18T17:02:16.947Z
order: w
board: product
---

## Objective

Two related cleanups to the starter Look presets:
1. The monochrome/B&W starter Looks should be grouped together in the picker rather than scattered among color categories.
2. Remove the color-skewed starter Looks (e.g. "Forest Shadow", "Midnight Slate", "Neon Dusk") — they read as gimmicky/off-brand rather than as neutral starting points for a RAW editor.

## Context

- Manifest: `Sources/KromoraKit/Resources/StarterLooks/manifest.json` — each entry has `name`/`category`. Color-skewed entries include `"Neon Dusk"` (Cinematic), `"Midnight Slate"` (Cool-toned), `"Forest Shadow"` (Moody), and there are 4 dedicated `"Monochrome"`-category entries (around lines 8, 80, 98, 116, 134) alongside other categories: Cinematic, Film-inspired, Warm slide-inspired, Pastel, Faded, High-contrast, Cool-toned, Moody.
- Loader/grouping: `Sources/KromoraKit/Models/BundledLookLibrary.swift:38-55` — `categories` groups `looks` by `\.category` into `LUTLibrary.Category`, sorted alphabetically by category name (so "Monochrome" doesn't necessarily sort first or adjacent to anything meaningful — it's just wherever it falls alphabetically).
- UI: `Sources/KromoraKit/Views/LookInspectorView.swift` — `lookList`/`filteredLooks` (~line 100-144), grid rendering `ForEach(looks)` (~line 346), category filtering via `viewModel.library.categories` (~line 114). Category headers currently aren't collapsible/sectioned distinctly (comment at ~line 111-112).

## Acceptance criteria

- [ ] Remove the color-skewed starter Look entries named "Forest" / "Midnight" / "Neon" (and confirm with the user/design any other clearly color-skewed entries in the same spirit, e.g. under Pastel/Cool-toned/Moody categories, before removing beyond the three named) from `manifest.json` and any bundled `.cube`/LUT assets that become orphaned.
- [ ] All remaining monochrome starter Looks are grouped together as a single, clearly-labeled section/category in the Look picker UI, appearing as one contiguous group rather than interleaved with color categories.
- [ ] `BundledLookLibrary` tests (if any cover category counts/names) are updated to match the new manifest.
- [ ] No dangling references to removed Look names elsewhere in the app (recents, favorites, or any saved edit that referenced them by name/id should fail gracefully, not crash).

## Out of scope

- Adding new starter Looks — this ticket only reorganizes/removes existing ones.

## Agent log

- 2026-09-18T17:02:16.945Z: Removed Neon Dusk, Midnight Slate, and Forest Shadow plus orphaned LUT assets; grouped starter Look categories with Monochrome first and a labeled category section in the picker; updated manifest tests and docs. Verification: manifest/assets consistency, Swift parser checks, git diff --check, and dg validate pass. BundledLookTests could not run because the existing unrelated ResolutionPlanner.swift compile error (missing roi) stops package compilation.
