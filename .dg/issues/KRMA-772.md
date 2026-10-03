---
id: KRMA-772
title: "KRMA-762 follow-up: cover relaunch cache invalidation cases"
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Relaunch cases for changed edit, replaced source bytes, different pixel epoch
      result: pass
      notes: Seed now uses the real complete signature; each case asserts via FrameClassifier that exactly one input differs from the exact seed.
    - criterion: Prior frame not treated as exact; exact render counts
      result: pass
      notes: Preview and edited-thumbnail counts asserted exactly 1 for edit/source cases; epoch case asserts preview 1 and thumbnail 0; new unchanged-seed control asserts 0 renders.
    - criterion: Unchanged relaunch and cold control intact; two unedited photos asserted
      result: pass
    - criterion: "Presentation diagnostics: no premature embedded/original candidate"
      result: pass
      notes: Non-strict XCTExpectFailure tagged KRMA-763/765.
    - criterion: Test-only epoch seam if needed
      result: pass
      notes: None needed; epoch varied via frame metadata.
    - criterion: Serial lane under 20s
      result: pass
      notes: 5 tests in 4.5s.
    - criterion: Run RelaunchParityTests, ci-tests fast, ci-tests serial
      result: pass
  checks_run:
    - swift test --no-parallel --filter RelaunchParityTests (5 passed, 4.5s)
    - scripts/ci-tests.sh fast (1478 tests completed)
    - scripts/ci-tests.sh serial (464 passed, 0 failures)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-02T17:31:33.441Z
  session: 01MUR8IPY0L5OJ7RCP
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - cache
  - testing
  - performance
created: 2026-10-02T16:16:46.286Z
updated: 2026-10-02T17:31:33.443Z
blockers: []
order: n
board: product
---

## Objective

Complete the relaunch cache regression coverage identified during KRMA-762 verification, so persisted frames are reused only when every relevant input still matches.

## Context

KRMA-762 added the two-session relaunch harness, but verification found that none of the three required negative cases is present. Without them, the test cannot catch a future cache implementation that incorrectly reuses a frame after its edit, source bytes, or rendering epoch changes. The broader presentation-budget work in KRMA-770 overlaps edit and epoch changes, but does not cover this focused relaunch invalidation contract or replaced source bytes.

The existing harness is `Tests/KromoraKitTests/RelaunchParityTests.swift`; `RenderPipeline.pixelEpoch` is currently static in `Sources/KromoraKit/Models/RenderPipeline.swift`. Keep any epoch injection seam limited to the test boundary and document why it is needed. Preserve the existing no-production-behavior-change requirement.

## Acceptance criteria

- [ ] Add relaunch cases for (a) an edit changed between sessions, (b) source file bytes replaced between sessions, and (c) a different pixel epoch between sessions.
- [ ] For each changed input, prove the prior frame is not treated as exact: the relevant preview and/or edited thumbnail is rendered exactly once and the settled frame refines exactly once, with no repeated render or refinement.
- [ ] Keep the unchanged-input relaunch case and its cold control intact; assert the two unedited photos as well as the edited photos.
- [ ] Assert through presentation-session diagnostics that no embedded-JPEG or original-thumbnail candidate is published before the confirmed frame.
- [ ] If an epoch seam is necessary, add the smallest test-only injection seam at the production boundary, with a code comment explaining why; do not change normal production behavior.
- [ ] Keep the test in the serial lane and under 20 seconds. Remove or update `XCTExpectFailure` wrappers only for assertions fixed by the relevant KRMA-763–KRMA-766 work, and make wrapper comments identify all applicable tickets.
- [ ] Run `swift test --no-parallel --filter RelaunchParityTests`, `scripts/ci-tests.sh fast`, and `scripts/ci-tests.sh serial`; record results and hand off for verification.

## Implementation notes

Follow-up to the blocker and minor findings in [KRMA-762](KRMA-762.md). Do not open additional child tickets for this scope. Do not run display-bound captures. Keep Swift 6 mode free of escape hatches, preserve unrelated working-tree changes, and commit with a subject beginning `KRMA-772:`.

Related work: KRMA-763 through KRMA-766 fix the positive relaunch behavior; KRMA-770 adds broader presentation-change budgets.

### Comment — codex @ 2026-10-02T16:38:08.160Z

