---
id: LUMO-247
title: Update EditDocumentStore callers (AppViewModel, ExportCoordinator)
type: task
status: backlog
priority: medium
labels:
  - persistence
created: 2026-09-06T04:06:25.910Z
updated: 2026-09-06T04:06:37.567Z
depends_on:
  - LUMO-244
  - LUMO-246
order: zzzzz
board: product
---

## Objective

Update `EditDocumentStore` callers for the new SwiftData-backed initializer.

## Context

See the epic body for shared constraints. Child 2 rewrites `EditDocumentStore` as a `@ModelActor`
with a throwing initializer; this ticket is the mechanical fan-out to callers.

## Work

- `AppViewModel.swift` (lines ~627/633/638/652) — replace `EditDocumentStore(fileURL:)`
  construction with the new (throwing) initializer, using the same fallback-to-in-memory policy on
  failure rather than a fatal error.
- `ExportCoordinator.swift` (~68/74/83/629) — mechanical constructor/type adjustments only, no
  behavioral change.

## Acceptance criteria

- [ ] `AppViewModel` constructs the SwiftData-backed store and falls back to an in-memory store on
      failure, matching today's "never crash, degrade to neutral edits" behavior.
- [ ] `ExportCoordinator` compiles against the new store type with no behavioral change.
- [ ] Zero Swift 6 concurrency diagnostics, zero opt-outs.

## Depends on

Child 2.
