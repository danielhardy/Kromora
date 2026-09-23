---
id: KRMA-547
title: Pre-existing lane failures observed during KRMA-543 verification
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Each failure is triaged to a root cause (or confirmed environment-only with a documented quarantine/skip).
      result: pass
      notes: "Root causes confirmed in code: nil-to-nil @Published histogram assignment emitted a spurious AppViewModel notification; fixture adapter admitted malformed images by extension with no warning; preview test matched the managed-library URL while the engine correctly uses the original URL. The two retired-scanner timing/grouping tests carry an unconditional XCTSkipIf with a documented reason."
    - criterion: The affected suites pass in the fast lane, or the environment-only failures are quarantined with a documented reason.
      result: pass
      notes: CanvasObservationTests 9/9 pass; LibraryScanTests 22 run, 0 failures, 2 skipped (documented quarantine); ThumbnailSwitchLifecycleTests 16/16 pass.
    - criterion: No change reintroduces the deleted mask-overlay prototype artifacts.
      result: pass
      notes: MaskOverlay.metal, MaskOverlayPrototype.swift, and MaskOverlayPerformanceBenchmark.swift remain absent; commit 99be0bf touches none of those areas (only AppViewModel histogram guard, ImageCollection scan-warning helper, fixture adapter, and two test files).
  checks_run:
    - "swift test --filter CanvasObservationTests/testHighFrequencyCanvasAndCropUpdatesBypassBroadModelPublisher: 1/1 pass"
    - "swift test --filter LibraryScanTests: 22 tests, 0 failures, 2 skipped"
    - "swift test --filter ThumbnailSwitchLifecycleTests: 16/16 pass"
    - "swift test --filter CanvasObservationTests: 9/9 pass"
    - "swift build: clean, complete"
    - verified deleted mask-overlay prototype files (MaskOverlay.metal, MaskOverlayPrototype.swift, MaskOverlayPerformanceBenchmark.swift) remain absent
  findings:
    - "Non-blocking: the two quarantined LibraryScanTests are unconditional XCTSkipIf(true), so their bodies are dead code; consider deleting them once the package-backed migration is fully closed out."
    - "Non-blocking: ImageCollection.recordScanWarning was added to the production type but is only called from the test fixture adapter; acceptable as a minimal helper consistent with the existing production warning path, no API concern."
  fixes: []
  verification_commits: []
  actor: pi
  resolved_model: unknown
  completed_at: 2026-09-23T13:53:32.491Z
  session: 01MUE5VJAD4BIEG0ZP
creation_provenance:
  runner: pi
  model: unknown
  actor: pi
labels:
  - verification
created: 2026-09-23T02:21:41.958Z
updated: 2026-09-23T13:53:32.494Z
parent: KRMA-543
order: y
board: product
---

## Objective

Triage and fix three pre-existing lane failures surfaced (but not caused) by KRMA-543 verification. Each reproduces identically on the pre-deletion parent commit (5784ea3) and on clean HEAD (96549f2) in a throwaway worktree, so all are out of scope for the mask-overlay deletion itself:

1. `CanvasObservationTests.testHighFrequencyCanvasAndCropUpdatesBypassBroadModelPublisher` (Tests/KromoraKitTests/CanvasNavigationTests.swift:627) — setting `viewModel.inspectorState.tab = .effects` now emits once through `viewModel.objectWillChange` (expected 0, got 1). Inspector chrome is apparently forwarded through the broad model publisher again.
2. `LibraryScanTests.testUnreadableImageIsReportedWithoutDiscardingReadableFiles` — 2 failures in the fast lane on clean HEAD and on the parent commit.
3. `ThumbnailSwitchLifecycleTests.testSequentialOpenPresentsReplacementWithoutAnotherUserAction` — times out waiting for the first preview (`previews=1, revisions=[2]`) on clean HEAD and on the parent commit; likely headless-environment timing.

## Acceptance criteria

- [ ] Each failure is triaged to a root cause (or confirmed environment-only with a documented quarantine/skip).
- [ ] The affected suites pass in the fast lane, or the environment-only failures are quarantined with a documented reason.
- [ ] No change reintroduces the deleted mask-overlay prototype artifacts.

### Comment — codex @ 2026-09-23T13:51:03.704Z

Implemented and committed as 99be0bf. Root causes: clearing an already-empty @Published histogram caused an extra AppViewModel notification; the folder fixture adapter admitted malformed images by extension and failed to record the warning; the preview test matched a URL even though injected edit-store rendering correctly uses the original URL, so it now matches stable asset ID. The full affected suites pass: 47 tests, 0 failures. Two legacy folder-scanner timing/grouping tests are explicitly skipped because package-backed loading retired the production scanner and the synchronous fixture adapter does not model those behaviors. No mask-overlay artifacts were changed or reintroduced.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-23T13:53:32.491Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Each failure is triaged to a root cause (or confirmed environment-only with a documented quarantine/skip). (pass) — Root causes confirmed in code: nil-to-nil @Published histogram assignment emitted a spurious AppViewModel notification; fixture adapter admitted malformed images by extension with no warning; preview test matched the managed-library URL while the engine correctly uses the original URL. The two retired-scanner timing/grouping tests carry an unconditional XCTSkipIf with a documented reason.
- [x] The affected suites pass in the fast lane, or the environment-only failures are quarantined with a documented reason. (pass) — CanvasObservationTests 9/9 pass; LibraryScanTests 22 run, 0 failures, 2 skipped (documented quarantine); ThumbnailSwitchLifecycleTests 16/16 pass.
- [x] No change reintroduces the deleted mask-overlay prototype artifacts. (pass) — MaskOverlay.metal, MaskOverlayPrototype.swift, and MaskOverlayPerformanceBenchmark.swift remain absent; commit 99be0bf touches none of those areas (only AppViewModel histogram guard, ImageCollection scan-warning helper, fixture adapter, and two test files).
Checks run:
- swift test --filter CanvasObservationTests/testHighFrequencyCanvasAndCropUpdatesBypassBroadModelPublisher: 1/1 pass
- swift test --filter LibraryScanTests: 22 tests, 0 failures, 2 skipped
- swift test --filter ThumbnailSwitchLifecycleTests: 16/16 pass
- swift test --filter CanvasObservationTests: 9/9 pass
- swift build: clean, complete
- verified deleted mask-overlay prototype files (MaskOverlay.metal, MaskOverlayPrototype.swift, MaskOverlayPerformanceBenchmark.swift) remain absent
Findings:
- Non-blocking: the two quarantined LibraryScanTests are unconditional XCTSkipIf(true), so their bodies are dead code; consider deleting them once the package-backed migration is fully closed out.
- Non-blocking: ImageCollection.recordScanWarning was added to the production type but is only called from the test fixture adapter; acceptable as a minimal helper consistent with the existing production warning path, no API concern.
Fixes:
- None
Verification commits:
- None
Actor: pi
Resolved model: unknown
Pickup session: 01MUE5VJAD4BIEG0ZP
Summary: KRMA-547 verification passes: all three lane failures resolved with correct minimal fixes, affected suites green, no mask-overlay artifacts reintroduced.
