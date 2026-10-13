---
id: KRMA-917
title: Align dust-suggestion undo test with ownership guard
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The test installs a suggestion with the active source fingerprint and verifies its accepted spot enters normal undo history exactly once.
      result: pass
      notes: The test unwraps retouchAnalysisSource.cacheFingerprint, installs through RetouchWorkflowCoordinator.install, asserts the sole spot ID and undo depth 1.
    - criterion: Undo removes the accepted retouch spot.
      result: pass
      notes: The test asserts the retouch spot list is empty after undo.
    - criterion: swift test --filter CopyPasteTests/testAcceptedDustSuggestionUsesNormalUndoHistory passes.
      result: pass
      notes: Focused test passed (1 test, 0 failures).
    - criterion: scripts/ci-tests.sh fast exits 0.
      result: pass
      notes: The first run had one unrelated StoredEditAdoptionTests timing assertion failure; its isolated rerun passed, and the second full run passed all 1,787 required tests with exit 0.
  checks_run:
    - swift test --filter CopyPasteTests/testAcceptedDustSuggestionUsesNormalUndoHistory — passed (1 test, 0 failures)
    - scripts/ci-tests.sh fast — second run passed all 1,787 required tests, exit 0; first run recorded one unrelated transient failure
    - swift test --filter StoredEditAdoptionTests/testSlowMaterializationCannotReopenSupersededPhoto — passed in isolation after its first parallel-lane failure
    - git diff --check -- Tests/KromoraKitTests/EditClipboardTests.swift — passed
    - dg validate — OK with existing model-registry warnings
  findings:
    - One parallel fast-lane run failed once at StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto; its isolated rerun and the subsequent full fast run passed. Filed low-priority verification child KRMA-919 under KRMA-917.
  fixes:
    - Committed the localized test setup correction; the source ownership guard and product behavior remain unchanged.
  verification_commits:
    - a7d824a3
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T01:51:12.920Z
  session: 01MV60OINX6AC63NFD
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
created: 2026-10-13T00:23:15.764Z
updated: 2026-10-13T01:51:12.924Z
parent: KRMA-916
blockers: []
order: a0
board: product
context:
  files:
    - Tests/KromoraKitTests/EditClipboardTests.swift
    - Sources/KromoraKit/ViewModels/RetouchWorkflowCoordinator.swift
  docs: []
  issues: []
  commands: []
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T01:43:18.135Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - a7d824a3
---

## Objective

Update the dust-suggestion undo-history test so it exercises the coordinator's current source-ownership contract.

## Context

KRMA-916 verification found `scripts/ci-tests.sh fast` exiting 1 on
`CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory`. The isolated rerun
`swift test --filter 'CopyPasteTests/testAcceptedDustSuggestionUsesNormalUndoHistory'` also fails.
`Tests/KromoraKitTests/EditClipboardTests.swift` seeds `retouchInteractionState` directly with
`setDustSuggestions`, bypassing `RetouchWorkflowCoordinator.install(_:owner:)`. The coordinator
rejects suggestions unless their recorded owner matches the active photo fingerprint, so this setup
produces an empty retouch list and undo depth 0 at assertions on lines 220-221. The test should set
up a legitimately owned suggestion. This is outside KRMA-916's palette changes.

## Acceptance criteria

- [ ] The test installs a suggestion with the active source fingerprint and verifies its accepted spot enters normal undo history exactly once.
- [ ] Undo removes the accepted retouch spot.
- [ ] `swift test --filter 'CopyPasteTests/testAcceptedDustSuggestionUsesNormalUndoHistory'` passes.
- [ ] `scripts/ci-tests.sh fast` exits 0.

## Implementation notes

Keep the source-ownership rejection behavior intact. Update only the test setup or a narrow test seam
needed to model a current-source suggestion; do not bypass the coordinator's ownership guard.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-13T01:51:12.920Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The test installs a suggestion with the active source fingerprint and verifies its accepted spot enters normal undo history exactly once. (pass) — The test unwraps retouchAnalysisSource.cacheFingerprint, installs through RetouchWorkflowCoordinator.install, asserts the sole spot ID and undo depth 1.
- [x] Undo removes the accepted retouch spot. (pass) — The test asserts the retouch spot list is empty after undo.
- [x] swift test --filter CopyPasteTests/testAcceptedDustSuggestionUsesNormalUndoHistory passes. (pass) — Focused test passed (1 test, 0 failures).
- [x] scripts/ci-tests.sh fast exits 0. (pass) — The first run had one unrelated StoredEditAdoptionTests timing assertion failure; its isolated rerun passed, and the second full run passed all 1,787 required tests with exit 0.
Checks run:
- swift test --filter CopyPasteTests/testAcceptedDustSuggestionUsesNormalUndoHistory — passed (1 test, 0 failures)
- scripts/ci-tests.sh fast — second run passed all 1,787 required tests, exit 0; first run recorded one unrelated transient failure
- swift test --filter StoredEditAdoptionTests/testSlowMaterializationCannotReopenSupersededPhoto — passed in isolation after its first parallel-lane failure
- git diff --check -- Tests/KromoraKitTests/EditClipboardTests.swift — passed
- dg validate — OK with existing model-registry warnings
Findings:
- One parallel fast-lane run failed once at StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto; its isolated rerun and the subsequent full fast run passed. Filed low-priority verification child KRMA-919 under KRMA-917.
Fixes:
- Committed the localized test setup correction; the source ownership guard and product behavior remain unchanged.
Verification commits:
- a7d824a3
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV60OINX6AC63NFD
Summary: Verification passed: the dust suggestion test now uses current-source ownership, both acceptance checks pass, and the intermittent unrelated adoption test failure is tracked as KRMA-919.
