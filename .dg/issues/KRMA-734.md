---
id: KRMA-734
title: Qualify last-known frames under faults, load, and release benchmarks
type: task
status: done
priority: urgent
verification_agent: claude
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Fault tests cover truncated/overflow/corrupt preview envelopes, pack index, interrupted writes, transaction failure, deleted Derived, LaunchHints
      result: pass
      notes: Matrix in docs/TESTING.md; fast lane 1462 tests pass.
    - criterion: Identity tests cover replacement, relocation, virtual copies, deletion, Look replacement, raster mismatch, pixel epoch, storage format
      result: pass
      notes: identity lane 4/4 passed.
    - criterion: Rapid A->B->A and filmstrip scrubs never publish obsolete completions
      result: pass
      notes: ThumbnailSwitchLifecycleTests in fast/serial lanes pass; the 4bbc5c5f fence test covers the package-record resolution window.
    - criterion: Cache-pressure tests prove preview LRU cap/pinning and thumbnail compaction
      result: pass
      notes: Fast lane.
    - criterion: Release benchmark evidence records every required field and reports p50/p95, frame counts, render admissions, crossfades, thumbnail swaps, layout changes
      result: pass
      notes: Three Release captures on 4bbc5c5f (M1 Pro, macOS 27.0, DSC01019.ARW, 30 samples each) and the KRMA734v1 capture recorded in docs/TESTING.md.
    - criterion: Structural budgets pass and main-actor work before first suspension <= 2 ms (median p95 <= 3 ms per ADR-LKF-001 amendment; wall-clock budgets non-gating)
      result: pass
      notes: Exact warm Edit 0 renders/1 confirmed; stale 1 provisional/1 confirmed; main-actor median p95 2.03 ms (2.00-2.19), within the 3 ms amended tolerance. Wall-clock first pixel p95 293 ms and grid p95 235 ms are evidence tracked in KRMA-748/749/750; no child ticket opened.
    - criterion: Confirmed/provisional frame counts are actual drawable presentations
      result: pass
      notes: Harness counts onPresented drawable callbacks.
    - criterion: STORAGE_POLICY, ENGINEERING_GUIDE, APP_ARCHITECTURE, TESTING describe landed implementation, ownership, failure semantics, migration, benchmark method
      result: pass
      notes: ThumbnailFrameStore and LaunchHints documented in 4bbc5c5f; TESTING.md main-actor row now records the ADR-LKF-001 tolerance (3bcb1c7f).
    - criterion: Warning gate, build, full test, release build, fast, serial, identity, git diff --check, dg validate pass
      result: pass
      notes: All pass on HEAD. Full swift test not run as a separate invocation; fast (1462) + serial (455) + optional (50, 31 skipped for missing opt-in env, 0 failures) cover the 1967 discovered tests and the lane audit confirms disjoint partition.
  checks_run:
    - "xcodebuild -version: Xcode 27.0 (27A266a)"
    - "scripts/ci-tests.sh warning-gate: pass"
    - "swift build: pass"
    - "swift build -c release: pass"
    - "scripts/ci-tests.sh verify: pass (total=1967 fast=1462 serial=455 optional=50, disjoint)"
    - "scripts/ci-tests.sh fast: pass (1462 tests)"
    - "scripts/ci-tests.sh serial: pass (455 tests, 0 failures)"
    - "scripts/ci-tests.sh identity: pass (4 tests, 0 failures)"
    - "scripts/ci-tests.sh optional: pass (50 executed, 31 skipped for opt-in env vars, 0 failures)"
    - "git diff --check: pass"
    - "dg validate: pass (model-name warnings only)"
    - Reviewed 4bbc5c5f AppViewModel.openImage canvas fence and its regression test, and 9ff5251d TESTING.md benchmark evidence
  findings:
    - docs/TESTING.md still labelled the main-actor 2.03 ms median as 'at the limit' without the owner's ADR-LKF-001 3 ms tolerance; corrected in 3bcb1c7f.
    - No correctness, security, or performance defects found in the reviewed changes. Wall-clock first-pixel and grid misses remain non-gating evidence tracked in KRMA-748/749/750 per ADR-LKF-001.
  fixes:
    - "docs/TESTING.md: main-actor budget row records the ADR-LKF-001 amendment and result"
  verification_commits:
    - 3bcb1c7f
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-01T23:12:31.886Z
  session: 01MUQ4YMRCYV0DVQX6
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - performance
  - reliability
  - verification
  - caching
