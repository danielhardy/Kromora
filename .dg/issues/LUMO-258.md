---
id: LUMO-258
title: Shrink the edit-store public surface back to internal
type: task
status: backlog
priority: medium
labels:
  - persistence
created: 2026-09-07T01:10:24.868Z
updated: 2026-09-07T01:11:06.959Z
depends_on:
  - LUMO-250
order: zzzzzzh
board: product
---

## Objective

Revert `EditDocumentStore` (and `AppViewModel.editStore`) to internal visibility. The SwiftData
port made the whole actor `public` solely so `LumoApp` can pass it into `LumoSettingsView`'s
public initializer — but the repo rule (CLAUDE.md: only `ContentView` and `LumoCommands` are
public) exists to keep the app boundary narrow, and a whole persistence actor is far more
surface than Settings needs.

## Context

Working-tree diff (uncommitted, on top of LUMO-246/247/250):

- `EditDocumentStore.swift`: `actor` → `public actor`, plus `var onDiskFileURL` exposed.
- `AppViewModel.swift`: `let editStore` → `public let editStore`.
- `LumoSettingsView.swift` / `LumoApp.swift`: Settings takes the store and reads
  `await editStore.onDiskFileURL` in a `.task`.

Settings only needs one value: the on-disk database URL (or nil). Everything else the public
actor exposes — `save`, `load`, `document`, counters, test seams — becomes callable from the
app target for no reason.

## Work

- Keep `EditDocumentStore` and `AppViewModel.editStore` internal.
- Vend the URL from the already-public `AppViewModel`, e.g.
  `public var editDatabaseURL: URL? { get async }` (or a `@Sendable () async -> URL?`
  provider), and change `LumoSettingsView`'s public initializer to take that instead of the
  store. `URL?` and function types are public; no actor crosses the boundary.
- Alternatively resolve the URL once in `LumoApp` (`.task`) and pass a plain `URL?` into
  Settings — simplest, if live-updating the row when the store degrades mid-session is not
  required (it degrades once at startup today, so it is not).

## Acceptance criteria

- [ ] `EditDocumentStore` is internal again; `AppViewModel.editStore` is internal again.
- [ ] Settings still shows the Reveal action backed by the real on-disk URL / in-memory message.
- [ ] `swift build`, `swift test` pass with zero Swift 6 diagnostics and zero opt-outs.
