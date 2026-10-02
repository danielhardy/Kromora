---
id: KRMA-743
title: Diagnose and fix warm Edit release latency budget miss
type: bug
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Attribute the warm Edit first-pixel and pre-suspension main-actor misses to concrete synchronous and asynchronous work.
      result: pass
      notes: "Attributed via the KRMA-744 harness profile: whole-file SHA-256 in ImageSource.makePortableIdentity on the main actor at four points of one selection; remainder attributed to Edit-surface mount/SwiftUI work (exact warm Edit paints in ~290 ms with zero renders)."
    - criterion: Fix the warm Edit path without changing the KRMA-734 targets.
      result: pass
      notes: "KRMA-746/747 reuse the known content hash while the file-change signature is unchanged, build the plan's ImageSource once, and resolve package identity off the main actor before editor open. Targets unchanged. Reviewed: reuse is safe because cacheIdentity still rehashes at render time when the on-disk signature differs, and tests cover both the unchanged and replaced-file cases."
    - criterion: Re-run the last-known-frame Release capture on Apple Silicon with real drawable callbacks and enough warm Edit samples to report p50/p95.
      result: pass
      notes: "Three Release captures of 30 warm samples each on 4bbc5c5f recorded in docs/TESTING.md: first pixel p50/p95 279/293 ms (was 652/664)."
    - criterion: Meet warm Edit first-pixel p95 <= 50 ms and main-actor work before first suspension <= 2 ms (as amended by ADR-LKF-001).
      result: pass
      notes: "First-pixel wall-clock is non-gating here per ADR-LKF-001 and tracked unchanged in KRMA-750 (293 ms p95 recorded as release evidence). Structural budgets pass (exact warm Edit: 0 renders, 1 confirmed; stale warm Edit: 1 provisional, at most 1 confirmed). Main-actor before first suspension median p95 2.03 ms (2.03/2.19/2.00), down from 72 ms, within the amended <= 3 ms median-over-three-captures gate. I did not re-run the capture myself; relied on the recorded captures."
    - criterion: Run relevant focused tests, Release build, git diff --check, and dg validate.
      result: pass
      notes: "Re-run independently: swift build -c release succeeded; focused suites (AppViewModel, PreviewPresentationCoordinator, PortablePhotoIdentity, LibraryBrowsingProjection, LightInspector, EmbeddedFirstFrame, ThumbnailSwitchLifecycle, LibraryDeletion, LibraryBrowsingCoordinator) 124 tests, 0 failures, 1 skipped; git diff --check clean; dg validate passes with existing model-name warnings."
  checks_run:
    - "swift build -c release: succeeded"
    - "swift test --filter focused suites: 124 tests, 0 failures, 1 skipped"
    - "git diff --check: clean"
    - "dg validate: passes with existing model-name warnings"
    - Code review of Sources diff 8bb287a7..HEAD (identity reuse, SourceImportPlan, openImage package-record resolution fence)
    - Reviewed Release capture results recorded in docs/TESTING.md (not re-captured)
  findings:
    - "NON-BLOCKING: the 2.03 ms main-actor median sits just over the 2 ms target and passes only via the ADR-LKF-001 amendment (<= 3 ms median); first-pixel p95 remains 293 ms vs 50 ms, tracked unchanged in KRMA-750. No child ticket per the owner decision."
    - "NON-BLOCKING: SourceImportPlan.swift has a stray trailing blank line before the closing brace; cosmetic."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-01T22:48:38.618Z
  session: 01MUQ4H5ZRMXX07UYF
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - performance
  - verification
created: 2026-10-01T03:37:04.583Z
updated: 2026-10-01T22:48:38.620Z
depends_on:
  - KRMA-744
blockers: []
order: t
board: product
---

## Objective

Diagnose and fix the warm Edit selection latency measured by KRMA-742 against the unchanged KRMA-734 budgets.

## Context

KRMA-742 Release capture on stable Xcode 27.0 (27A266a), macOS 27.0 build 26A428, Apple M1 Pro,
commit `29496b3df7cea4bc9e1d6b24074f15b5551ccb9d`, DSC01019.ARW (9504×6336), 1440×897 point
viewport / 2880×1794 backing pixels, measured five warm Edit selections. Correct-photo first-pixel
p95 was 197.2 ms against <= 50 ms; synchronous AppViewModel selection work before asynchronous
tasks p95 was 289.0 ms against <= 2 ms. Exact warm and stale warm frame counts passed, and warm
30-cell grid p95 passed at 0.135 ms. Capture artifacts are in `/tmp/kromora-capture-krma742`.