created: 2026-09-30T13:19:21.193Z
updated: 2026-10-01T23:12:31.891Z
depends_on:
  - KRMA-729
  - KRMA-730
  - KRMA-731
  - KRMA-732
  - KRMA-733
  - KRMA-737
  - KRMA-739
  - KRMA-738
  - KRMA-751
blockers:
  - id: evt_muoncf71_uxhj3k
    type: human
    reason: The only local toolchain is /Applications/Xcode-beta.app (Xcode 27.0 build 27A5252f); its beta SDK failed to link the Release XCTest bundle. Xcode 27.0 stable (build 27A266a) has since been released but is not installed here, so the release drawable and last-known-frame budgets remain unmeasured on stable.
    action: Install/select Xcode 27.0 stable (build 27A266a) on this Apple Silicon host, rerun the Release XCTest drawable capture and budgets, then resume KRMA-734 at verification.
    created_at: 2026-09-30T21:57:59.149Z
    resolved_at: 2026-09-30T22:43:18.728Z
    resolved_by: web
estimate: 8
order: n
board: product
blocked_reason: The only local toolchain is /Applications/Xcode-beta.app (Xcode 27.0 build 27A5252f); its beta SDK failed to link the Release XCTest bundle. Xcode 27.0 stable (build 27A266a) has since been released but is not installed here, so the release drawable and last-known-frame budgets remain unmeasured on stable.
blocked_action: Install/select Xcode 27.0 stable (build 27A266a) on this Apple Silicon host, rerun the Release XCTest drawable capture and budgets, then resume KRMA-734 at verification.
blocked_from_status: ready
context:
  files:
    - Sources/KromoraKit/Models/Observability.swift
    - Sources/KromoraKit/Models/PreviewDiskCache.swift
    - Sources/KromoraKit/Models/PortablePackageMaintenance.swift
    - Sources/KromoraKit/ViewModels/PreviewAdmissionCoordinator.swift
    - Sources/KromoraKit/ViewModels/PreviewPresentationCoordinator.swift
    - Sources/KromoraKit/ViewModels/EditedThumbnailCoordinator.swift
    - Tests/KromoraKitTests/
    - scripts/ci-tests.sh
    - scripts/run-kromora-capture.sh
  docs:
    - .context/last-known-frame-plan.md
    - docs/TESTING.md
    - docs/STORAGE_POLICY.md
    - docs/ENGINEERING_GUIDE.md
    - docs/APP_ARCHITECTURE.md
  issues: []
  commands:
    - scripts/ci-tests.sh warning-gate
    - swift build
    - swift test
    - swift build -c release
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - scripts/ci-tests.sh identity
    - scripts/ci-tests.sh optional
    - git diff --check
    - dg validate
commits:
  - dd1b3554
  - b83a4cd9
  - 3bcb1c7f
---

## Objective

Prove the complete last-known-frame system remains correct under corruption, interruption,
replacement, eviction, and rapid navigation, and record release-build performance against the
architecture budgets.

## Context

This is Phase 6 and starts only after KRMA-729 through KRMA-733 are done. Do not paper over failures
with retries or relaxed assertions. Fix localized defects found here; create urgent child blockers
for broader defects.

Build one deterministic scenario matrix that covers preview envelopes, packed thumbnails,
transactional geometry, Look deltas, launch hints, and presentation generations. Use existing fault
injection and fake-render seams for correctness, then use real ImageIO/Core Image/AppKit paths in the
serial/optional lanes where needed.

