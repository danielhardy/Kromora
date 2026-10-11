---
id: KRMA-857
title: Test mask analysis status presentation (status bar) and absence of panel banner
type: task
status: done
priority: low
agent: codex
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:08:34.933Z
updated: 2026-10-11T13:11:10.564Z
depends_on:
  - KRMA-850
blockers: []
order: zzzzh
board: product
---

## Objective

KRMA-850 moved the "Mask analysis unavailable/failed" message from the Masks inspector panel to the status bar (`MaskActivityIndicator` in Sources/KromoraKit/Views/StatusBar.swift). It has no test, and the panel/status bar split is exactly the kind of thing that regresses silently (the banner reflowing the panel was the original bug).

## Acceptance criteria

1. Extract the state-to-presentation mapping into a small value type (for example `MaskStatusPresentation(state:)` returning none / loading / failure(message)) that the view renders; no view-structure assertions on source text.
2. Unit tests: `.idle`, `.ready`, `.empty` map to none; `.loading` maps to loading; `.unavailable(m)` and `.failed(m)` map to failure carrying `m`.
3. A masking-panel test asserts that for `.unavailable`/`.failed` the inspector's `renderStatus` contributes no banner (via an observable model property rather than source text).
4. The failure presentation exposes an accessibility label containing the full message and a retry action that calls `retryMaskAnalysis` (assert with a spy).
5. Runs in the `fast` lane.

Related: KRMA-850.


### Comment — claude @ 2026-10-11T13:11:10.137Z

Closing as won't-do: low-value test hardening for shipped KRMA-850 behavior; no MaskStatusPresentation type exists. Reopen if the status bar split regresses.