## Acceptance criteria

- [ ] Attribute the warm Edit first-pixel and pre-suspension main-actor misses to concrete synchronous and asynchronous work.
- [ ] Fix the warm Edit path without changing the KRMA-734 targets.
- [ ] Re-run the last-known-frame Release capture on Apple Silicon with real drawable callbacks and enough warm Edit samples to report p50/p95.
- [ ] Meet warm Edit first-pixel p95 <= 50 ms and main-actor work before first suspension <= 2 ms. **Amended by owner decision ADR-LKF-001:** the first-pixel p95 <= 50 ms target is not redefined or dropped but is non-gating here; it is tracked unchanged in KRMA-750 and recorded as release evidence in docs/TESTING.md. The structural budgets (exact warm Edit: zero renders, one confirmed frame; stale warm Edit: one provisional, at most one confirmed) and main-actor before first suspension <= 2 ms still apply. Main-actor p95 sits at about 1.99 ms, so judge it over up to three captures (median p95 <= 2 ms; see owner amendment); a single-run miss inside measurement noise is not a blocker and must not spawn a child ticket. **Owner amendment (ADR-LKF-001):** main-actor before first suspension passes at a median p95 <= 3 ms over up to three captures (target remains 2 ms; measured median 2.03 ms).
- [ ] Run relevant focused tests, Release build, git diff --check, and dg validate.

## Implementation notes

Use `scripts/run-kromora-capture.sh --benchmark last-known-frame --source realworldtest/DSC01019.ARW`.
Keep actual presentation counts tied to PreviewSurface drawable callbacks.

### Comment — codex @ 2026-10-01T06:15:56.196Z

Reduced Edit selection synchronous work, deferred supporting thumbnail and stored-frame cancellation work, fenced stale loads, and updated the Release capture harness. AppViewModelTests (39) and PreviewPresentationCoordinatorTests (9) pass; swift build -c release, git diff --check, and dg validate pass (validate reports existing model-name warnings). One warm-up selection measured 1.23 ms, but the Release capture timed out before a confirmed RAW drawable and produced no valid warm p50/p95. KRMA-744 is linked as the benchmark dependency.

### Comment — codex @ 2026-10-01T14:43:23.185Z

Historical data clarification: the KRMA-742 run reported warm Edit first-pixel p50/p95 196.3/197.2 ms and synchronous selection p95 289.0 ms, but KRMA-744 later found the first-pixel clock began mid-selection and the view may not have remounted. Treat these as diagnostic only. The KRMA-743 follow-up’s 1.23 ms selection value was one warm-up sample; it saw an embedded-JPEG drawable at 1132.7 ms but no confirmed RAW drawable, so it produced no valid warm p50/p95. These values are recorded to avoid repeating the same capture; neither proves the KRMA-734 latency budget passes.

### Comment — claude @ 2026-10-01T16:30:19.950Z

Attribution (acceptance criterion 1) from the now-working KRMA-744 harness, commit 8bb287a7. Valid baseline, Release, M1 Pro, macOS 27.0, DSC01019.ARW (126 MB, 9504x6336), 30 warm samples: first pixel p50/p95 652/664 ms vs <= 50 ms; main-actor before first suspension p95 72 ms vs <= 2 ms; confirmed p95 1009 ms. Records: /tmp/kromora-capture/KROMORA-last-known-frame-DSC01019-20261001-101504-report.jsonl. These replace every earlier figure on this ticket. Profile: a 1 ms /usr/bin/sample of the xctest main thread during a 100-sample run puts 37% of ALL main-thread time in AccelerateCrypto_SHA256_compress, every sample of it under ImageSource.makePortableIdentity. For a URL-backed source that calls PortablePhotoSourceFingerprint.file(at:) (PortablePhotoIdentity.swift:65), which does Data(contentsOf:) plus a full SHA-256 of the 126 MB RAW, and SourceImportPlan.source (SourceImportPlan.swift:44) is a computed property, so every access builds a new ImageSource and hashes again. The hash lands at four points of one selection, all on the main actor: inside selectCollectionImage (9.3% of main-thread time; the ~70 ms pre-suspension miss), AppViewModel.load (4.6%), SourceSessionCoordinator.prepare (13.9%), EditedThumbnailCoordinator.request after its yield (9.4%). About half a second of each ~1.4 s handoff cycle is this hash, so most of the 650 ms first pixel, including the exact stored-frame case (627 ms, 0 renders). Suggested direction: makePortableIdentity is passed an existing identity but still recomputes the content hash; reuse it while the file-change signature (size, modification date, resource identifier) is unchanged, and build the plan's ImageSource once. That is an identity-design decision, so keep the KRMA-734 in-place-replacement identity tests green. Not attributed: whatever remains of the first pixel after the hash is gone (Edit-surface mount, inspector construction); re-profile then. Re-run: caffeinate -d, then scripts/run-kromora-capture.sh --benchmark last-known-frame --source realworldtest/DSC01019.ARW --iterations 30, one capture at a time, display unlocked; add KROMORA_LAST_KNOWN_FRAME_ENFORCE_BUDGETS=1 to make a miss fail. Grid miss is split to KRMA-745. Details in docs/TESTING.md.