Measure release builds on representative Apple Silicon. Record machine, OS, commit, source
format/dimensions, viewport/backing pixels, cold/warm state, cache state, and sample count. Fake
renderer measurements are orchestration evidence only.

Required architecture budgets from the plan:

- warm Edit navigation: correct-photo provisional pixels p95 <= 50 ms, with <= 2 ms main-actor work
  before first suspension;
- exact warm Edit: zero preview renders and one confirmed frame;
- stale warm Edit: one provisional plus at most one confirmed replacement;
- warm 30-cell grid: p95 visible frame hydration <= 100 ms on the reference system;
- unchanged Look rescan: zero preview/edited-thumbnail render admissions;
- pixel epoch bump: no wipe or blanking;
- navigation burst: bounded work and zero obsolete publications.

If hardware variance makes a wall-clock limit unsuitable for required CI, keep deterministic
structural assertions in CI and record the wall-clock result as release benchmark evidence. Do not
silently drop the budget.

## Acceptance criteria

- [ ] Fault tests cover truncated/overflow/corrupt preview envelopes, corrupt/missing pack index,
      interrupted preview and pack writes, transaction failure around edit+geometry, deleted
      `Derived`, and corrupt/oversized LaunchHints.
- [ ] Identity tests cover in-place source replacement, package relocation, virtual copies, asset
      deletion, Look replacement at the same ID, raster-space mismatch, pixel epoch change, and
      storage format change.
- [ ] Rapid A -> B -> A and long filmstrip scrubs prove obsolete cache/embedded/render/thumbnail/scan
      completions never publish and work stays bounded.
- [ ] Cache-pressure tests prove preview LRU cap/pinning and thumbnail compaction without evicting or
      corrupting active visible entries.
- [ ] Release benchmark evidence records every required field and reports p50/p95, frame counts,
      render admissions, crossfades, thumbnail swaps, and layout changes.
- [ ] Structural budgets pass (exact warm Edit: zero preview renders and one confirmed frame; stale warm Edit: one provisional plus at most one confirmed replacement; unchanged Look rescan, pixel epoch bump, and navigation burst per their structural assertions) and main-actor work before first suspension <= 2 ms (median p95 over up to three captures). **Amended by owner decision ADR-LKF-001:** the wall-clock warm Edit first-pixel (p95 <= 50 ms) and warm 30-cell grid (p95 <= 100 ms) budgets are not redefined or dropped, but they no longer gate this ticket; the measured misses are recorded as release evidence in docs/TESTING.md and tracked unchanged in KRMA-750. Do not open a child ticket for them. **Owner amendment (ADR-LKF-001):** main-actor before first suspension passes at a median p95 <= 3 ms over up to three captures (target remains 2 ms; measured median 2.03 ms).
- [ ] "Confirmed frame" and "provisional frame" counts are actual drawable presentations, and
      KRMA-731/732/733 assertions use this same definition.
- [ ] `STORAGE_POLICY.md`, `ENGINEERING_GUIDE.md`, `APP_ARCHITECTURE.md`, and `TESTING.md` describe
      the landed implementation, ownership, failure semantics, migration, and benchmark method.
- [ ] Warning gate, build, full test, release build, fast, serial, identity, `git diff --check`, and
      `dg validate` pass. Optional RAW/manual drawable checks are run when fixtures/display exist and
      are explicitly marked unavailable otherwise.

## Implementation notes

- Count actual confirmed drawable presentations; screenshots do not establish sequence or latency.
- Cache loss/corruption must degrade to ordinary decode/render, never package-open failure.
- Keep verification artifacts out of durable package truth and within documented size/privacy
  limits.

### Comment — codex @ 2026-09-30T21:57:53.883Z

Qualification handoff committed as 70d7907. Warning gate, swift build, swift test, Release app build, fast, serial (455/455 with one skip), identity (4/4), git diff --check, and dg validate passed. The optional lane with local IMG_0371.DNG exposed two failing test methods/three assertions; urgent follow-up KRMA-737 records the RAW preparation and decoder seed diagnosis and is linked as a dependency. Release drawable capture could not link its XCTest bundle with the only installed toolchain, Xcode 27.0 beta; no release latency or actual drawable-count evidence was produced. Architecture budgets remain unmeasured.,

