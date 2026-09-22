---
id: KRMA-539
title: Fix MaskingWorkspaceTests source-switch and mask persistence failures
type: task
status: done
priority: high
agent: codex
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The focused MaskingWorkspaceTests suite passes without timeout.
      result: pass
      notes: swift test --no-parallel --filter KromoraKitTests.MaskingWorkspaceTests passed 36/36.
    - criterion: Switching photos preserves the active photo and restores its mask document.
      result: pass
      notes: The active-photo and masking-tab restoration test passed in the focused suite.
    - criterion: Persisted semantic masks reopen with their target and source state.
      result: pass
      notes: Semantic-mask creation, reuse, persisted target/source identity, and source-switch coverage passed in the focused suite; companion persistence tests passed 11/11.
    - criterion: The fast lane no longer reports this suite.
      result: pass
      notes: scripts/ci-tests.sh fast completed its required lane without a MaskingWorkspaceTests failure. Its exit code was nonzero only for unrelated CopyPasteTests, LibraryDeletionTests, LibraryScanTests, and ThumbnailSwitchLifecycleTests.
  checks_run:
    - swift test --no-parallel --filter KromoraKitTests.MaskingWorkspaceTests (36 passed)
    - swift test --no-parallel --filter KromoraKitTests.SourceSessionCoordinatorTests (4 passed)
    - swift test --no-parallel --filter KromoraKitTests.EditPersistenceIntegrationTests (11 passed)
    - swift build -c release (passed with two pre-existing warnings)
    - scripts/ci-tests.sh fast (MaskingWorkspaceTests passed; unrelated failures listed above)
    - git diff --check
  findings:
    - The fast lane still has unrelated failures in CopyPasteTests, LibraryDeletionTests, LibraryScanTests, and ThumbnailSwitchLifecycleTests.
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-22T20:35:47.946Z
  session: 01MUD4VWSH10B21U92
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - fast-lane
  - regression
  - masking
created: 2026-09-22T17:35:55.872Z
updated: 2026-09-22T20:35:47.948Z
estimate: 3
order: n
board: product
---

## Objective

Restore MaskingWorkspaceTests coverage for source switching, active-photo state, and persisted mask reopening.

## Evidence

The fast lane failed while waiting for the second photo, persisted masks, and the second source to publish. The failures affected active-photo mask-tab restoration and semantic-mask reuse, including missing persisted targets and source readiness.

## Acceptance criteria

- [ ] The focused MaskingWorkspaceTests suite passes without timeout.
- [ ] Switching photos preserves the active photo and restores its mask document.
- [ ] Persisted semantic masks reopen with their target and source state.
- [ ] The fast lane no longer reports this suite.

### Comment — codex @ 2026-09-22T19:28:33.379Z

Recovered implementation changes into WIP commit 20cf4cb after the prior direct claimed-to-done transition. No ticket-specific commit attribution or independent verification is accepted; this issue is intentionally back in review for fresh verification.

### Comment — codex @ 2026-09-22T19:52:30.748Z

Verification was attempted twice but the Claude runner exited before submitting a report after its background release-build/masking-test tasks were killed at runner end-of-turn. No pass is recorded; returning to review for a verifier invocation that keeps checks foreground and waits for completion.

## Agent log

- 2026-09-22T18:47:44.169Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The focused MaskingWorkspaceTests suite passes without timeout. (pass) — MaskingWorkspaceTests passed 36/36 serially and in five repeated parallel runs.
- [x] Switching photos preserves the active photo and restores its mask document. (pass) — The active-photo/tab restoration regression passed; source-session loads now await the persistence barrier before reading stored edits.
- [x] Persisted semantic masks reopen with their target and source state. (pass) — The semantic-mask reuse/reopen regression passed, including persisted Subject target and source-switch isolation.
- [x] The fast lane no longer reports this suite. (pass) — The fast lane reached the masking suite without a MaskingWorkspaceTests failure; remaining fast-lane failures were unrelated suites already tracked separately.
Checks run:
- swift test --no-parallel --filter KromoraKitTests.MaskingWorkspaceTests (36 passed)
- swift test --parallel --filter KromoraKitTests.MaskingWorkspaceTests (5 repeated runs, 36 passed each)
- swift test --no-parallel --filter KromoraKitTests.SourceSessionCoordinatorTests (4 passed)
- swift test --no-parallel --filter KromoraKitTests.EditPersistenceIntegrationTests (11 passed)
- swift build -c release
- dg validate --json
- git diff --check
Findings:
- None
Fixes:
- Source switching now waits for queued edit persistence to finish before stored-document reads begin.
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MUD0OSEAKUDM9UFV
Summary: Added a source-load persistence barrier so photo switches wait for the prior edit snapshot to become durable before reading the next photo's document. Mask tab state and per-photo mask documents now survive navigation, and persisted semantic-mask recipes reopen with their target/source identity.

- 2026-09-22T20:35:47.946Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The focused MaskingWorkspaceTests suite passes without timeout. (pass) — swift test --no-parallel --filter KromoraKitTests.MaskingWorkspaceTests passed 36/36.
- [x] Switching photos preserves the active photo and restores its mask document. (pass) — The active-photo and masking-tab restoration test passed in the focused suite.
- [x] Persisted semantic masks reopen with their target and source state. (pass) — Semantic-mask creation, reuse, persisted target/source identity, and source-switch coverage passed in the focused suite; companion persistence tests passed 11/11.
- [x] The fast lane no longer reports this suite. (pass) — scripts/ci-tests.sh fast completed its required lane without a MaskingWorkspaceTests failure. Its exit code was nonzero only for unrelated CopyPasteTests, LibraryDeletionTests, LibraryScanTests, and ThumbnailSwitchLifecycleTests.
Checks run:
- swift test --no-parallel --filter KromoraKitTests.MaskingWorkspaceTests (36 passed)
- swift test --no-parallel --filter KromoraKitTests.SourceSessionCoordinatorTests (4 passed)
- swift test --no-parallel --filter KromoraKitTests.EditPersistenceIntegrationTests (11 passed)
- swift build -c release (passed with two pre-existing warnings)
- scripts/ci-tests.sh fast (MaskingWorkspaceTests passed; unrelated failures listed above)
- git diff --check
Findings:
- The fast lane still has unrelated failures in CopyPasteTests, LibraryDeletionTests, LibraryScanTests, and ThumbnailSwitchLifecycleTests.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: unknown
Pickup session: 01MUD4VWSH10B21U92
Summary: Fresh foreground verification passed KRMA-539. The focused masking, source-session, and edit-persistence suites pass; the release build passes; the fast lane reports no MaskingWorkspaceTests failure. The fast lane remains nonzero only for unrelated CopyPaste, LibraryDeletion, LibraryScan, and ThumbnailSwitchLifecycle failures.
