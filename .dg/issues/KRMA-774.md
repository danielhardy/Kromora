---
id: KRMA-774
title: "KRMA-763 follow-up: fix multi-paste regression from real grid fingerprints"
type: task
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Multi-paste test passes and each destination can undo
      result: pass
      notes: CopyPasteTests pass; fix routes by activeSourceReference and restores matching session
    - criterion: Fast lane green
      result: pass
      notes: Fast lane showed one intermittent failure in WarmReopenPresentationTests, which also reproduces at 99501c5 before this change; paste is unrelated. Tracked in KRMA-775.
  checks_run:
    - swift test --filter CopyPasteTests (pass)
    - scripts/ci-tests.sh fast (one pre-existing flaky failure, see KRMA-775)
    - flake repro at 99501c5 and HEAD
  findings:
    - "Low: pre-existing flaky WarmReopenPresentationTests.testReplacedSourceNeverShowsTheStoredFrame; ticket KRMA-775"
  fixes: []
  verification_commits:
    - bee9c23
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-02T18:43:35.954Z
  session: 01MURB58M4E5E4FZT9
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - verification
created: 2026-10-02T18:24:55.326Z
updated: 2026-10-02T18:43:35.956Z
parent: KRMA-763
blockers: []
order: n
board: product
commits:
  - bee9c23
---

CopyPasteTests.testMultiPasteUpdatesOnlySelectedPhotosAndEachDestinationCanUndo (EditClipboardTests.swift:357) fails at HEAD, passes at 2372ab2. Pasted edits on non-active selected photos are not seen when opening them (document is identity, undoDepth 0). Grid items now carry real fingerprints and skip materializedAsset in openImage; find why the stored edit identity no longer matches, fix product code or test fixture, and get the fast lane green.


### Comment — codex @ 2026-10-02T18:39:38.533Z

Fixed multi-paste routing to follow the active source reference while selection focus changes, preserving each destination's edit session and undo history. Verification: CopyPasteTests passed (6 tests); scripts/ci-tests.sh fast passed (1,482 tests, exit 0). Commit: bee9c23.

## Agent log

- 2026-10-02T18:43:35.954Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Multi-paste test passes and each destination can undo (pass) — CopyPasteTests pass; fix routes by activeSourceReference and restores matching session
- [x] Fast lane green (pass) — Fast lane showed one intermittent failure in WarmReopenPresentationTests, which also reproduces at 99501c5 before this change; paste is unrelated. Tracked in KRMA-775.
Checks run:
- swift test --filter CopyPasteTests (pass)
- scripts/ci-tests.sh fast (one pre-existing flaky failure, see KRMA-775)
- flake repro at 99501c5 and HEAD
Findings:
- Low: pre-existing flaky WarmReopenPresentationTests.testReplacedSourceNeverShowsTheStoredFrame; ticket KRMA-775
Fixes:
- None
Verification commits:
- bee9c23
Actor: claude
Resolved model: sonnet
Pickup session: 01MURB58M4E5E4FZT9
Summary: Verified multi-paste fix; unrelated pre-existing flake filed as KRMA-775