### Comment — codex @ 2026-09-30T22:33:32.248Z

Toolchain guidance is now Xcode 27+ with the macOS 27 SDK; the app deployment floor remains macOS 26. CI now targets GitHub's arm64 xcode-27 runner image (currently preview). Apple's release page lists Xcode 27.0 stable build 27A266a, released September 14, 2026: https://developer.apple.com/news/releases/?id=01062025a. This host still selects /Applications/Xcode-beta.app build 27A5252f, so the human blocker remains until the Release XCTest drawable capture is repeated successfully on stable Xcode 27.

### Comment — codex @ 2026-10-01T14:43:22.428Z

Historical measurement update from existing captures (no new capture needed for this note): the 2026-09-30 KRMA-742 run produced exact warm Edit 211.7 ms (1 sample; 0 renders, 1 provisional/1 confirmed), stale warm Edit 182.3 ms (1 sample; 1 render, 1 provisional/1 confirmed), warm Edit p50/p95 196.3/197.2 ms (5 samples), main-actor selection p95 289.0 ms, and warm-grid p50/p95 0.135/0.135 ms (5 samples). KRMA-744 found the grid samples did not include a new SwiftUI mount/layout and the Edit first-pixel clock started mid-selection; those latency numbers are not qualification evidence. The 289.0 ms synchronous call is a diagnostic observation, not a proven remount measurement. Exact/stale counts are single-sample observations, not asserted then. KRMA-743’s later run got one 1.23 ms warm-up selection sample and one embedded-JPEG drawable at 1132.7 ms, but no confirmed RAW drawable or valid p50/p95. Keep architecture budgets marked unqualified; don’t rerun the broken capture path.

### Comment — claude @ 2026-10-01T16:30:20.880Z

Status after the KRMA-744 harness repair (8bb287a7): the Release benchmark now produces valid, asserted evidence. Budgets: exact warm Edit PASS (0 renders, 1 confirmed), stale warm Edit PASS (1 provisional, 1 confirmed), warm 30-cell grid p95 214 ms vs 100 MISS (KRMA-745), warm Edit first pixel p95 664 ms vs 50 MISS and main-actor before suspension p95 72 ms vs 2 MISS (KRMA-743, root cause identified: whole-file SHA-256 of the 126 MB RAW in ImageSource.makePortableIdentity on the main actor, 37% of main-thread time). Per this ticket both misses are ticketed and linked in depends_on, so it stays open until 743 and 745 land and the capture reports edit=PASS and grid=PASS. Remaining unmeasured budgets from the list (unchanged Look rescan, pixel epoch bump, navigation burst) are not covered by this harness and need their structural CI assertions confirmed at verification. The earlier historical 2026-09-30 grid/Edit latency numbers are invalid and superseded.

### Comment — claude @ 2026-10-01T20:24:35.862Z

Owner decision ADR-LKF-001 (2026-10-01): wall-clock warm Edit first-pixel and 30-cell grid budgets are recorded as release evidence in docs/TESTING.md and tracked unchanged in KRMA-750 (non-gating); this ticket's budget criterion was amended accordingly and its dependencies on 743 and 745 removed. Verify the fault, identity, rapid-navigation, cache-pressure, documentation, and gate criteria and the structural budgets. Latest valid numbers: exact warm Edit 0 renders/1 confirmed (pass), stale 1 provisional/1 confirmed (pass), main-actor p95 1.99 ms (pass), warm Edit first pixel p95 ~290 ms and grid p95 ~231 ms (evidence, tracked in KRMA-750). Do not open a child ticket for the wall-clock misses.

### Comment — claude @ 2026-10-01T22:02:38.695Z

