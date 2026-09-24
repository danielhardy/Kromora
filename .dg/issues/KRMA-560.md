---
id: KRMA-560
title: Match the trailing toolbar cluster to the rest of the horizontal bar
type: bug
status: ready
priority: medium
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - ui
  - chrome
  - library
created: 2026-09-24T00:35:41.566Z
updated: 2026-09-24T00:35:53.989Z
blockers: []
order: h
board: product
context:
  files:
    - Sources/KromoraKit/Views/ContentView.swift
    - Sources/KromoraKit/Views/KromoraTheme.swift
    - Sources/KromoraKit/Views/CullingBarView.swift
    - Sources/KromoraKit/Views/LibraryGridView.swift
  issues:
    - KRMA-513
  commands:
    - swift build
    - scripts/ci-tests.sh fast
---

## Objective

In Library, the circled trailing end of the window toolbar does not share the surface of the rest of that horizontal bar. Make that region use the same surface as the rest of the bar.

## What the screenshot shows

Library, dark appearance, two photos. The window toolbar is one horizontal bar: traffic lights, the centered Library / Edit control, then a trailing cluster (source browser, zoom, Auto, comparison, inspector, reset, import with a count badge, export). A red circle marks that trailing cluster and the strip of bar directly under it, just left of Delete on the culling row.

The open length of the bar, including the Library / Edit control, reads as one surface. The circled region reads as a different one.

## Scope

The toolbar is `ContentView.toolbarContent`, placed in `ToolbarItemGroup(placement: .primaryAction)`, with `.toolbarBackground(.visible, for: .windowToolbar)`. `KromoraTheme` already requires one full-width native toolbar material and forbids a custom fill on that bar. KRMA-513 kept that band continuous across the inspector. This ticket is the trailing cluster on that same bar, not a new inspector seam.

Library and Edit share this toolbar, so both should show one surface. Do not restyle culling controls, Delete, or the photo grid unless the mismatch is actually the culling row: `CullingBarView` paints `KromoraTheme.secondaryChrome`, while the Delete button beside it sits on the grid's `windowBackground`. If that sibling region is the circled break, make the culling row one surface and leave the native toolbar alone.

## Acceptance criteria

- [ ] In Library, the circled trailing toolbar region uses the same surface as the rest of the horizontal bar. No second plate, material, or color break behind that cluster.
- [ ] Edit shows the same continuous bar.
- [ ] With the inspector open, the toolbar still spans the full window width as one band (KRMA-513).
- [ ] Culling controls, Delete, and the photo grid keep their current roles. Their surfaces change only if the shared culling-row surface is the actual fix.
- [ ] `swift build` succeeds and `scripts/ci-tests.sh fast` passes.

![Library window with the trailing toolbar cluster circled](../assets/KRMA-560/composer-annotation-4cf4d92f-76cb-4453-8b23-254192d97b2f.png)