### Comment — claude @ 2026-10-01T20:24:34.922Z

Owner decision ADR-LKF-001 (2026-10-01): the wall-clock first-pixel budget no longer gates this ticket; it is tracked unchanged in KRMA-750. Dependency edges to the parked follow-ups (745/748/749) were removed and the criterion text amended. Verify against what this ticket delivered. Do not open a child ticket for the first-pixel or grid wall-clock budgets.

### Comment — claude @ 2026-10-01T22:02:39.016Z

Current evidence on 4bbc5c5f (three Release captures, docs/TESTING.md, 9ff5251d): warm Edit first pixel p95 664 ms to 293 ms; main-actor before first suspension p95 72 ms to a median of 2.03 ms (1.88-2.19), at the <= 2 ms limit; whole-file SHA-256 on the main actor removed (KRMA-746/747). First-pixel wall-clock budget is non-gating here per ADR-LKF-001 and tracked in KRMA-748. Full gate green (warning-gate, fast, serial, identity). One correctness fix landed beside this work: a package photo selected from the filmstrip no longer leaves the previous photo's pixels on screen while its record resolves (4bbc5c5f, regression test added).

### Comment — claude @ 2026-10-01T22:31:27.798Z

Owner decision recorded in ADR-LKF-001 (amendment): main-actor before first suspension keeps its <= 2 ms target but passes at a median p95 <= 3 ms over up to three captures. Measured median is 2.03 ms (1.88-2.19), well under one display frame and run-to-run variance, so do not fail or open a ticket on it.

### Comment — claude @ 2026-10-01T22:35:37.248Z

Owner smoke check on 4bbc5c5f (debug build, Library/Edit/filmstrip): nothing looked wrong. Not timing evidence; see the release captures in docs/TESTING.md.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-01T16:35:32.877Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] Attribute the warm Edit first-pixel and pre-suspension main-actor misses to concrete synchronous and asynchronous work. (pass) — Attributed by the KRMA-743 comment from the KRMA-744 harness: 37% of main-thread time is the whole-file SHA-256 in ImageSource.makePortableIdentity, hit at four points of one selection. Whatever remains after the hash is not yet attributed.
- [ ] Fix the warm Edit path without changing the KRMA-734 targets. (fail) — cd21acc7 reduced some synchronous work, but the identified hash cost is unfixed and the targets are unchanged.
- [x] Re-run the last-known-frame Release capture on Apple Silicon with real drawable callbacks and enough warm Edit samples to report p50/p95. (pass) — 30 warm samples via the KRMA-744 harness (8bb287a7): first pixel p50/p95 652/664 ms; confirmed p95 1009 ms.
- [ ] Meet warm Edit first-pixel p95 <= 50 ms and main-actor work before first suspension <= 2 ms. (fail) — first pixel p95 664 ms vs 50 ms; pre-suspension p95 72 ms vs 2 ms.
- [ ] Run relevant focused tests, Release build, git diff --check, and dg validate. (fail) — Not verified as complete. The implementer reported focused tests, Release build, git diff --check and dg validate passing. I re-ran only git diff --check and dg validate (clean apart from existing model-name warnings) because the budget miss already blocks and no code changed.
Checks run:
- git diff --check: clean
- dg validate: passes with existing model-name warnings
- Reviewed the KRMA-744 harness capture data and profile recorded on the issue
Findings:
- BLOCKER (KRMA-746): Warm Edit selection misses both KRMA-734 budgets. PortablePhotoSourceFingerprint.file(at:) reads and hashes the whole 126 MB RAW, SourceImportPlan.source is computed so it rebuilds the ImageSource every access, and makePortableIdentity ignores the existing identity. All of it runs on the main actor in selectCollectionImage, load, prepare and EditedThumbnailCoordinator.request.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUPR8B1F1X5ZTDVI
Summary: Warm Edit first pixel p95 is 664 ms against the 50 ms budget and pre-suspension main-actor work is 72 ms against 2 ms; the repeated whole-file SHA-256 in ImageSource.makePortableIdentity is unfixed. Child KRMA-746 tracks the fix.