Pre-flight of this ticket's gate on 4bbc5c5f by the owner's request, ahead of re-verification. Gate: scripts/ci-tests.sh verify, warning-gate (zero warnings), fast, serial (455 tests), identity (4 tests) all pass; debug and release builds succeed; the app launches and exits cleanly. Fixed here: (1) KRMA-751 test determinism, 1ea93f49; (2) a real invariant violation found in review: after KRMA-747, selecting a package-library photo returned before load() cleared the canvas, so the previous photo stayed visible while the record resolved; AppViewModel.openImage now fences the surface first, with a regression test that fails without it, 4bbc5c5f; (3) STORAGE_POLICY, ENGINEERING_GUIDE, and APP_ARCHITECTURE now describe ThumbnailFrameStore and LaunchHints, which they had omitted, 4bbc5c5f. Budgets (three captures, docs/TESTING.md, 9ff5251d): exact warm Edit 0 renders/1 confirmed PASS, stale warm Edit 1 provisional/1 confirmed PASS, main-actor before first suspension median p95 2.03 ms (1.88-2.19 across all runs) which is AT the <= 2 ms limit and not clearly under it, warm Edit first pixel p95 293 ms (was 664) and grid p95 235 ms are evidence tracked in KRMA-748/749 per ADR-LKF-001. The main-actor figure is the one open judgement: it is within run-to-run noise but its median is 0.03 ms over. Still waiting on KRMA-751 verification (dependency).

### Comment — claude @ 2026-10-01T22:31:27.471Z

Owner decision recorded in ADR-LKF-001 (amendment): main-actor before first suspension keeps its <= 2 ms target but passes at a median p95 <= 3 ms over up to three captures. Measured median is 2.03 ms (1.88-2.19), well under one display frame and run-to-run variance, so do not fail or open a ticket on it.

### Comment — claude @ 2026-10-01T22:35:36.938Z

Manual check by the owner on 2026-10-01 against 4bbc5c5f: ran the debug build (swift run), clicked through Library, Edit, and filmstrip selection, and nothing looked wrong. Debug builds run noticeably slower, so this is a functional smoke check and not timing evidence; release timings are the three captures in docs/TESTING.md. Screenshots were not captured.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-30T23:39:15.339Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [ ] Release benchmark evidence records every required field and reports p50/p95, frame counts (fail) — No release capture; docs/TESTING.md records only a failed link attempt.
- [ ] All architecture budgets pass (fail) — Unmeasured. Blocker KRMA-738 filed.
- [ ] Confirmed/provisional frame counts are actual drawable presentations (fail) — No drawable capture produced.
Checks run:
- xcode-select -p; xcodebuild -version: Xcode-beta 27A5252f, stable not installed
Findings:
- Human blocker marked resolved but stable Xcode 27.0 is not installed; budgets unmeasured. Tracked in KRMA-738.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUOQY1ODO4AQ3O7F
Summary: Release drawable budgets remain unmeasured: host still has only Xcode 27.0 beta (27A5252f); stable not installed. Child KRMA-738 filed.

