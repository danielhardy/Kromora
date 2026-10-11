---
id: KRMA-869
title: Instrument the Library to Edit photo switch and chase the main-actor stall (KRMA-860)
type: task
status: done
priority: high
agent: claude
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A capture of Library -> Edit shows the phase timeline above.
      result: pass
      notes: Reviewed the recorded real Library-to-Edit capture in the issue comments and docs/TESTING.md. It includes selection, load-prefix substeps, source preparation, and first-pixel timings.
    - criterion: The dominant phase is identified and either fixed or documented with a reason.
      result: pass
      notes: "The timeline identified whole-file SHA-256 hashing on the main actor as the cause. KRMA-860 records the fixes and post-fix evidence: selectionSyncReturned fell from about 101 ms to 2.8 ms in the dev capture, with no wholeFileRehash on the main thread."
    - criterion: "Related: KRMA-860, KRMA-863."
      result: pass
      notes: Reviewed the recorded cross-ticket results; this issue adds the phase evidence and the related issues document the fixes.
  checks_run:
    - Independent review of commits fa5e504fe7ac7ebcf86851620e3dc4ac1aced006 and f9add390ae9df09318f3c58f931554cb1b64b127, including privacy of logged details, clock alignment, call-site coverage, and instrumentation overhead.
    - "swift test --filter ObservabilityTests: exit 0; 7 tests passed, 0 failures."
    - Reviewed the post-fix capture summary in docs/TESTING.md and the KRMA-869 issue comments. No display-bound benchmark was run during verification.
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T01:46:14.065Z
  session: 01MV35UO8V9RP6PE4B
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T19:55:09.553Z
updated: 2026-10-11T01:46:14.069Z
blockers: []
order: zq
board: product
commits:
  - fa5e504fe7ac7ebcf86851620e3dc4ac1aced006
  - f9add390ae9df09318f3c58f931554cb1b64b127
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


### Comment — claude @ 2026-10-10T19:58:28.312Z

First capture (dev/debug build, three Library->Edit switches). Phases in ms since selection: selectPortableItem 50.8, loadSyncPrefix 100.8, selectionSyncReturned 100.9 (two blocks of almost exactly 50 ms each, looks like a blocking wait, not compute); beginLoadScheduled 520.5, i.e. about 420 ms of main-thread work between the synchronous return and the first Task.yield resuming (SwiftUI view transition); beginLoad itself is fast (about 2 ms through beginLoadSyncEnd); sourcePrepared +583 ms; sourceInstalled +100; storedDocumentLoaded +133; metadataPublished +100; capabilitiesPublished +288; stored-frame firstPixel/confirmed only at 1954 ms and 1313 ms (the first switch showed an original-thumbnail firstPixel at 617 ms and confirmed at 677 ms). Follow-up f9add390ae9df09318f3c58f931554cb1b64b127 logs the individual steps inside the two 50 ms blocks.


### Comment — claude @ 2026-10-10T21:13:52.859Z

Result of the KRMA-860 fixes as seen in the photo-switch timeline: first pixel for a Library to Edit switch went from about 1.3-1.95 s to 74-205 ms and the synchronous main-actor span from about 100 ms to under 3 ms. Remaining items: the off-main whole-file rehash in source preparation (about 50-60 ms of the 131-180 ms sourcePrepared) and the rendered confirmation at about 610-640 ms.


### Comment — claude @ 2026-10-11T01:13:16.753Z

Handoff to verification (implementer: claude; reporter has reviewed). Commits fa5e504f, f9add390. Instrumentation only, no behavior change: PhotoSwitchPhase log lines (category photo-switch, plus signposts) with milliseconds since the selection began for each stage of a Library to Edit switch, and per-step timing inside selectPortableItem and the load prefix. It produced the evidence that located the KRMA-860 and KRMA-863 causes, and its results are recorded in the comments on those tickets. Tests: ObservabilityTests vocabulary updated and passing. Check: the diagnostic names are stable, the extra work per switch is negligible, and consider whether the finer-grained step logging should stay or be trimmed now that the cause is fixed.


### Comment — claude @ 2026-10-11T01:13:25.922Z

Commits for KRMA-869 (oldest first; review with git show <sha>):
- fa5e504fe7ac7ebcf86851620e3dc4ac1aced006 KRMA-869: add a phase timeline for the Library to Edit photo switch
- f9add390ae9df09318f3c58f931554cb1b64b127 KRMA-869: time each step of the synchronous selection and load prefix

## Agent log

- 2026-10-11T01:46:14.065Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A capture of Library -> Edit shows the phase timeline above. (pass) — Reviewed the recorded real Library-to-Edit capture in the issue comments and docs/TESTING.md. It includes selection, load-prefix substeps, source preparation, and first-pixel timings.
- [x] The dominant phase is identified and either fixed or documented with a reason. (pass) — The timeline identified whole-file SHA-256 hashing on the main actor as the cause. KRMA-860 records the fixes and post-fix evidence: selectionSyncReturned fell from about 101 ms to 2.8 ms in the dev capture, with no wholeFileRehash on the main thread.
- [x] Related: KRMA-860, KRMA-863. (pass) — Reviewed the recorded cross-ticket results; this issue adds the phase evidence and the related issues document the fixes.
Checks run:
- Independent review of commits fa5e504fe7ac7ebcf86851620e3dc4ac1aced006 and f9add390ae9df09318f3c58f931554cb1b64b127, including privacy of logged details, clock alignment, call-site coverage, and instrumentation overhead.
- swift test --filter ObservabilityTests: exit 0; 7 tests passed, 0 failures.
- Reviewed the post-fix capture summary in docs/TESTING.md and the KRMA-869 issue comments. No display-bound benchmark was run during verification.
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV35UO8V9RP6PE4B
Summary: Verification passed; phase timeline and post-fix evidence reviewed, focused observability tests pass.
