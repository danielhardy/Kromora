---
id: LUMO-250
title: "Settings: reveal edit database in Finder"
type: task
status: backlog
priority: medium
labels:
  - persistence
  - ui
created: 2026-09-06T04:19:30.857Z
updated: 2026-09-06T04:19:32.150Z
depends_on:
  - LUMO-244
  - LUMO-246
order: zzzzzv
board: product
---

## Objective

Add a Settings action to reveal the SwiftData edit database in Finder, for backup/support
purposes.

## Context

See the epic body ([[LUMO-244]]) for shared constraints. Once Child 2 ([[LUMO-246]]) lands
`EditDocumentStore.makeContainer(url:)` writing to
`~/Library/Application Support/Lumo/EditStore.store`, that path is a plain file on disk — the
cheapest way to let a user back it up or attach it to a support request is to just show it to them
in Finder, not build a dedicated export/dump pipeline.

## Work

- Add a "Reveal Edit Database in Finder" (or similarly named) action to the app's Settings.
- Wire it to `NSWorkspace.shared.activateFileViewerSelecting([url])` (or equivalent) pointed at the
  `EditStore.store` URL used by `EditDocumentStore.makeContainer(url:)`.
- Handle the case where the store fell back to an in-memory container (Child 2's resilience path)
  — disable or hide the action, since there is no file to reveal.

## Acceptance criteria

- [ ] Settings exposes an action that opens Finder with `EditStore.store` selected.
- [ ] The action is disabled/hidden when the store is running in-memory (no on-disk file).
- [ ] No new export/serialization code path added — this only surfaces the existing on-disk file.
- [ ] Zero Swift 6 concurrency diagnostics, zero opt-outs.

## Depends on

Child 2 ([[LUMO-246]]).