- 2026-10-01T00:24:41.094Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] Fault tests cover truncated/overflow/corrupt preview envelopes, pack index, interrupted writes, transaction failure, deleted Derived, LaunchHints (pass) — Matrix in docs/TESTING.md; fast lane passed.
- [x] Identity tests cover replacement, relocation, virtual copies, deletion, Look replacement, raster mismatch, pixel epoch, storage format (pass) — identity lane 4/4 passed.
- [x] Rapid A->B->A and filmstrip scrubs never publish obsolete completions (pass) — Covered by fast/serial navigation suites, which passed apart from the unrelated grain failure.
- [x] Cache-pressure tests prove preview LRU cap/pinning and thumbnail compaction (pass) — Fast lane passed.
- [ ] Release benchmark evidence records every required field and reports p50/p95, frame counts, render admissions, crossfades, thumbnail swaps, layout changes (fail) — Release XCTest bundle still fails to link on stable Xcode 27.0 (27A266a); no samples produced. KRMA-738.
- [ ] All architecture budgets pass (fail) — Unmeasured; blocker KRMA-738 (linked as dependency).
- [ ] Confirmed/provisional frame counts are actual drawable presentations (fail) — No drawable capture could run; KRMA-738.
- [x] Docs describe landed implementation, ownership, failure semantics, migration and benchmark method (pass) — TESTING.md updated with stable-toolchain attempt.
- [ ] Warning gate, build, full test, release build, fast, serial, identity, git diff --check, dg validate pass (fail) — Serial lane fails: MetalKernelParityTests grain-seed delta 34 > 32 on macOS 27.0 (26A428). KRMA-739. Full swift test and optional lane not run separately; serial and fast cover them.
Checks run:
- xcode-select -p; xcodebuild -version: Xcode 27.0 (27A266a) stable selected
- scripts/ci-tests.sh warning-gate: pass
- swift build: pass
- swift build -c release: pass
- scripts/ci-tests.sh fast: pass
- scripts/ci-tests.sh serial: FAIL (2 grain golden assertions, delta 34 > 32)
- scripts/ci-tests.sh identity: pass (4/4)
- git diff --check: pass
- dg validate: pass (model warnings only)
- scripts/run-kromora-capture.sh --benchmark metal-presentation --source realworldtest/DSC01019.ARW --iterations 30: FAIL (Release XCTest link error: SwiftUI opaque type descriptors, CoreAudioTypes)
Findings:
- Stable Xcode 27.0 is installed, but the Release XCTest bundle still fails to link (unresolved SwiftUI View.tag/task opaque descriptors), so the earlier beta-SDK diagnosis was incomplete and budgets remain unmeasured. Tracked in KRMA-738, now a dependency of KRMA-734.
- Serial lane fails on macOS 27.0 (26A428): grain-seed golden worst delta 34 vs tolerance 32 (passed on macOS 27.2). Tracked in KRMA-739, now a dependency of KRMA-734.
- Tolerance was not relaxed; no product source changed.
Fixes:
- None
Verification commits:
- dd1b3554
Actor: claude
Resolved model: sonnet
Pickup session: 01MUORQY6UO1WWPMRI
Summary: Release drawable budgets still unmeasured: Release XCTest bundle fails to link even on stable Xcode 27.0 (KRMA-738); serial lane also fails on a grain golden at macOS 27.0 (KRMA-739).

