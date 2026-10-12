---
id: KRMA-913
title: "Library facet sidebar: dual-thumb range slider, wider animated sidebar, and filmstrip filter popover"
type: task
status: backlog
priority: medium
agent: claude
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - library
  - facets
  - ui
created: 2026-10-12T17:27:13.446Z
updated: 2026-10-12T17:28:13.577Z
blockers: []
order: zzzz
board: product
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/Views/LibraryFacetSidebar.swift
      access: write
      confidence: 1
---

## Objective

Improve the Library metadata-filter sidebar: a proper two-thumb range control, a sidebar wide enough for its content that slides in and out, and a way to reach the filters from the compact filmstrip.

## Context

The range facets (for example aperture, ISO, focal length) used two stacked sliders, which is awkward for choosing an inclusive range. The sidebar was 240 pt wide and appeared and disappeared without animation, and the compact filmstrip, which has no sidebar, had no access to the metadata filters.

Note for the verifier: this working-tree change was written by the project owner (or another session), not by the implementer. The implementer reviewed the diff and built it, but has not run the UI.

## Work done

- `LibraryFacetSidebar.swift`: `RangeSlider`, a private two-thumb inclusive range control that calls `onCommit` when a drag ends or an accessibility adjustment is made; replaces the two stacked `Slider`s. Width 240 -> 280. `viewModel` is now `@ObservedObject`.
- `LibraryGridView.swift`: the sidebar and its divider slide in from the trailing edge with a 0.25 s smooth animation, clipped to the grid.
- `CullingBarView.swift`: in the compact (filmstrip) layout of a windowed portable library, the Filter label becomes a button that opens the facet sidebar in a popover; the icon fills and uses the accent colour while any facet is active.

## Acceptance criteria

- Dragging either thumb changes the range label live and runs the query only when the drag ends.
- VoiceOver can adjust each thumb (labelled "Minimum <facet>" / "Maximum <facet>") and each adjustment commits.
- The sidebar slides in and out without layout jumps in the grid.
- In the filmstrip layout the Filter button opens the facets in a popover and shows an active state when facets are set.
- Reduce Motion is respected for the slide animation (not verified).

## Verification notes

- Checks run: `swift build` (clean). No UI test exists for `RangeSlider`, and the UI was not exercised manually by the implementer; the verifier should drive it (display-bound).
- Open question for the verifier: `LibraryFacetSidebar` switched to `@ObservedObject`; confirm that is consistent with how `AppViewModel` is observed elsewhere in this module.
