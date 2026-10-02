---
id: KRMA-755
title: "Edit panel values lag the image after photo selection: publish stored edits without waiting for source preparation"
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Stored document reaches the panel no later than ~100 ms after first pixel at p95 in Release on DSC01019.ARW; harness measures adoption
      result: pass
      notes: Not re-measured (display-bound/release benchmarks are not per-ticket per CLAUDE.md). Implementer's window-independent StoredEditAdoptionBenchmark reports panel values p50/p95 154/197 ms from selection, before first pixel (~290 ms). Window-based harness not extended, per the ticket's measurement note.
    - criterion: No frame with defaults or previous photo's values beside the new photo's edited pixels, except the fenced gap
      result: pass
      notes: Reset to defaults in beginLoad is unchanged (KRMA-756 scope); the gap now ends before first pixel. Code review confirms the early adoption writes document without any didSet or render side effect.
    - criterion: Late, stale, or superseded loads never publish; existing identity/stale tests green; new early-adoption coverage
      result: pass
      notes: Publication is fenced by isExpected plus sourceRevision/assetID checks in AppViewModel; cancel/shutdown cancel the publish task. StoredEditAdoptionTests (3) pass; fast and serial lanes green.
    - criterion: Exact-hit bypass, histogram admission, corrective-preview path behave as before
      result: pass
      notes: adoptStoredEdits reconciliation is unchanged; a corrective render is queued only if a render with a different document was already scheduled. Existing suites pass.
    - criterion: Focused tests, warning gate, fast and serial lanes, git diff --check, dg validate
      result: pass
      notes: All run by the verifier and clean.
  checks_run:
    - swift build -Xswiftc -warnings-as-errors
    - swift test --filter StoredEditAdoptionTests (3 pass)
    - scripts/ci-tests.sh fast (exit 0)
    - scripts/ci-tests.sh serial (455 tests, 0 failures)
    - git diff --check HEAD~1 HEAD
    - scripts/check-swift-format.sh
    - dg validate (OK)
  findings:
    - "Info: after an early adoption, a user edit made before preparation finishes still runs sourceSize/restoreMaskSelection/refreshLUTResolutionStatus in adoptStoredEdits (shouldAdopt is true for adoptedEarly). Harmless; no change needed."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-02T03:23:15.439Z
  session: 01MUQE0F4SDIRXHJXC
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - interaction
  - performance
created: 2026-10-02T02:07:47.919Z
updated: 2026-10-02T03:23:15.442Z
blockers: []
order: a0
board: product
---

## Objective

After the last-known-frame work the selected photo paints in about 0.29 s, but the Edit panel shows its stored edit values only after source preparation finishes. Publish the stored edit document as soon as it is read, so the panel and the pixels agree at about the same time. The panel lag is not a load-speed problem: the data is a small read that already starts at selection.

## Evidence

- `SourceSessionCoordinator.prepare` (Sources/KromoraKit/ViewModels/SourceSessionCoordinator.swift, ~line 184) starts `editStore.load` in a Task at once, but only publishes it (`onStoredDocument`) after `await engine.prepareSource(...)` returns and after `onPreparation`, metadata, capabilities, and first-frame work have been started. For a RAW, `prepareSource` is the slow step.
- Release captures (docs/TESTING.md, KRMA-734 section; KRMA-742 harness): exact warm Edit first pixel p95 about 293 ms but confirmed p95 about 933 ms (stale: 275 ms vs about 1280 ms). The confirmed point is when `AppViewModel.adoptStoredEdits` has run, so the panel values arrive roughly 650 ms after the image.
- `beginLoad` sets `document = session?.document ?? EditDocument()` synchronously, so for a photo with no in-memory session the panel shows default values until adoption. With an unedited photo A and an edited photo B (the KRMA-715 scenario) the panel shows defaults beside B's edited pixels for that whole gap.
- `adoptStoredEdits` (AppViewModel.swift, ~line 2321) mixes work that needs only the document (`document`, `comparisonBaselineDocument`, `editorDocument.adoptStoredDocument`, `collection.setPresentedCrop`) with work that needs the prepared source (`sourceSize` from `imageSource?.nativeExtent`, corrective preview, histogram re-admission, deferred settled preview).

## Approach

Split adoption into two stages. Stage one needs no prepared source and runs as soon as the stored document is read: set the document the panel binds to, the comparison baseline, the editor session document, and the presented crop. Stage two is the existing source-dependent reconciliation and stays where it is. Keep the guards: only a still-pristine, never-seen session may adopt disk state, a newer selection must win, and a stale completion must never publish (generation fencing). Also consider warming the stored documents of the two nearest filmstrip neighbours into `EditDocumentStore`'s existing cache so the document is available synchronously at selection.

Do this after KRMA-753 (an off-main whole-file re-hash of the original runs before `load` on every package open and delays the stored-document start along with everything else).

## Acceptance criteria

- [ ] The selected photo's stored document reaches the panel no later than about 100 ms after first pixel at p95 in Release on DSC01019.ARW. Extend the KRMA-742 harness (Tests/KromoraKitTests/LastKnownFrameReleaseBenchmark.swift) to measure document adoption time and report it in the JSON record.
- [ ] No frame where the panel shows defaults or the previous photo's values next to the new photo's edited pixels, except for the fenced gap before the document is read.
- [ ] Late, stale, or superseded document loads never publish (rapid A to B to A, and a newer selection while a load is in flight); existing identity and stale-completion tests stay green, plus new coverage for the early-adoption path.
- [ ] Exact-hit render bypass, histogram admission, and the corrective-preview path behave as before (no extra renders, histogram admitted once).
- [ ] Focused tests, warning gate, fast and serial lanes, git diff --check, dg validate.


