---
id: KRMA-869
title: Instrument the Library to Edit photo switch and chase the main-actor stall (KRMA-860)
type: task
status: backlog
priority: high
agent: codex
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T19:55:09.553Z
updated: 2026-10-10T19:55:10.026Z
blockers: []
order: zzzzy
board: product
---

## Objective

Going from the Library grid to Edit still feels slow to the reporter. The 2026-10-10 direct Release capture (docs/TESTING.md, KRMA-860) measured 99 ms on the main actor before the first suspension and a warm-Edit first-pixel p95 of 387 ms (293 ms on 2026-10-01). Instruments is unavailable on this machine (DTServiceHub), so there is no profile of the switch. Add a phase timeline so one real capture shows where the time goes, then fix the largest phase.

## Work done (instrumentation only, no behavior change)

`PhotoSwitchPhase` log lines (subsystem `com.kromora.app`, category `photo-switch`, also signposts), each with `ms` since the selection began, on the same clock as `PresentationFirstPixel`/`Confirmed`:

- `selectPortableItem`, `selectionSyncReturned` (the main-actor span the benchmark reports),
- `loadSyncPrefix`, `beginLoadScheduled` (latency of the first `Task.yield`), `persistenceFlushRequested`, `documentActivated`, `editHistoryRefreshed`, `lutStatusRefreshed`, `thumbnailCandidateBuilt` (which candidate: stored / edited thumbnail / original / none), `beginLoadSyncEnd`,
- `sourcePrepared`, `sourceInstalled`, `previewScheduled`, `storedDocumentLoaded`, `metadataPublished`, `capabilitiesPublished`,
- `firstPixel` (with candidate source) and `confirmed` (with source and frame count).

ObservabilityTests vocabulary updated.

## How to read it

`log stream --predicate 'subsystem == "com.kromora.app" AND category == "photo-switch"'`, then press E or double-click a photo in the Library. A large gap between consecutive phases is the cost. In particular: `selectionSyncReturned` should be about 2 ms and is about 99 ms in the benchmark; a late `firstPixel` with `source=` other than `storedFrame` means the cached frame was not used; a long `sourcePrepared` is source decode.

## Remaining work

Fix the dominant phase from a real capture (KRMA-860 for the synchronous span), and re-measure with `lkf-direct` (docs/TESTING.md) before and after.

## Acceptance criteria

- A capture of Library -> Edit shows the phase timeline above.
- The dominant phase is identified and either fixed or documented with a reason.
- Related: KRMA-860, KRMA-863.