- 2026-10-01T21:07:22.220Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] Fault tests cover truncated/overflow/corrupt preview envelopes, pack index, interrupted writes, transaction failure, deleted Derived, LaunchHints (pass) — Matrix in docs/TESTING.md; covering tests pass in the fast lane (apart from the flaky tests below).
- [x] Identity tests cover replacement, relocation, virtual copies, deletion, Look replacement, raster mismatch, pixel epoch, storage format (pass) — identity lane 4/4 passed.
- [x] Rapid A->B->A and filmstrip scrubs never publish obsolete completions (pass) — ThumbnailSwitchLifecycleTests 18/18 pass after the verification fix; serial lane 455/455.
- [x] Cache-pressure tests prove preview LRU cap/pinning and thumbnail compaction (pass) — Fast lane.
- [x] Release benchmark evidence records every required field and reports p50/p95, frame counts, render admissions, crossfades, thumbnail swaps, layout changes (pass) — Fresh Release capture KRMA734v1 on Xcode 27.0 stable (30 iterations) recorded in docs/TESTING.md.
- [x] Structural budgets pass and main-actor work before first suspension <= 2 ms (wall-clock budgets non-gating per ADR-LKF-001) (pass) — Exact warm Edit 0 renders/1 confirmed; stale 1 provisional/1 confirmed; main-actor p95 1.86 ms (prior capture 1.99). Wall-clock misses (first pixel p95 278 ms, grid p95 230 ms) recorded in TESTING.md and tracked in KRMA-750; no child ticket opened for them.
- [x] Confirmed/provisional frame counts are actual drawable presentations (pass) — Harness counts onPresented drawable callbacks; capture reports 30 provisional / 30 confirmed.
- [x] STORAGE_POLICY, ENGINEERING_GUIDE, APP_ARCHITECTURE, TESTING describe landed implementation, ownership, failure semantics, migration, benchmark method (pass) — TESTING.md updated with this capture and the ADR-LKF-001 status.
- [ ] Warning gate, build, full test, release build, fast, serial, identity, git diff --check, dg validate pass (fail) — fast lane fails reproducibly: EmbeddedFirstFrameTests (KRMA-751, introduced by KRMA-743 cd21acc7). Full swift test not run separately (fast + serial cover it).
Checks run:
- xcodebuild -version: Xcode 27.0 (27A266a); macOS 27.0 (26A428)
- scripts/ci-tests.sh warning-gate: pass
- swift build: pass
- swift build -c release: pass
- git diff --check: pass
- dg validate: pass (model warnings only)
- scripts/ci-tests.sh fast (HEAD, before fixes): FAIL (10 failures across LibraryDeletionTests, ThumbnailSwitchLifecycleTests, WorkspaceNavigationTests, bisected to cd21acc7)
- scripts/ci-tests.sh fast (after fixes, 2 runs): FAIL (EmbeddedFirstFrameTests x2 runs; SmartMaskTests flake once)
- focused LibraryDeletionTests|ThumbnailSwitchLifecycleTests|WorkspaceNavigationTests after fixes: pass (34/34)
- EmbeddedFirstFrameTests under CPU load: fail 2/3 at HEAD, pass 4/4 at pre-743 bc473576
- scripts/ci-tests.sh serial: pass (455/455)
- scripts/ci-tests.sh identity: pass (4/4)
- scripts/run-kromora-capture.sh --benchmark last-known-frame --source realworldtest/DSC01019.ARW: pass; exact/stale structural budgets pass, main-actor p95 1.86 ms; wall-clock first pixel 278 ms and grid 230 ms are non-gating evidence (ADR-LKF-001, KRMA-750)
Findings:
- KRMA-743 (cd21acc7) split load() into a synchronous half and a deferred beginLoad, which broke 10 fast-lane assertions. Three causes: selectCollectionImage skipped the collection focus step although selectPortableItem is a no-op without an open library (fixed: only skip when the item is actually active); LibraryDeletionTests and ThumbnailSwitchLifecycleTests asserted synchronously after the now-yielding switch (fixed: wait for install).
- EmbeddedFirstFrameTests became nondeterministic: the real background thumbnail loader can finish before the deferred beginLoad, so the original thumbnail becomes the candidate and the embedded first frame is rejected. Needs a thumbnail seam or selection-time candidate choice; not a localized safe fix. Urgent child KRMA-751, now a dependency of KRMA-734.
- SmartMaskTests.testForegroundAndBackgroundRequestsShareOneSegmentationTask flaked once (provider called twice); unrelated to this work. Backlog child KRMA-752.
- Working tree holds another agent's uncommitted AppViewModel (grid transaction) and benchmark signpost edits; left untouched and not committed.
Fixes:
- AppViewModel.selectCollectionImage: collectionAlreadySelected only when collection.selection.activeID == item.id
- LibraryDeletionTests and ThumbnailSwitchLifecycleTests: await the deferred source install / candidate instead of asserting synchronously
- docs/TESTING.md: record the KRMA734v1 capture and ADR-LKF-001 status
Verification commits:
- b83a4cd9
Actor: claude
Resolved model: sonnet
Pickup session: 01MUPZL3XVXLYJSSI0
Summary: Fast lane fails reproducibly on EmbeddedFirstFrameTests, a nondeterminism introduced by KRMA-743 (deferred beginLoad lets the real thumbnail win the candidate race). Urgent child KRMA-751. Structural budgets, serial, identity, and docs pass; localized fixes committed in b83a4cd9.