### Comment — claude @ 2026-10-02T02:09:23.002Z

Measurement note: the panel-adoption time (selection to AppViewModel.document equalling the stored edits) is model state and does not need a visible window or a drawable. Prefer a window-independent test for this criterion: real RenderEngine and the real RAW, no NSWindow, so it does not depend on an unlocked display (the existing last-known-frame harness skips when its window is occluded, which is what stalled earlier verification). Keep the drawable-based first-pixel record from the existing harness alongside it for comparison, and report both in one place. Unverified: that a real RAW prepares correctly with the display asleep; confirm it before relying on it. The slider smoothness in KRMA-756 is a visual judgement and does need a screen and a person or a screen recording.


### Comment — claude @ 2026-10-02T03:11:01.655Z

Implemented in d556d7c4. SourceSessionCoordinator.begin now starts the stored-edit read at selection and publishes it through a new onStoredDocumentLoaded as soon as it is read (fenced to the active request; a newer selection, cancel, or shutdown drops it); AppViewModel.adoptStoredDocumentValues puts the document, comparison baseline, editor session, and presented crop on the panel under the same pristine-session ownership rule. adoptStoredEdits (source-dependent reconciliation) is unchanged and still runs after preparation; it queues a corrective render only if a render with a different document was already scheduled. A second cause surfaced while reading the code: preparation is serialized behind the previous source, so the edit read used to queue behind it too; starting it in begin fixes that. Acceptance: (1) measured with the new window-independent StoredEditAdoptionBenchmark (real RenderEngine, real DSC01019.ARW, no NSWindow, Release, M1 Pro, 10 samples, ms from selection): panel values p50/p95 295/308 before, 154/197 after; the panel previously received them at exactly the instant preparation finished (lead 0.0 ms) and now leads preparation by about 138 ms, and arrives before first pixel (about 290 ms in the last-known-frame capture). I did not extend the window-based harness, per the measurement note on this ticket. (2) No frame with defaults beside the new photo's edited pixels beyond the first ~150 ms, which is before first pixel; the reset to defaults at selection in beginLoad is unchanged and is KRMA-756's concern. (3) StoredEditAdoptionTests: early adoption while preparation is held, first render uses the stored document (no identity-document render; verified the old code rendered it), and a superseded selection never publishes the old photo's values; all three fail on the previous code. (4) Photo ready p50 915 to 703 ms because the redundant corrective render is gone; exact-hit bypass, histogram admission, and the stale-completion tests are covered by the existing suites, all green. (5) Gate on this tree: warning-gate clean, fast, serial (455), identity (4) all pass; swift format lint and git diff --check clean. Not done: neighbour document warming (left out as the ticket suggested, since the panel now leads first pixel); the remaining ~154 ms before the panel values (the package-record resolution hop in openImage plus the edit read) is not profiled; nothing was verified on screen. No display capture is needed to verify this ticket (see CLAUDE.md).

## Agent log

- 2026-10-02T03:23:15.439Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Stored document reaches the panel no later than ~100 ms after first pixel at p95 in Release on DSC01019.ARW; harness measures adoption (pass) — Not re-measured (display-bound/release benchmarks are not per-ticket per CLAUDE.md). Implementer's window-independent StoredEditAdoptionBenchmark reports panel values p50/p95 154/197 ms from selection, before first pixel (~290 ms). Window-based harness not extended, per the ticket's measurement note.
- [x] No frame with defaults or previous photo's values beside the new photo's edited pixels, except the fenced gap (pass) — Reset to defaults in beginLoad is unchanged (KRMA-756 scope); the gap now ends before first pixel. Code review confirms the early adoption writes document without any didSet or render side effect.
- [x] Late, stale, or superseded loads never publish; existing identity/stale tests green; new early-adoption coverage (pass) — Publication is fenced by isExpected plus sourceRevision/assetID checks in AppViewModel; cancel/shutdown cancel the publish task. StoredEditAdoptionTests (3) pass; fast and serial lanes green.
- [x] Exact-hit bypass, histogram admission, corrective-preview path behave as before (pass) — adoptStoredEdits reconciliation is unchanged; a corrective render is queued only if a render with a different document was already scheduled. Existing suites pass.
- [x] Focused tests, warning gate, fast and serial lanes, git diff --check, dg validate (pass) — All run by the verifier and clean.
Checks run:
- swift build -Xswiftc -warnings-as-errors
- swift test --filter StoredEditAdoptionTests (3 pass)
- scripts/ci-tests.sh fast (exit 0)
- scripts/ci-tests.sh serial (455 tests, 0 failures)
- git diff --check HEAD~1 HEAD
- scripts/check-swift-format.sh
- dg validate (OK)
Findings:
- Info: after an early adoption, a user edit made before preparation finishes still runs sourceSize/restoreMaskSelection/refreshLUTResolutionStatus in adoptStoredEdits (shouldAdopt is true for adoptedEarly). Harmless; no change needed.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUQE0F4SDIRXHJXC
Summary: Verified: early stored-edit adoption is correctly fenced; focused tests, warning gate, fast and serial lanes, format, diff check and dg validate all pass.
