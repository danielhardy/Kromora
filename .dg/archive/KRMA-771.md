---
id: KRMA-771
title: "KRMA-761 follow-up: assert one ledger record per lookup at each frame lookup site"
type: task
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Fake-frame-store tests assert exactly one FrameLookupLedger entry per lookup at beginStoredFrameLookup, OriginalThumbnailLoader.load, EditedThumbnailCoordinator.request, and ImageCollection frame application
      result: pass
      notes: Each site has a test checking record count, surface, and outcome. Collection test goes through applyLaunchFrames, which feeds applyStoredFrames.
    - criterion: Covers corrupt envelope without throwing, and missing file
      result: pass
    - criterion: Tests only; no decision changes
      result: pass
      notes: Commit d0c26e4 touches only Tests/ files.
  checks_run:
    - "swift test --filter EditedThumbnailCoordinatorTests|ImageCollectionFrameLookupTests|PreviewPresentationCoordinatorTests|ThumbnailTests: 43 tests, 0 failures"
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-02T14:34:48.827Z
  session: 01MUR2DOQTT5YVDC15
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - verification
created: 2026-10-02T14:21:06.945Z
updated: 2026-10-02T14:34:48.829Z
parent: KRMA-761
blockers: []
order: n
board: product
---

Add fake-frame-store tests proving PreviewPresentationCoordinator.beginStoredFrameLookup, OriginalThumbnailLoader.load, EditedThumbnailCoordinator.request and ImageCollection.applyStoredFrames each record exactly one FrameLookupLedger entry per lookup with the right surface and outcome, including corrupt envelope (no throw) and missing file. Tests only; no decision changes.


### Comment — codex @ 2026-10-02T14:34:16.100Z

Added lookup ledger assertions for preview presentation, original thumbnails, edited thumbnails, and collection frame application. Each path checks one entry per lookup, expected surface, and missing/corrupt outcomes; corrupt preview envelope is read without throwing. Focused tests passed, and scripts/ci-tests.sh fast passed (1,477 tests). Commit: d0c26e4.

## Agent log

- 2026-10-02T14:34:48.827Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Fake-frame-store tests assert exactly one FrameLookupLedger entry per lookup at beginStoredFrameLookup, OriginalThumbnailLoader.load, EditedThumbnailCoordinator.request, and ImageCollection frame application (pass) — Each site has a test checking record count, surface, and outcome. Collection test goes through applyLaunchFrames, which feeds applyStoredFrames.
- [x] Covers corrupt envelope without throwing, and missing file (pass)
- [x] Tests only; no decision changes (pass) — Commit d0c26e4 touches only Tests/ files.
Checks run:
- swift test --filter EditedThumbnailCoordinatorTests|ImageCollectionFrameLookupTests|PreviewPresentationCoordinatorTests|ThumbnailTests: 43 tests, 0 failures
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUR2DOQTT5YVDC15
