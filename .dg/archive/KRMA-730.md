---
id: KRMA-730
title: Make Look signatures content-addressed and scans delta-aware
type: task
status: done
priority: high
agent: claude
verification_agent: codex
thinking: high
verification_model: gpt-6-luna
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Shared LookSignature distinguishes none, resolved, and unresolved; unresolved values cannot be exact cache hits.
      result: pass
    - criterion: Package revisions expose Look identity from PortablePackageLookReference.contentHash without adding digest to EditDocument.
      result: pass
    - criterion: Live CubeLUT content changes alter its signature at the same LUTID.
      result: pass
    - criterion: Byte-identical scans cause no render admissions or broad LUT cache invalidation.
      result: pass
    - criterion: Changed referenced Looks refresh only affected active or visible assets; unrelated Look changes cause no image work.
      result: pass
      notes: Verification fix scopes thumbnail refreshes to the current active/visible set.
    - criterion: Appearing and disappearing Looks transition through unresolved/resolved states without exact reuse across states.
      result: pass
    - criterion: Scan deltas, replaced bytes at the same path, unchanged rescans, package/live signatures, and existing portability behaviors have deterministic coverage.
      result: pass
  checks_run:
    - Targeted swift test for LUTLibraryTests, LUTIDTests, LookSignatureTests, PreviewPresentationCoordinatorTests, and EditedThumbnailCoordinatorTests (53 tests, 0 failures)
    - scripts/ci-tests.sh fast (exit 0; 1375 tests)
    - git diff --check (clean)
    - dg validate (OK; model-name warnings only)
  findings: []
  fixes:
    - Limited scan-triggered edited-thumbnail refreshes to active and currently visible assets; added a regression test proving offscreen materialized thumbnails are skipped.
  verification_commits:
    - afb5160
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-09-30T15:00:11.661Z
  session: 01MUO86F2W6UP8O8GC
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - performance
  - reliability
  - looks
  - caching
created: 2026-09-30T13:19:18.910Z
updated: 2026-09-30T15:00:11.663Z
blockers: []
estimate: 5
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/Models/CubeLUT.swift
    - Sources/KromoraKit/Models/LUTLibrary.swift
    - Sources/KromoraKit/Models/LUTSettings.swift
    - Sources/KromoraKit/Models/PortablePackageEditSidecar.swift
    - Sources/KromoraKit/Models/EditDocumentStore.swift
    - Sources/KromoraKit/Models/RenderEngine.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
    - Sources/KromoraKit/ViewModels/PreviewPresentationCoordinator.swift
    - Sources/KromoraKit/ViewModels/EditedThumbnailCoordinator.swift
    - Tests/KromoraKitTests/PreviewPresentationCoordinatorTests.swift
    - Tests/KromoraKitTests/EditedThumbnailCoordinatorTests.swift
  docs:
    - .context/last-known-frame-plan.md
    - docs/ENGINEERING_GUIDE.md
    - docs/STORAGE_POLICY.md
  issues: []
  commands:
    - swift test --filter 'LUTLibraryTests|LUTIDTests|LookSignatureTests|PreviewPresentationCoordinatorTests|EditedThumbnailCoordinatorTests'
    - scripts/ci-tests.sh fast
    - git diff --check
    - dg validate
commits:
  - afb5160
---

## Objective

Make preview and thumbnail identity independent of Look scan timing, and re-render only assets whose
referenced Look bytes actually changed.

## Context

The reviewed contract is Phase 2 of `.context/last-known-frame-plan.md`.

Current keys use `request.lut?.cacheFingerprint ?? "unresolved"`. A persisted `LUTID` can therefore
render/cache once before the Look scan and again after it. `AppViewModel.library.onScanned` always
invalidates the entire engine LUT cache and re-admits the current preview and every materialized
edited thumbnail.

Do not add a digest to `EditDocument`. Package edit revisions already contain
`PortablePackageLookReference.contentHash` and a content-addressed blob. That hash is the durable
identity for a saved edit. Live/unsaved Look state can use the content digest already represented by
`CubeLUT.cacheFingerprint`.

Introduce a shared Sendable `LookSignature` with three semantic states: `none`,
`resolved(LUTID, contentHash)`, and `unresolved(LUTID)`. `none` and `unresolved` must never compare
equal. An unresolved signature may label provisional pixels but cannot yield an exact cache hit.

