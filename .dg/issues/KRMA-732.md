---
id: KRMA-732
title: Persist runtime thumbnail frames and stable presentation geometry
type: task
status: done
priority: urgent
agent: codex
verification_agent: codex
thinking: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Production Library and filmstrip use packed original and edited thumbnail frames, decoding or rendering only on miss or stale refinement
      result: pass
      notes: Reviewed runtime wiring through OriginalThumbnailLoader, ImageCollection, and EditedThumbnailCoordinator; focused relaunch, exact-hit, stale refinement, and lifecycle tests passed.
    - criterion: Stable original/latest-edited keys retain at most two live records per asset and compaction reclaims replaced bytes
      result: pass
      notes: Stable key/replacement/relaunch test and packed maintenance compaction test passed.
    - criterion: Exact edited records skip rendering; stale records remain visible during refinement; failed renders preserve same-asset pixels
      result: pass
      notes: Focused coordinator and thumbnail lifecycle tests passed.
    - criterion: Source fingerprint or package identity changes make stored frames unusable
      result: pass
      notes: Shared classifier identity tests and stale-source lifecycle tests passed.
    - criterion: Edit revision and presented geometry publish transactionally, including rollback on injected failure
      result: pass
      notes: Added regression coverage for a publish fault and unreadable membership shard; edit and geometry remain paired.
    - criterion: Grid and filmstrip geometry is stable across pixel arrival, originals fit, and edits fill
      result: pass
      notes: Reviewed layout binding and geometry projection; LibraryGridTests and thumbnail lifecycle tests passed.
    - criterion: Identity and reset-to-original clear edited pixels, fill mode, and crop
      result: pass
      notes: Reviewed identity publication/removal path; identity and presentation lifecycle tests passed.
    - criterion: Visible-window frame reads are limited to four concurrent reads and visible IDs plus one prefetch page, and yield to editor work
      result: pass
      notes: Named policy bounds and scheduler lane reviewed; window-bound and scheduler tests passed.
    - criterion: Missing or corrupt derived thumbnail data remains a cache miss and does not fail package open or validation
      result: pass
      notes: Runtime facade converts index/offset/decode faults to misses and loaders regenerate from source; package validation and frame-envelope corruption tests passed.
    - criterion: Focused coverage includes freshness states, relaunch, geometry, interruption, and compaction
      result: pass
      notes: Focused frame, coordinator, lifecycle, package-maintenance, and new transaction regression tests passed.
  checks_run:
    - swift test --filter 'PortablePackageMaintenanceTests|EditedThumbnailCoordinatorTests|ThumbnailSwitchLifecycleTests|ThumbnailTests|LibraryGridTests|PortableLibraryPackageTests.testEditCommitAbortsWhenMembershipGeometryCannotBeRead' (70 passed)
    - swift test --filter 'PortableLibraryPackageTests.test(EditCommitAbortsWhenMembershipGeometryCannotBeRead|EditRevisionAndPresentedGeometryPublishOrRollbackTogether)' (2 passed)
    - scripts/ci-tests.sh fast (exit 0; 1,444 tests)
    - scripts/ci-tests.sh serial (exit 0; 455 tests, 1 skipped)
    - scripts/ci-tests.sh identity (exit 0; 4 tests)
    - git diff --check (exit 0)
    - dg validate (exit 0; emitted existing agent/model-name warnings)
  findings:
    - "Fixed during verification: stagePresentedAspectRatio swallowed membership shard read errors, which could let a new edit revision commit while library geometry remained old."
  fixes:
    - Propagate membership shard read errors so edit and geometry transaction abort together; added corruption and injected publish-failure regression tests.
  verification_commits:
    - 64e18806319289e5e2d7c38179ceb0d0e866a104
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-30T19:43:52.914Z
  session: 01MUOI0E8HX54T84MQ
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - architecture
  - performance
  - reliability
  - thumbnails
  - library
created: 2026-09-30T13:19:20.050Z
updated: 2026-09-30T19:43:52.916Z
depends_on:
  - KRMA-730
  - KRMA-731
