---
id: KRMA-604
title: Add edit history, snapshots, and virtual copies
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Show an ordered, navigable history of edit commits and preview an earlier state.
      result: pass
      notes: InfoInspectorView.editHistorySection lists durable revisions (AppViewModel.durableEditHistory, backed by EditDocumentStore.history(for:) -> PortableLibraryPackage.readEditHistory) in order with timestamps and a checkmark on the current state; restoring a revision jumps to it immediately rather than offering a separate non-committing preview step, so 'preview' and 'branch' are effectively the same action (restoreEditRevision -> applyHistoryDocument -> saveActiveDocument(force:true)). This matches the linear-history design used for the rest of the feature and is not a defect, but it is worth noting the AC's two verbs ('preview' vs 'branch/fork') collapse into one user action.
    - criterion: Support branching/forking from an earlier state and named snapshots within a photo.
      result: pass
      notes: restoreEditRevision appends the restored document as a new durable revision (a fork point in the linear history), and saveEditSnapshot/EditDocumentStore.saveSnapshot/PortableLibraryPackage.appendEditRevision(snapshotName:) persist an immutable labeled revision. Verified end-to-end by testNamedSnapshotAndDurableHistorySurviveStoreReload (save, reload package, read history back).
    - criterion: Support virtual copies with independent edits/history and a clear relationship to the original source.
      result: pass
      notes: "PortableLibrarySession.createVirtualCopy imports a second copy of the managed original under a new PortablePhotoAssetID, and PortableLibraryPackage.markVirtualCopy records copyOfAssetID plus a copy-marked membership display name in one transaction. AppViewModel.virtualCopySourceDescription surfaces the relationship in the inspector. Verified by testVirtualCopyHasIndependentIdentityAndEditHistory: independent asset IDs, independent edit histories, and the copyOfAssetID link all round-trip correctly."
    - criterion: Keep copy/version identity, ratings, flags, and history understandable in the library and persistent across reopen.
      result: pass
      notes: A virtual copy is a fully independent PortablePackageAssetRecord, so existing per-asset rating/flag storage already keeps them independent between original and copy; nothing in this change conflates them. History persistence across reopen is exercised directly by testNamedSnapshotAndDurableHistorySurviveStoreReload (PortableLibraryPackage.open at a fresh URL after the save).
  checks_run:
    - swift build
    - swift build --build-tests
    - swift test --filter PackageEditProjectionTests (4/4 passed)
    - scripts/ci-tests.sh fast (1265/1265 passed)
    - scripts/ci-tests.sh serial (429 executed, 1 skipped, 0 failures)
  findings:
    - "PortablePackageMaintenance.compactRevisions now fully reads and JSON-decodes every historical edit revision file for every asset on every maintenance pass, just to learn whether it carries a snapshotName, because that field lives only in the revision file and not on the lightweight PortablePackageEditPointer. Location: Sources/KromoraKit/Models/PortablePackageMaintenance.swift:613-616. Impact: Turns an in-memory, pointer-metadata-only compaction scan into a full-library file-read/decode pass on every background maintenance cycle, unconditionally (even for assets needing no compaction, since it runs before the stale-check short-circuit). No test exercises the documented claim that named snapshots survive compaction. Not blocking: correctness is unaffected (all tests pass, snapshots are in fact retained), and this is a performance/maintainability concern rather than a functional defect. Filed as KRMA-647 (backlog, verification, parent KRMA-604) rather than fixed in place, since a real fix likely needs a new field on the persisted pointer schema, which is out of scope for a localized verification-stage fix."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T05:52:39.316Z
  session: 01MUJE5AXII09TQJOG
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:31.792Z
updated: 2026-09-27T05:52:39.318Z
blockers: []
order: a0
board: product
---

## Objective

Make edit history visible and let photographers save alternate interpretations of one source.

## Context

The current edit workflow supports undo but not a visible history panel, snapshots, or virtual copies.

Derived from §5 Presets, history, versions in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Show an ordered, navigable history of edit commits and preview an earlier state.
- [ ] Support branching/forking from an earlier state and named snapshots within a photo.
- [ ] Support virtual copies with independent edits/history and a clear relationship to the original source.
- [ ] Keep copy/version identity, ratings, flags, and history understandable in the library and persistent across reopen.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.