- 2026-10-01T23:12:31.886Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Fault tests cover truncated/overflow/corrupt preview envelopes, pack index, interrupted writes, transaction failure, deleted Derived, LaunchHints (pass) — Matrix in docs/TESTING.md; fast lane 1462 tests pass.
- [x] Identity tests cover replacement, relocation, virtual copies, deletion, Look replacement, raster mismatch, pixel epoch, storage format (pass) — identity lane 4/4 passed.
- [x] Rapid A->B->A and filmstrip scrubs never publish obsolete completions (pass) — ThumbnailSwitchLifecycleTests in fast/serial lanes pass; the 4bbc5c5f fence test covers the package-record resolution window.
- [x] Cache-pressure tests prove preview LRU cap/pinning and thumbnail compaction (pass) — Fast lane.
- [x] Release benchmark evidence records every required field and reports p50/p95, frame counts, render admissions, crossfades, thumbnail swaps, layout changes (pass) — Three Release captures on 4bbc5c5f (M1 Pro, macOS 27.0, DSC01019.ARW, 30 samples each) and the KRMA734v1 capture recorded in docs/TESTING.md.
- [x] Structural budgets pass and main-actor work before first suspension <= 2 ms (median p95 <= 3 ms per ADR-LKF-001 amendment; wall-clock budgets non-gating) (pass) — Exact warm Edit 0 renders/1 confirmed; stale 1 provisional/1 confirmed; main-actor median p95 2.03 ms (2.00-2.19), within the 3 ms amended tolerance. Wall-clock first pixel p95 293 ms and grid p95 235 ms are evidence tracked in KRMA-748/749/750; no child ticket opened.
- [x] Confirmed/provisional frame counts are actual drawable presentations (pass) — Harness counts onPresented drawable callbacks.
- [x] STORAGE_POLICY, ENGINEERING_GUIDE, APP_ARCHITECTURE, TESTING describe landed implementation, ownership, failure semantics, migration, benchmark method (pass) — ThumbnailFrameStore and LaunchHints documented in 4bbc5c5f; TESTING.md main-actor row now records the ADR-LKF-001 tolerance (3bcb1c7f).
- [x] Warning gate, build, full test, release build, fast, serial, identity, git diff --check, dg validate pass (pass) — All pass on HEAD. Full swift test not run as a separate invocation; fast (1462) + serial (455) + optional (50, 31 skipped for missing opt-in env, 0 failures) cover the 1967 discovered tests and the lane audit confirms disjoint partition.
Checks run:
- xcodebuild -version: Xcode 27.0 (27A266a)
- scripts/ci-tests.sh warning-gate: pass
- swift build: pass
- swift build -c release: pass
- scripts/ci-tests.sh verify: pass (total=1967 fast=1462 serial=455 optional=50, disjoint)
- scripts/ci-tests.sh fast: pass (1462 tests)
- scripts/ci-tests.sh serial: pass (455 tests, 0 failures)
- scripts/ci-tests.sh identity: pass (4 tests, 0 failures)
- scripts/ci-tests.sh optional: pass (50 executed, 31 skipped for opt-in env vars, 0 failures)
- git diff --check: pass
- dg validate: pass (model-name warnings only)
- Reviewed 4bbc5c5f AppViewModel.openImage canvas fence and its regression test, and 9ff5251d TESTING.md benchmark evidence
Findings:
- docs/TESTING.md still labelled the main-actor 2.03 ms median as 'at the limit' without the owner's ADR-LKF-001 3 ms tolerance; corrected in 3bcb1c7f.
- No correctness, security, or performance defects found in the reviewed changes. Wall-clock first-pixel and grid misses remain non-gating evidence tracked in KRMA-748/749/750 per ADR-LKF-001.
Fixes:
- docs/TESTING.md: main-actor budget row records the ADR-LKF-001 amendment and result
Verification commits:
- 3bcb1c7f
Actor: claude
Resolved model: sonnet
Pickup session: 01MUQ4YMRCYV0DVQX6
Summary: Verification passed: all gates green on HEAD; structural budgets pass; wall-clock misses tracked in KRMA-750 per ADR-LKF-001.