blockers: []
estimate: 8
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/Models/PortablePackageMaintenance.swift
    - Sources/KromoraKit/Models/PortableLibraryPackage.swift
    - Sources/KromoraKit/Models/PortablePackageEditSidecar.swift
    - Sources/KromoraKit/Models/PortableLibrarySession.swift
    - Sources/KromoraKit/Models/LibraryQueryController.swift
    - Sources/KromoraKit/Models/ImageCollection.swift
    - Sources/KromoraKit/Models/Thumbnails.swift
    - Sources/KromoraKit/ViewModels/EditedThumbnailCoordinator.swift
    - Sources/KromoraKit/Views/LibraryGridView.swift
    - Sources/KromoraKit/Views/FilmstripView.swift
    - Tests/KromoraKitTests/PortablePackageMaintenanceTests.swift
    - Tests/KromoraKitTests/EditedThumbnailCoordinatorTests.swift
    - Tests/KromoraKitTests/ThumbnailSwitchLifecycleTests.swift
  docs:
    - .context/last-known-frame-plan.md
    - docs/STORAGE_POLICY.md
    - docs/ENGINEERING_GUIDE.md
    - docs/LIBRARY_PACKAGE_PLAN.md
  issues: []
  commands:
    - swift test --filter 'PortablePackageMaintenanceTests|EditedThumbnailCoordinatorTests|ThumbnailSwitchLifecycleTests|ThumbnailTests|LibraryGridTests'
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - scripts/ci-tests.sh identity
    - git diff --check
    - dg validate
commits:
  - 64e18806319289e5e2d7c38179ceb0d0e866a104
---

## Objective

Use the existing package thumbnail packs at runtime so Library and filmstrip paint their last edited
appearance and final geometry on first layout, without source-to-edited swaps after relaunch.

## Context

Implement Phase 4 of `.context/last-known-frame-plan.md`. Reuse the shared frame signature and
classifier from KRMA-731 and the deterministic Look identity from KRMA-730.

`PortablePackagePackedThumbnailStore` currently exists only for maintenance/tests. Runtime original
thumbnails are decoded from source every launch, and edited thumbnails are rendered into memory.
`ImageCollection.Item.libraryAspectRatio` and `shouldFillLibraryThumbnail` change only after edited
work publishes, causing layout reflow and an original-to-edited flash.

Add an actor-isolated `ThumbnailFrameStore` facade over the packed store. Its stable keys retain at
most `original` and `latestEdited` records per asset. Each record carries the shared source/signature,
geometry, raster color-space metadata, and JPEG bytes. Replacing a stable key appends and moves the
index pointer; existing package maintenance compacts unreachable bytes. Runtime corruption/stale
offsets are misses, never package-open failures.

Read order for a visible window is memory -> packed record -> source decode/render. Admit bounded
frame reads for the complete visible ID set before edited rendering. Exact edited records publish
and skip render; stale records stay visible while one demand-driven render refines them; failures
leave the best same-asset record visible. Reset-to-identity publishes/stores the original and removes
or supersedes the edited pointer.

Make geometry independent of raster arrival. Add optional `presentedAspectRatio` to
`PortablePackageAssetSummary` and publish it in the same package transaction that advances an edit
revision. Copy it into the local index. It is denormalized metadata rebuildable from the current edit
sidecar. Missing values from old packages fall back to source aspect and are repaired on the next
edit commit or explicit projection repair; do not make old packages fail to decode.

Grid/filmstrip cells reserve the presented ratio immediately. Original fallback pixels use `.fit`
inside that final frame; edited pixels use `.fill`. Publishing pixels must not change cell size.
Remove broad `refreshMaterializedEditedThumbnails` waves once signature/delta admission covers the
affected visible assets.

## Acceptance criteria

- [ ] Production Library and filmstrip read/write packed original and edited thumbnail records;
      source decoding/rendering occurs only on miss or stale refinement.
- [ ] Stable keys keep at most two live index entries per asset. Replacements do not accumulate live
      exact-edit keys, and compaction reclaims superseded bytes.
- [ ] Exact edited records skip rendering after relaunch. Stale records never regress to original
      while replacement work runs, and failed work preserves the last same-asset bitmap.
- [ ] Source fingerprint/package identity changes make both record kinds unusable.
- [ ] Edit persistence and membership summary publish the current `presentedAspectRatio`
      transactionally; injected failure cannot expose a new edit with old geometry or the reverse.
- [ ] `libraryAspectRatio` is correct before pixel publication and does not change when original or
      edited pixels arrive. Original fallback fits within the reserved edited geometry.
- [ ] Identity edits and reset-to-original clear edited presentation without leaving a stale fill
      mode or crop.
- [ ] Visible-window frame reads use a named concurrency limit (initially 4 concurrent reads) and
      a per-window cap of the visible IDs plus one prefetch page, both asserted in tests. Reads
      precede render admission and yield immediately to editor work through `ImageWorkScheduler`
      priorities.
- [ ] Missing/corrupt packs and deletion of `Derived/Thumbnails` regenerate normally and never make
      the package fail validation/open.
- [ ] Focused tests cover exact/stale/missing/identity states, relaunch, delayed obsolete completion,
      geometry stability, pack interruption, and compaction.

## Implementation notes

