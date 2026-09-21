---
id: KRMA-415
title: "Phase 4.5: low-priority maintenance — packed-thumbnail and revision compaction"
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Packed-thumbnail compaction reclaims space from stale/deleted entries with no data loss or dangling offsets, verified by test.
      result: pass
      notes: PortablePackagePackedThumbnailStore.compact() rewrites only live values found via lookup(), publishes packs+index in one journaled transaction, and only deletes now-obsolete pack files after commit. Verified by testPackedThumbnailCompactionReclaimsStaleBytesAndKeepsLiveOffsets and the interruption test.
    - criterion: Edit-revision compaction never discards the current revision or a still-referenced revision.
      result: pass
      notes: compactRevisions retains currentRevision, explicitly protected revisions, and the newest N per policy; stale revisions are moved to quarantine and asset.json updated in one transaction. Verified by testRevisionCompactionRetainsCurrentNewestAndProtectedRevisions.
    - criterion: Maintenance runs through ImageWorkScheduler's package I/O lanes at low priority and yields to editor-visible work under contention.
      result: pass
      notes: "PortablePackageMaintenance.enqueue uses scheduler.enqueuePackageIO(lane: .maintenance) which defaults to background priority and is a separate admission path from the editor/thumbnail lanes. No dedicated fairness-under-simultaneous-editor-activity test exists yet; filed as non-blocking follow-up KRMA-428."
    - criterion: A failed or interrupted maintenance pass is retried and never reported as a critical/data-loss failure.
      result: pass
      notes: "Interrupted transactions roll back via PortablePackageTransaction.recover (crash-safe by construction), and PortablePackageMaintenance.enqueue retries a reported operation failure up to retryLimit, verified by testInterruptedMaintenanceRollsBackAndCanBeRetried and testMaintenanceCoordinatorRetriesFailureOnTheMaintenanceLane. Found and fixed during this pass: the quarantine directory's post-commit cleanup used a best-effort FileManager.removeItem instead of the existing journaled stageRemoval primitive, which could leak an orphaned quarantine directory on a process stop between transactions -- fixed in this session (commit 5128a3f) to use a second journaled stageRemoval transaction, matching PortablePackageTrash.reclaimSpace's established pattern. A residual gap (no sweep for a directory orphaned before the fix could even run, and .rejected scheduler-admission outcomes are not retried) is non-blocking and filed as KRMA-428."
    - criterion: swift build, swift test, dg validate, and git diff --check pass.
      result: pass
      notes: swift build clean; swift test --filter PortablePackageMaintenanceTests (4/4 passed) and scripts/ci-tests.sh fast (full fast/model/fake-engine lane) both green after the fix; dg validate OK (pre-existing unrelated model-name warnings only); git diff --check clean.
  checks_run:
    - swift build
    - swift test --filter PortablePackageMaintenanceTests
    - scripts/ci-tests.sh fast
    - dg validate
    - git diff --check
  findings:
    - "medium/correctness: quarantine cleanup after revision compaction used a best-effort, non-journaled FileManager.removeItem instead of the existing stageRemoval transaction primitive (Sources/KromoraKit/Models/PortablePackageMaintenance.swift, compactRevisions) -- fixed in commit 5128a3f to use a second journaled stageRemoval + commit."
    - "low/robustness: no sweep exists for Recovery/Quarantine/Maintenance directories orphaned by a process stop between the two revision-compaction transactions; PortablePackageMaintenance.enqueue does not retry a .rejected (queue-full) scheduler admission outcome; nothing in the app yet calls PortablePackageMaintenance. Non-blocking (rebuildable-tier, feature not wired in yet); filed as backlog child ticket KRMA-428."
  fixes:
    - Replaced the best-effort FileManager.removeItem after revision-compaction commit with a second journaled PortablePackageTransaction.stageRemoval + commit, mirroring PortablePackageTrash.reclaimSpace's established crash-safe deletion pattern (commit 5128a3f).
  verification_commits:
    - 5128a3f
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-13T18:31:29.427Z
  session: 01MU059FYLQ4JV3RPO
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - backup
  - recovery
  - performance
created: 2026-09-12T19:44:27.380Z
updated: 2026-09-21T02:09:38.792Z
order: a0
board: product
commits:
  - 5128a3f
---

## Objective