Added relaunch invalidation coverage for changed edits, replaced source bytes, and older pixel epochs. Expanded unchanged relaunch assertions to cover both unedited photos and retained the cold control. Presentation-session diagnostics now retain pre-confirmation candidate provenance; expected-failure assertions document the still-reproduced KRMA-763/KRMA-765 behavior. Verification passed: swift test --no-parallel --filter RelaunchParityTests (4 tests, 4.3s), scripts/ci-tests.sh fast (1,478 tests), and scripts/ci-tests.sh serial (463 tests). Commit: 30ac23c.

### Comment — codex @ 2026-10-02T17:09:00.983Z

Fixed the review blocker in commit 2372ab2 (KRMA-772: isolate relaunch cache invalidation inputs). The persisted preview and edited thumbnail seeds now use the real complete signature; changed-edit, replaced-source, and old-pixel-epoch cases each differ from that exact seed in one named input. Added an unchanged-input reuse control and exact render-count assertions. Checks: swift test --no-parallel --filter RelaunchParityTests (5 tests passed); scripts/ci-tests.sh fast (1,478 passed); scripts/ci-tests.sh serial (464 passed). The source-replacement provisional-frame diagnostic remains an expected failure tracked by KRMA-763.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-02T16:39:32.012Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [ ] Add relaunch cases for edit changed, source bytes replaced, different pixel epoch (fail) — Three tests exist but do not isolate the changed input. seedSinglePhotoRelaunch overwrites the persisted frame with FrameFixtures.frame(edit: "prior-session"), whose editHash never matches the real edit. The edit-changed and epoch tests would therefore pass even if the cache ignored edit or epoch changes. The epoch test also differs from the seeded frame in the epoch and in the edit hash.
- [ ] Prove prior frame not treated as exact: preview/thumbnail rendered exactly once, settled frame refines exactly once (fail) — Preview count is asserted ==1, but edited thumbnail count is only asserted >0, never exactly once. The epoch test makes no thumbnail assertion. No unchanged-input contrast shows the same seed would be reused when nothing changes.
- [x] Keep unchanged relaunch case and cold control; assert two unedited photos too (pass) — Preserved; unedited photos asserted under non-strict XCTExpectFailure for KRMA-763/765.
- [x] Assert via presentation-session diagnostics no embedded-JPEG/original-thumbnail candidate before confirmed frame (pass) — provisionalCandidateSources added to the session; assertion present, wrapped in non-strict XCTExpectFailure (KRMA-763).
- [x] Smallest test-only epoch seam if needed (pass) — No seam added; epoch was varied by rewriting frame metadata. Production change is a 4-line diagnostics field only.
- [x] Serial lane, under 20s; XCTExpectFailure wrappers identify tickets (pass) — 4 tests in 4.2s.
- [x] Run RelaunchParityTests, ci-tests fast, ci-tests serial (pass) — RelaunchParityTests re-run: 4 passed, 0 failures. fast and serial lanes not re-run, because the blocker is a test-design flaw they cannot detect; implementer reported 1478 and 463 passing.
Checks run:
- swift test --no-parallel --filter RelaunchParityTests (4 passed, 4.2s)
- Experiment: removed the synthetic seed frame; the first session persists no frame on this tree, so the synthetic frame is the only seed. Experiment reverted.
Findings:
- BLOCKER: Invalidation tests use a seed frame whose edit hash is a fixed placeholder, so each negative case is invalidated regardless of the input under test; they cannot catch a cache that ignores edit, source or epoch changes. Thumbnail 'exactly once' is only asserted >0. Suggested fix: Build the seed frame from the real signature (real edit hash, source identity, look, working space, pixelEpoch) so only one input differs per test; add an unchanged-input control from the same seed that reuses the frame; assert edited-thumbnail count exactly 1 for the changed cases.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUR6T93SH4A18TSE
Summary: Relaunch invalidation tests seed a frame with a placeholder edit hash, so they do not isolate the changed input; thumbnail exactly-once is not asserted.