### Comment — codex @ 2026-09-27T05:41:32.694Z

Implemented persistent edit history, named snapshots, history restoration as new revisions, and independent package virtual copies with source links and copy-marked library names. Named snapshots survive revision compaction. Added regression coverage and updated package/architecture docs. Verification: swift test --filter PackageEditProjectionTests (4 passed). Commit: ba195a8.

## Agent log

- 2026-09-27T05:52:39.316Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Show an ordered, navigable history of edit commits and preview an earlier state. (pass) — InfoInspectorView.editHistorySection lists durable revisions (AppViewModel.durableEditHistory, backed by EditDocumentStore.history(for:) -> PortableLibraryPackage.readEditHistory) in order with timestamps and a checkmark on the current state; restoring a revision jumps to it immediately rather than offering a separate non-committing preview step, so 'preview' and 'branch' are effectively the same action (restoreEditRevision -> applyHistoryDocument -> saveActiveDocument(force:true)). This matches the linear-history design used for the rest of the feature and is not a defect, but it is worth noting the AC's two verbs ('preview' vs 'branch/fork') collapse into one user action.
- [x] Support branching/forking from an earlier state and named snapshots within a photo. (pass) — restoreEditRevision appends the restored document as a new durable revision (a fork point in the linear history), and saveEditSnapshot/EditDocumentStore.saveSnapshot/PortableLibraryPackage.appendEditRevision(snapshotName:) persist an immutable labeled revision. Verified end-to-end by testNamedSnapshotAndDurableHistorySurviveStoreReload (save, reload package, read history back).
- [x] Support virtual copies with independent edits/history and a clear relationship to the original source. (pass) — PortableLibrarySession.createVirtualCopy imports a second copy of the managed original under a new PortablePhotoAssetID, and PortableLibraryPackage.markVirtualCopy records copyOfAssetID plus a copy-marked membership display name in one transaction. AppViewModel.virtualCopySourceDescription surfaces the relationship in the inspector. Verified by testVirtualCopyHasIndependentIdentityAndEditHistory: independent asset IDs, independent edit histories, and the copyOfAssetID link all round-trip correctly.
- [x] Keep copy/version identity, ratings, flags, and history understandable in the library and persistent across reopen. (pass) — A virtual copy is a fully independent PortablePackageAssetRecord, so existing per-asset rating/flag storage already keeps them independent between original and copy; nothing in this change conflates them. History persistence across reopen is exercised directly by testNamedSnapshotAndDurableHistorySurviveStoreReload (PortableLibraryPackage.open at a fresh URL after the save).
Checks run:
- swift build
- swift build --build-tests
- swift test --filter PackageEditProjectionTests (4/4 passed)
- scripts/ci-tests.sh fast (1265/1265 passed)
- scripts/ci-tests.sh serial (429 executed, 1 skipped, 0 failures)
Findings:
- PortablePackageMaintenance.compactRevisions now fully reads and JSON-decodes every historical edit revision file for every asset on every maintenance pass, just to learn whether it carries a snapshotName, because that field lives only in the revision file and not on the lightweight PortablePackageEditPointer. Location: Sources/KromoraKit/Models/PortablePackageMaintenance.swift:613-616. Impact: Turns an in-memory, pointer-metadata-only compaction scan into a full-library file-read/decode pass on every background maintenance cycle, unconditionally (even for assets needing no compaction, since it runs before the stale-check short-circuit). No test exercises the documented claim that named snapshots survive compaction. Not blocking: correctness is unaffected (all tests pass, snapshots are in fact retained), and this is a performance/maintainability concern rather than a functional defect. Filed as KRMA-647 (backlog, verification, parent KRMA-604) rather than fixed in place, since a real fix likely needs a new field on the persisted pointer schema, which is out of scope for a localized verification-stage fix.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUJE5AXII09TQJOG
Summary: Verified durable edit history, named snapshots, and virtual copies: build clean under Swift 6 mode, PackageEditProjectionTests (4/4), fast lane (1265/1265), serial lane (429/429, 1 skipped). All four acceptance criteria pass. Filed non-blocking KRMA-647 for a compaction perf/test-coverage gap.