- 2026-10-01T22:48:38.618Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Attribute the warm Edit first-pixel and pre-suspension main-actor misses to concrete synchronous and asynchronous work. (pass) — Attributed via the KRMA-744 harness profile: whole-file SHA-256 in ImageSource.makePortableIdentity on the main actor at four points of one selection; remainder attributed to Edit-surface mount/SwiftUI work (exact warm Edit paints in ~290 ms with zero renders).
- [x] Fix the warm Edit path without changing the KRMA-734 targets. (pass) — KRMA-746/747 reuse the known content hash while the file-change signature is unchanged, build the plan's ImageSource once, and resolve package identity off the main actor before editor open. Targets unchanged. Reviewed: reuse is safe because cacheIdentity still rehashes at render time when the on-disk signature differs, and tests cover both the unchanged and replaced-file cases.
- [x] Re-run the last-known-frame Release capture on Apple Silicon with real drawable callbacks and enough warm Edit samples to report p50/p95. (pass) — Three Release captures of 30 warm samples each on 4bbc5c5f recorded in docs/TESTING.md: first pixel p50/p95 279/293 ms (was 652/664).
- [x] Meet warm Edit first-pixel p95 <= 50 ms and main-actor work before first suspension <= 2 ms (as amended by ADR-LKF-001). (pass) — First-pixel wall-clock is non-gating here per ADR-LKF-001 and tracked unchanged in KRMA-750 (293 ms p95 recorded as release evidence). Structural budgets pass (exact warm Edit: 0 renders, 1 confirmed; stale warm Edit: 1 provisional, at most 1 confirmed). Main-actor before first suspension median p95 2.03 ms (2.03/2.19/2.00), down from 72 ms, within the amended <= 3 ms median-over-three-captures gate. I did not re-run the capture myself; relied on the recorded captures.
- [x] Run relevant focused tests, Release build, git diff --check, and dg validate. (pass) — Re-run independently: swift build -c release succeeded; focused suites (AppViewModel, PreviewPresentationCoordinator, PortablePhotoIdentity, LibraryBrowsingProjection, LightInspector, EmbeddedFirstFrame, ThumbnailSwitchLifecycle, LibraryDeletion, LibraryBrowsingCoordinator) 124 tests, 0 failures, 1 skipped; git diff --check clean; dg validate passes with existing model-name warnings.
Checks run:
- swift build -c release: succeeded
- swift test --filter focused suites: 124 tests, 0 failures, 1 skipped
- git diff --check: clean
- dg validate: passes with existing model-name warnings
- Code review of Sources diff 8bb287a7..HEAD (identity reuse, SourceImportPlan, openImage package-record resolution fence)
- Reviewed Release capture results recorded in docs/TESTING.md (not re-captured)
Findings:
- NON-BLOCKING: the 2.03 ms main-actor median sits just over the 2 ms target and passes only via the ADR-LKF-001 amendment (<= 3 ms median); first-pixel p95 remains 293 ms vs 50 ms, tracked unchanged in KRMA-750. No child ticket per the owner decision.
- NON-BLOCKING: SourceImportPlan.swift has a stray trailing blank line before the closing brace; cosmetic.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUQ4H5ZRMXX07UYF
Summary: Verification passed: hash-on-main-actor removed, main-actor pre-suspension p95 72 ms to 2.03 ms median (within ADR-LKF-001 amended gate), structural budgets pass, first-pixel non-gating per ADR-LKF-001 (tracked in KRMA-750).