- 2026-10-02T16:40:12.609Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [ ] Add relaunch cases for edit changed, source bytes replaced, different pixel epoch (fail) — seedSinglePhotoRelaunch (RelaunchParityTests.swift:103-105) writes a frame with placeholder edit hash 'prior-session', so every negative case is invalidated regardless of the input under test; tests would pass even if the cache ignored edit, source or epoch changes.
- [ ] Prove prior frame not treated as exact: rendered exactly once, settled frame refines exactly once (fail) — Edited thumbnail count only asserted >0 (lines 166, 190); epoch test has no thumbnail assertion; no unchanged-input control from the same seed.
- [x] Keep unchanged relaunch case and cold control; assert two unedited photos (pass)
- [x] Presentation-session diagnostics: no embedded-JPEG/original-thumbnail candidate before confirmed frame (pass) — Present under non-strict XCTExpectFailure for KRMA-763.
- [x] Smallest test-only epoch seam if needed (pass)
- [x] Serial lane, under 20s; XCTExpectFailure wrappers identify tickets (pass)
- [x] Run RelaunchParityTests, ci-tests fast, ci-tests serial (pass) — Implementer-reported; tree unchanged since the prior verification, which re-ran RelaunchParityTests (4 passed).
Checks run:
- Re-inspected RelaunchParityTests.swift at HEAD 30ac23c; unchanged since the prior blocker report, defect still present
Findings:
- BLOCKER: Invalidation tests seed a frame with a placeholder edit hash, so they cannot isolate the changed input. Fix: build the seed frame from the real signature (edit hash, source identity, look, working space, pixelEpoch) so only one input differs per test; add an unchanged-input control that reuses the frame; assert edited-thumbnail count exactly 1 for changed cases.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUR6V2G581XMUKCC
Summary: Invalidation tests seed a placeholder-edit-hash frame so they do not isolate the changed input; thumbnail exactly-once not asserted. Implementation needs another pass.

- 2026-10-02T16:42:09.299Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [ ] Add relaunch cases for edit changed, source bytes replaced, different pixel epoch (fail) — seedSinglePhotoRelaunch (RelaunchParityTests.swift:103-105) writes the seed frame with placeholder edit hash prior-session, so every negative case is invalidated regardless of the input under test; the tests would pass even if the cache ignored edit, source or epoch changes.
- [ ] Prove prior frame not treated as exact: rendered exactly once, settled frame refines exactly once (fail) — Edited thumbnail count only asserted >0; epoch test has no thumbnail assertion; no unchanged-input control reusing the same seed.
- [x] Keep unchanged relaunch case and cold control; assert two unedited photos (pass)
- [x] Presentation-session diagnostics: no embedded-JPEG/original-thumbnail candidate before confirmed frame (pass) — Present under non-strict XCTExpectFailure for KRMA-763.
- [x] Smallest test-only epoch seam if needed (pass)
- [x] Serial lane, under 20s; XCTExpectFailure wrappers identify tickets (pass)
- [x] Run RelaunchParityTests, ci-tests fast, ci-tests serial (pass) — Implementer-reported; verified earlier at 4 passed.
Checks run:
- Re-inspected RelaunchParityTests.swift at HEAD 30ac23c; no Tests/ or Sources/ changes since the prior blocker reports, defect still present
Findings:
- BLOCKER: Invalidation tests seed a frame with a placeholder edit hash, so they cannot isolate the changed input. Fix: build the seed frame from the real signature (edit hash, source identity, look, working space, pixelEpoch) so only one input differs per test; add an unchanged-input control reusing the frame; assert edited-thumbnail count exactly 1 for changed cases.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUR6XOU8O3GHR5PX
Summary: Invalidation tests seed a placeholder-edit-hash frame so they do not isolate the changed input; thumbnail exactly-once is not asserted. Implementation needs another pass.

- 2026-10-02T17:31:33.441Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Relaunch cases for changed edit, replaced source bytes, different pixel epoch (pass) — Seed now uses the real complete signature; each case asserts via FrameClassifier that exactly one input differs from the exact seed.
- [x] Prior frame not treated as exact; exact render counts (pass) — Preview and edited-thumbnail counts asserted exactly 1 for edit/source cases; epoch case asserts preview 1 and thumbnail 0; new unchanged-seed control asserts 0 renders.
- [x] Unchanged relaunch and cold control intact; two unedited photos asserted (pass)
- [x] Presentation diagnostics: no premature embedded/original candidate (pass) — Non-strict XCTExpectFailure tagged KRMA-763/765.
- [x] Test-only epoch seam if needed (pass) — None needed; epoch varied via frame metadata.
- [x] Serial lane under 20s (pass) — 5 tests in 4.5s.
- [x] Run RelaunchParityTests, ci-tests fast, ci-tests serial (pass)
Checks run:
- swift test --no-parallel --filter RelaunchParityTests (5 passed, 4.5s)
- scripts/ci-tests.sh fast (1478 tests completed)
- scripts/ci-tests.sh serial (464 passed, 0 failures)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUR8IPY0L5OJ7RCP