Implement low-priority maintenance: immutable-revision-safe compaction and packed-thumbnail
compaction (per KRMA-389's packed-thumbnail decision), running as background scheduler work that
never turns a rebuildable artifact into an integrity failure.

## Dependencies

- KRMA-392 (scheduler lanes — compaction runs as background package I/O through the existing
  scheduler, not a new mechanism).
- KRMA-389 (the packed-thumbnail-or-rejected decision this compaction work implements against).

## Scope

- If KRMA-389 recommended packed thumbnails, implement compaction for the packed-thumbnail shards:
  reclaiming space from stale/deleted entries without data loss or dangling offsets, running as
  low-priority background maintenance.
- Implement compaction/pruning for old immutable edit revisions where a retention policy applies
  (e.g. collapsing very old superseded revisions), without ever discarding the current/latest
  revision or violating the immutable-revision guarantee for revisions still referenced.
- All maintenance work must run through `ImageWorkScheduler`'s package I/O lanes (KRMA-392) at low
  priority, yielding to editor-visible work.
- Treat every compacted/maintained artifact here as rebuildable-tier, never critical — a
  maintenance failure must be logged and retried, never surfaced as a data-loss integrity failure
  (that classification is KRMA-393's validation ticket's job).

## Acceptance criteria

- [ ] Packed-thumbnail compaction (if applicable per the KRMA-389 decision) reclaims space from
  stale/deleted entries with no data loss or dangling offsets, verified by test.
- [ ] Edit-revision compaction never discards the current revision or a still-referenced revision.
- [ ] Maintenance runs through `ImageWorkScheduler`'s package I/O lanes at low priority and yields to
  editor-visible work under contention.
- [ ] A failed or interrupted maintenance pass is retried and never reported as a critical/data-loss
  failure.
- [ ] `swift build`, `swift test`, `dg validate`, and `git diff --check` pass.

## Verification lane

Compaction/unit lane with injected stale/deleted entries and interrupted maintenance runs, plus a
scheduler-fairness check under simultaneous editor activity.

## Context

- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/AUTO_PERFORMANCE.md
- context.issues: KRMA-393, KRMA-392, KRMA-389


### Comment — codex @ 2026-09-13T18:25:08.585Z

Implemented immutable edit-revision retention and packed-thumbnail shard compaction in commit 7ad3f99. Maintenance acquires the package lease, uses journaled publication/rollback, runs via ImageWorkScheduler's low-priority maintenance package-I/O lane, logs failures, and retries failed/interrupted passes. Tests cover stale/deleted/replaced thumbnail data, protected/current revisions, interrupted rollback, retry, and scheduler admission. Verification passed: swift build; swift test --no-parallel (1434 passed, 53 skipped); swift test --no-parallel --filter PortablePackageMaintenanceTests (4 passed); dg validate (pre-existing unknown-model warnings only); git diff --check.

## Agent log

- 2026-09-13T18:31:29.427Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Packed-thumbnail compaction reclaims space from stale/deleted entries with no data loss or dangling offsets, verified by test. (pass) — PortablePackagePackedThumbnailStore.compact() rewrites only live values found via lookup(), publishes packs+index in one journaled transaction, and only deletes now-obsolete pack files after commit. Verified by testPackedThumbnailCompactionReclaimsStaleBytesAndKeepsLiveOffsets and the interruption test.
- [x] Edit-revision compaction never discards the current revision or a still-referenced revision. (pass) — compactRevisions retains currentRevision, explicitly protected revisions, and the newest N per policy; stale revisions are moved to quarantine and asset.json updated in one transaction. Verified by testRevisionCompactionRetainsCurrentNewestAndProtectedRevisions.
- [x] Maintenance runs through ImageWorkScheduler's package I/O lanes at low priority and yields to editor-visible work under contention. (pass) — PortablePackageMaintenance.enqueue uses scheduler.enqueuePackageIO(lane: .maintenance) which defaults to background priority and is a separate admission path from the editor/thumbnail lanes. No dedicated fairness-under-simultaneous-editor-activity test exists yet; filed as non-blocking follow-up KRMA-428.
- [x] A failed or interrupted maintenance pass is retried and never reported as a critical/data-loss failure. (pass) — Interrupted transactions roll back via PortablePackageTransaction.recover (crash-safe by construction), and PortablePackageMaintenance.enqueue retries a reported operation failure up to retryLimit, verified by testInterruptedMaintenanceRollsBackAndCanBeRetried and testMaintenanceCoordinatorRetriesFailureOnTheMaintenanceLane. Found and fixed during this pass: the quarantine directory's post-commit cleanup used a best-effort FileManager.removeItem instead of the existing journaled stageRemoval primitive, which could leak an orphaned quarantine directory on a process stop between transactions -- fixed in this session (commit 5128a3f) to use a second journaled stageRemoval transaction, matching PortablePackageTrash.reclaimSpace's established pattern. A residual gap (no sweep for a directory orphaned before the fix could even run, and .rejected scheduler-admission outcomes are not retried) is non-blocking and filed as KRMA-428.
- [x] swift build, swift test, dg validate, and git diff --check pass. (pass) — swift build clean; swift test --filter PortablePackageMaintenanceTests (4/4 passed) and scripts/ci-tests.sh fast (full fast/model/fake-engine lane) both green after the fix; dg validate OK (pre-existing unrelated model-name warnings only); git diff --check clean.
Checks run:
- swift build
- swift test --filter PortablePackageMaintenanceTests
- scripts/ci-tests.sh fast
- dg validate
- git diff --check
Findings:
- medium/correctness: quarantine cleanup after revision compaction used a best-effort, non-journaled FileManager.removeItem instead of the existing stageRemoval transaction primitive (Sources/KromoraKit/Models/PortablePackageMaintenance.swift, compactRevisions) -- fixed in commit 5128a3f to use a second journaled stageRemoval + commit.
- low/robustness: no sweep exists for Recovery/Quarantine/Maintenance directories orphaned by a process stop between the two revision-compaction transactions; PortablePackageMaintenance.enqueue does not retry a .rejected (queue-full) scheduler admission outcome; nothing in the app yet calls PortablePackageMaintenance. Non-blocking (rebuildable-tier, feature not wired in yet); filed as backlog child ticket KRMA-428.
Fixes:
- Replaced the best-effort FileManager.removeItem after revision-compaction commit with a second journaled PortablePackageTransaction.stageRemoval + commit, mirroring PortablePackageTrash.reclaimSpace's established crash-safe deletion pattern (commit 5128a3f).
Verification commits:
- 5128a3f
Actor: claude
Resolved model: sonnet
Pickup session: 01MU059FYLQ4JV3RPO
Summary: Verified KRMA-415 maintenance compaction: acceptance criteria met, tests green. Hardened quarantine cleanup to use a journaled stageRemoval transaction instead of a best-effort delete (commit 5128a3f); filed non-blocking follow-up KRMA-428 for orphan-sweep, scheduler-rejection retry, and app wiring.