- Keep package truth in edit revisions; summary geometry is denormalized and recoverable.
- Do not synchronously instantiate/read the packed store on the main actor.
- Do not introduce one file per thumbnail; preserve sharded packs and maintenance semantics.
- Keep `Thumbnails.cache` as the bounded in-memory front tier.

### Comment — codex @ 2026-09-30T19:11:48.354Z

Pickup recovery: the prior Claude run hit the provider five-hour session limit (see .dg/.project/pickup/01MUOF2AY72CK8XZOB.log) and DispatchGraph scheduled retry for 2026-09-30 19:19:50 UTC. The last build also failed because Tests/KromoraKitTests/EditedThumbnailCoordinatorTests.swift FakeDestination no longer conforms to EditedThumbnailDestination; address that before continuing. I changed the preferred implementation agent to codex and removed the Claude-only model override so pickup follows the configured Codex runner/model. Continue from the existing shared working tree and preserve its uncommitted changes.

### Comment — codex @ 2026-09-30T19:28:29.505Z

Implemented persisted runtime thumbnail frames and transactional presented geometry; bounded visible-window reads and stable original/latest-edited keys are wired into Library and filmstrip. Verification passed: focused 69 tests, fast 1,443 tests (exit 0), serial 455 tests with 1 skipped (exit 0), identity 4 tests (exit 0), dg validate, and git diff --check. Commit: b87d1de.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-30T19:43:52.914Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Production Library and filmstrip use packed original and edited thumbnail frames, decoding or rendering only on miss or stale refinement (pass) — Reviewed runtime wiring through OriginalThumbnailLoader, ImageCollection, and EditedThumbnailCoordinator; focused relaunch, exact-hit, stale refinement, and lifecycle tests passed.
- [x] Stable original/latest-edited keys retain at most two live records per asset and compaction reclaims replaced bytes (pass) — Stable key/replacement/relaunch test and packed maintenance compaction test passed.
- [x] Exact edited records skip rendering; stale records remain visible during refinement; failed renders preserve same-asset pixels (pass) — Focused coordinator and thumbnail lifecycle tests passed.
- [x] Source fingerprint or package identity changes make stored frames unusable (pass) — Shared classifier identity tests and stale-source lifecycle tests passed.
- [x] Edit revision and presented geometry publish transactionally, including rollback on injected failure (pass) — Added regression coverage for a publish fault and unreadable membership shard; edit and geometry remain paired.
- [x] Grid and filmstrip geometry is stable across pixel arrival, originals fit, and edits fill (pass) — Reviewed layout binding and geometry projection; LibraryGridTests and thumbnail lifecycle tests passed.
- [x] Identity and reset-to-original clear edited pixels, fill mode, and crop (pass) — Reviewed identity publication/removal path; identity and presentation lifecycle tests passed.
- [x] Visible-window frame reads are limited to four concurrent reads and visible IDs plus one prefetch page, and yield to editor work (pass) — Named policy bounds and scheduler lane reviewed; window-bound and scheduler tests passed.
- [x] Missing or corrupt derived thumbnail data remains a cache miss and does not fail package open or validation (pass) — Runtime facade converts index/offset/decode faults to misses and loaders regenerate from source; package validation and frame-envelope corruption tests passed.
- [x] Focused coverage includes freshness states, relaunch, geometry, interruption, and compaction (pass) — Focused frame, coordinator, lifecycle, package-maintenance, and new transaction regression tests passed.
Checks run:
- swift test --filter 'PortablePackageMaintenanceTests|EditedThumbnailCoordinatorTests|ThumbnailSwitchLifecycleTests|ThumbnailTests|LibraryGridTests|PortableLibraryPackageTests.testEditCommitAbortsWhenMembershipGeometryCannotBeRead' (70 passed)
- swift test --filter 'PortableLibraryPackageTests.test(EditCommitAbortsWhenMembershipGeometryCannotBeRead|EditRevisionAndPresentedGeometryPublishOrRollbackTogether)' (2 passed)
- scripts/ci-tests.sh fast (exit 0; 1,444 tests)
- scripts/ci-tests.sh serial (exit 0; 455 tests, 1 skipped)
- scripts/ci-tests.sh identity (exit 0; 4 tests)
- git diff --check (exit 0)
- dg validate (exit 0; emitted existing agent/model-name warnings)
Findings:
- Fixed during verification: stagePresentedAspectRatio swallowed membership shard read errors, which could let a new edit revision commit while library geometry remained old.
Fixes:
- Propagate membership shard read errors so edit and geometry transaction abort together; added corruption and injected publish-failure regression tests.
Verification commits:
- 64e18806319289e5e2d7c38179ceb0d0e866a104
Actor: codex
Resolved model: unknown
Pickup session: 01MUOI0E8HX54T84MQ
Summary: Verification passed; fixed transactional geometry projection failure and ran all declared checks.
