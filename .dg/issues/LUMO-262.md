---
id: LUMO-262
title: Scope load status to the photo that produced it
type: task
status: ready
priority: low
labels:
  - persistence
  - ui
created: 2026-09-07T01:10:27.053Z
updated: 2026-09-07T04:14:20.285Z
depends_on:
  - LUMO-244
order: x8
board: product
---

## Objective

A load result should report the status produced by *that* load, not whatever sticky status a
previous photo left behind.

## Context

`status` is store-level and sticky: `load(for:)` returns the ambient `status` in every result,
including paths that did nothing actionable. After photo A loads `.corrupt`, opening unrelated
photo B returns `.corrupt` too — the banner/checks downstream cannot tell "this photo's record
is damaged" from "some earlier photo's was". `save` resetting to `.ready` papers over part of
this, but read-only sessions (the common culling case) never save.

## Work

- Track the status transitions within a single `load` call and return that per-load status in
  `EditDocumentLoadResult`, while keeping a separate store-level "worst actionable status" only
  where the UI genuinely needs latch-until-acknowledged behavior. If the UI relies on
  stickiness, say so explicitly per status case (`.relinked` arguably wants to survive until the
  user sees it; `.corrupt` for photo A must not taint photo B).
- `restoreActionableStatus` is the current mechanism — rework or justify it as part of this.

## Acceptance criteria

- [ ] Loading a healthy photo after a corrupt one reports `.ready` (or the healthy photo's own
      outcome), while the corrupt record still reports `.corrupt` on its own loads.
- [ ] Any deliberately sticky banner behavior is covered by a test naming the case.
