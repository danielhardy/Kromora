---
id: LUMO-259
title: Reveal-in-Finder must handle a not-yet-created store file
type: task
status: backlog
priority: medium
labels:
  - persistence
  - ui
created: 2026-09-07T01:10:25.405Z
updated: 2026-09-07T01:28:01.542Z
depends_on:
  - LUMO-250
order: eeeeeee8
board: product
---

## Objective

The Reveal-in-Finder action must account for a store file that does not exist yet. SwiftData
creates the `.store` file lazily on first write, so a fresh install with no saved edits has a
healthy persistent store and a nil URL is never produced — but there is no file to reveal, and
`activateFileViewerSelecting` with a nonexistent path fails silently or reveals the parent.

## Context

Follow-up to LUMO-250. `onDiskFileURL` returns the *requested* container URL
(`EditDocumentStore.defaultFileURL`), which answers "where would the database live", not "does
it exist". The current `.task` in `LumoSettingsView` treats non-nil as revealable.

## Work

- When resolving the URL for display (whether in the view's `.task` or in the provider from
  LUMO-258), check `FileManager.default.fileExists(atPath:)` and surface "no database yet"
  (same treatment as the in-memory case) when the file is absent.
- Do not force-create the file (no empty write) just to make the button work.

## Acceptance criteria

- [ ] Fresh install, no edits saved: Settings shows the database as not-yet-created (no dead
      Reveal button), rather than targeting a nonexistent path.
- [ ] After the first saved edit, the action appears and reveals `EditStore.store` in Finder.
- [ ] In-memory fallback behavior from LUMO-250 is unchanged.
