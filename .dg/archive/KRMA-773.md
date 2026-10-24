---
id: KRMA-773
title: "KRMA-763 follow-up: make fingerprint backfill start after launch and avoid stale shard overwrite"
type: task
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Define which work cancels backfill; make it resumable within a session; add session-level test
      result: pass
      notes: Browsing no longer cancels; shutdown is the boundary; running marker clears on attempt exit; async launch test added.
    - criterion: repairSourceFingerprints re-reads membership shard before each batch commit
      result: pass
      notes: Fresh shard read merged per batch, only still-nil fingerprints set. A small window remains between re-read and transaction begin, but the original-sized window of record reads is eliminated.
  checks_run:
    - swift test --filter PortableLibrarySessionTests (18 passed)
    - git diff --check
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-02T18:13:00.314Z
  session: 01MURA65Y2XPTBE252
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - verification
created: 2026-10-02T18:05:15.691Z
updated: 2026-10-02T18:13:00.317Z
parent: KRMA-763
blockers: []
order: n
board: product
---

1) startSourceFingerprintBackfill is blocked by hasUserVisibleLibraryWork, set by the launch reloadPortableWindow in onIndexLoadingStateChange; define which work cancels it, make it resumable within a session, and add a session-level test. 2) repairSourceFingerprints must re-read the membership shard right before each batch commit rather than reusing the shard read at shard start.


### Comment — codex @ 2026-10-02T18:12:23.625Z

Implemented and committed as 99501c5. Launch browsing/selection no longer suppresses source fingerprint backfill; shutdown is the cancellation boundary and the in-session running marker clears when an attempt exits. Repair rereads the membership shard for each batch and merges only still-missing fingerprints, preserving newer membership fields. Added an asynchronous launch session regression test. Verification: swift test --filter PortableLibrarySessionTests (18 passed); git diff --check passed.

## Agent log

- 2026-10-02T18:13:00.315Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Define which work cancels backfill; make it resumable within a session; add session-level test (pass) — Browsing no longer cancels; shutdown is the boundary; running marker clears on attempt exit; async launch test added.
- [x] repairSourceFingerprints re-reads membership shard before each batch commit (pass) — Fresh shard read merged per batch, only still-nil fingerprints set. A small window remains between re-read and transaction begin, but the original-sized window of record reads is eliminated.
Checks run:
- swift test --filter PortableLibrarySessionTests (18 passed)
- git diff --check
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MURA65Y2XPTBE252