Have `LUTLibrary` publish a value snapshot `[LUTID: contentHash]` with each completed scan. Compare
old and new snapshots and determine changed/appeared/disappeared IDs. Scope engine invalidation and
preview/thumbnail re-admission to referenced changed IDs. An unrelated or byte-identical scan must
not enter the renderer.

Package-backed load results need a clean seam to expose the current revision's Look content hash
without rereading or duplicating the blob. Keep package sidecars authoritative and retain the
existing missing-Look status behavior.

## Acceptance criteria

- [ ] One shared `LookSignature` is used by preview and edited-thumbnail pixel identity. An
      `unresolved` signature never produces an exact-match classification or cache hit, and
      `none` never equals `unresolved` (asserted on values, not on string contents).
- [ ] The current package edit revision resolves its signature from
      `PortablePackageLookReference.contentHash`; no digest is added to `EditDocument`.
- [ ] A live `CubeLUT` signature changes when table bytes change at the same `LUTID`.
- [ ] A byte-identical scan triggers zero preview render admissions, zero edited-thumbnail render
      admissions, and no broad engine LUT-cache invalidation.
- [ ] A changed referenced Look invalidates/re-renders only affected active or visible assets. An
      unrelated Look change updates browser state without image work.
- [ ] A Look appearing or disappearing moves the reference through explicit unresolved/resolved
      state and cannot reuse an exact result from the other state.
- [ ] Scan snapshot/delta and package/live signature behavior have deterministic tests, including
      same path with replaced bytes and unchanged rescans. New tests live in `LUTLibraryTests` and
      `LookSignatureTests` (create them if absent).
- [ ] Existing embedded-Look portability, missing-reference messaging, export resolution, and
      derived-LUT save behavior remain correct.

## Implementation notes

- Prefer a value snapshot and set difference over callbacks that directly schedule global work.
- If engine invalidation cannot initially target one LUT ID, add that narrow API; do not retain a
  blanket invalidation on every scan.
- Keep parsing and file I/O off the main actor and preserve current scan generation fences.

### Comment — claude @ 2026-09-30T14:53:15.514Z

Implemented LookSignature (none/resolved/unresolved) shared by preview disk-cache keys and edited-thumbnail revisions; CubeLUT.contentHash (SHA-256 of file bytes, matches PortablePackageLookReference.contentHash); EditDocumentLoadResult.lookSignature from the package reference; LUTLibrary snapshot + LookLibraryDelta; scoped invalidateLUTCache(ids:) and thumbnail/preview re-admission for referenced IDs only. Byte-identical or unrelated scans do no renderer work. Tests: LookSignatureTests, LUTLibraryTests, AppViewModel/EditedThumbnail additions; scripts/ci-tests.sh fast passes (one earlier run had a load-related timeout in CopyPasteTests that passes alone and on rerun).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-30T15:00:11.661Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Shared LookSignature distinguishes none, resolved, and unresolved; unresolved values cannot be exact cache hits. (pass)
- [x] Package revisions expose Look identity from PortablePackageLookReference.contentHash without adding digest to EditDocument. (pass)
- [x] Live CubeLUT content changes alter its signature at the same LUTID. (pass)
- [x] Byte-identical scans cause no render admissions or broad LUT cache invalidation. (pass)
- [x] Changed referenced Looks refresh only affected active or visible assets; unrelated Look changes cause no image work. (pass) — Verification fix scopes thumbnail refreshes to the current active/visible set.
- [x] Appearing and disappearing Looks transition through unresolved/resolved states without exact reuse across states. (pass)
- [x] Scan deltas, replaced bytes at the same path, unchanged rescans, package/live signatures, and existing portability behaviors have deterministic coverage. (pass)
Checks run:
- Targeted swift test for LUTLibraryTests, LUTIDTests, LookSignatureTests, PreviewPresentationCoordinatorTests, and EditedThumbnailCoordinatorTests (53 tests, 0 failures)
- scripts/ci-tests.sh fast (exit 0; 1375 tests)
- git diff --check (clean)
- dg validate (OK; model-name warnings only)
Findings:
- None
Fixes:
- Limited scan-triggered edited-thumbnail refreshes to active and currently visible assets; added a regression test proving offscreen materialized thumbnails are skipped.
Verification commits:
- afb5160
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MUO86F2W6UP8O8GC
Summary: Verified content-addressed Look identity and delta-aware scans; scoped refresh to active/visible thumbnails. Targeted and fast test suites pass.
