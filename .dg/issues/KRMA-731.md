---
id: KRMA-731
title: Replace PreviewDiskCache with a latest-preview frame store
type: task
status: done
priority: urgent
agent: claude
verification_agent: codex
model: sonnet
thinking: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The classifier covers every source/edit/Look/space/pixel-epoch/storage-resolution row and is the only freshness implementation used by preview callers.
      result: pass
      notes: Classifier and warm-reopen suites passed; current-frame freshness is centralized in FrameClassifier.
    - criterion: Envelope decoding is bounded and rejects bad magic, truncation/overflow, identity mismatch, invalid dimensions, corrupt JPEG, and unsupported format without affecting other entries.
      result: pass
      notes: LatestPreviewFrameStoreTests passed, including corrupt-entry isolation, unsupported versions, bounds, identity, dimension, and non-JPEG payload cases.
    - criterion: There is at most one durable 2048 px preview per asset; writes are atomic/coalesced and no cache operation performs synchronous main-actor directory enumeration.
      result: pass
      notes: Store tests cover replacement, coalescing, cap, pinning, lazy cleanup, and actor-backed index loading.
    - criterion: Exact warm reopen submits zero preview renders and admits histogram/supporting work exactly once through the confirmed publication tail.
      result: pass
      notes: Warm-reopen and admission tests passed for zero render submissions and one confirmed histogram admission.
    - criterion: Stale/provisional warm reopen shows target pixels before source preparation completes, submits one settled render, and produces at most one replacement.
      result: pass
      notes: Warm-reopen tests passed; KRMA-735 now wires the stale replacement to one digest-gated 120 ms surface crossfade, covered by PreviewSurfaceTests.
    - criterion: Pixel epoch bumps preserve/show frames as stale-compatible. Storage incompatibility is a local miss. No version change wipes unrelated files.
      result: pass
      notes: Classifier and store regressions passed for pixel epoch and per-entry storage version behavior.
    - criterion: Source replacement, package identity mismatch, and raster-space incompatibility never show the stored frame.
      result: pass
      notes: Classifier and warm-reopen identity tests passed, including replaced sources and incompatible raster spaces.
    - criterion: Interactive, ROI, comparison, embedded, provisional, and failed output never writes the store. Canonical settled output does.
      result: pass
      notes: Publication and admission tests passed for excluded paths and canonical settled writes.
    - criterion: Legacy exact-key JPEGs are ignored and removed lazily; PreviewDiskCache and its old exact-key production path are removed.
      result: pass
      notes: Store regression passed for lazy legacy cleanup; production uses LatestPreviewFrameStore.
    - criterion: Focused, fast, serial, and identity gates pass with no Swift 6 escape hatch.
      result: pass
      notes: "Focused preview/store/classifier/surface run: 113 passed. Fast: 1,441 passed. Serial: 455 run, 1 skipped, 0 failures. Identity: 4 passed including 1,000-asset relocation. Updated the stale MenuCommandTests assertion after the serial rerun exposed that the inspector action had moved to MenuCommands; the focused test and full serial lane then passed."
  checks_run:
    - swift test --filter PreviewDiskCacheTests|PreviewAdmissionCoordinatorTests|PreviewPresentationCoordinatorTests|PreviewPublicationCoordinatorTests|LatestPreviewFrameStoreTests|PresentationFrameClassifierTests|FrameRefinementPolicyTests|PreviewSurfaceTests — passed, 113 tests, exit 0
    - scripts/ci-tests.sh fast — passed, 1,441 tests, exit 0
    - scripts/ci-tests.sh serial — passed, 455 tests, 1 skipped, 0 failures, exit 0
    - scripts/ci-tests.sh identity — passed, 4 tests including 1,000-asset relocation, exit 0
    - swift test --no-parallel --filter MenuCommandTests/testViewMenuRoutesRelocatedEditorActionsAndKeepsComparisonToolbarStable — passed, exit 0
    - git diff --check — passed
    - dg validate — OK; existing model-name warnings
  findings: []
  fixes:
    - Updated the stale MenuCommandTests expectation to verify toggleInspector is handled by MenuCommands after the action relocation; added an assertion that it is absent from ContentView.
  verification_commits:
    - 9433d61
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-30T18:06:09.036Z
  session: 01MUOEHLX3UBX8C1OO
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - architecture
  - performance
  - reliability
  - preview
  - caching
created: 2026-09-30T13:19:19.473Z
updated: 2026-09-30T18:06:09.039Z
depends_on:
  - KRMA-729
  - KRMA-730
  - KRMA-735
blockers: []
estimate: 8
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/Models/PreviewDiskCache.swift
    - Sources/KromoraKit/Models/RenderPipeline.swift
    - Sources/KromoraKit/Models/RenderEngine.swift
    - Sources/KromoraKit/Models/RenderEngineResources.swift
    - Sources/KromoraKit/ViewModels/PreviewPresentationCoordinator.swift
    - Sources/KromoraKit/ViewModels/PreviewAdmissionCoordinator.swift
    - Sources/KromoraKit/ViewModels/PreviewPublicationCoordinator.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
    - Tests/KromoraKitTests/PreviewDiskCacheTests.swift
    - Tests/KromoraKitTests/PreviewAdmissionCoordinatorTests.swift
    - Tests/KromoraKitTests/PreviewPresentationCoordinatorTests.swift
  docs:
    - .context/last-known-frame-plan.md
    - docs/ENGINEERING_GUIDE.md
    - docs/STORAGE_POLICY.md
    - docs/APP_ARCHITECTURE.md
  issues: []
  commands:
    - swift test --filter 'PreviewDiskCacheTests|PreviewAdmissionCoordinatorTests|PreviewPresentationCoordinatorTests|PreviewPublicationCoordinatorTests'
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - scripts/ci-tests.sh identity
    - git diff --check
    - dg validate
commits:
  - 9433d61
---

## Objective

Replace the exact-key, multi-entry `PreviewDiskCache` with one crash-safe latest presentation frame
per asset that can display before source preparation and suppress rendering only on an exact match.

## Context

Implement Phase 3 of `.context/last-known-frame-plan.md` after KRMA-729 and KRMA-730. This ticket is a
replacement, not a second cache layer.

The current cache begins lookup only inside settled preview admission, stores many edit-key JPEGs,
and wipes all entries whenever `RenderPipeline.cacheVersion` changes. It cannot hide source/edit/Look
startup latency and converts ordinary pixel-pipeline changes into cold launches.

Add shared value types described in the plan: `PresentationFrame`, `FrameSignature`,
`PresentedGeometry`, raster color-space identity, perceptual digest, and a pure classifier returning
exact, stale-compatible, provisional-only, or unusable. The source gate is
`PortablePhotoIdentity`, including fingerprint. Current inputs must be fully resolved before exact
classification.

Implement `LatestPreviewFrameStore` as an actor in `Derived/Previews`. Store one atomically replaced
`<asset-hash>.kframe` envelope per asset: bounded magic/version/header length, JSON metadata, then
JPEG bytes. Validate every length and identity before allocation/publication. Corruption and
unsupported storage format are per-entry misses.

Split the current version meaning into `pixelEpoch` and `storageFormatVersion`. A pixel epoch
mismatch is stale-compatible. A storage version mismatch ignores that entry. Neither condition may
wipe the directory. Preserve the 1 GB incremental LRU cap, coalesced writes, identity invalidation,
and active/visible pinning. Remove the old multi-key API and its version-wide wipe after callers cut
over. Clean legacy JPEGs lazily off-main.

Start lookup when selection begins, using identity already available from the collection, in
parallel with `SourceSessionCoordinator`. Present a valid candidate through KRMA-729's provisional
seam. After source/edit/Look resolution, exact hits enter the normal confirmed-frame tail and skip
preview rendering; stale/provisional hits retain inert pixels while one settled render runs.

Only a complete, canonical, non-ROI settled preview writes. Rasterization and perceptual digest
generation stay in `RenderEngine`/`RenderEngineResources`; no Core Image object crosses into the
store. Stale replacement performs at most one 120 ms crossfade when digest distance exceeds a named
constant threshold (initial value chosen from a generated fixture set that includes a visible
edit change and a sub-visible change, and recorded beside the constant with the tests that pin it); Reduce Motion and below-threshold changes swap immediately.

## Acceptance criteria

- [ ] The classifier covers every source/edit/Look/space/pixel-epoch/storage-resolution row and is
      the only freshness implementation used by preview callers.
- [ ] Envelope decoding is bounded and rejects bad magic, truncation/overflow, identity mismatch,
      invalid dimensions, corrupt JPEG, and unsupported format without affecting other entries.
- [ ] There is at most one durable 2048 px preview per asset; writes are atomic/coalesced and no
      cache operation performs synchronous main-actor directory enumeration.
- [ ] Exact warm reopen submits zero preview renders and admits histogram/supporting work exactly
      once through the confirmed publication tail.
- [ ] Stale/provisional warm reopen shows target pixels before source preparation completes,
      submits one settled render, and produces at most one replacement. Counts are actual confirmed
      drawable presentations, using the same definition as KRMA-734.
- [ ] Pixel epoch bumps preserve/show frames as stale-compatible. Storage incompatibility is a
      local miss. No version change wipes unrelated files.
- [ ] Source replacement, package identity mismatch, and raster-space incompatibility never show
      the stored frame.
- [ ] Interactive, ROI, comparison, embedded, provisional, and failed output never writes the
      store. Canonical settled output does.
- [ ] Legacy exact JPEGs are ignored and removed lazily; `PreviewDiskCache` and its old exact-key
      production path are removed rather than retained beside the new store.
- [ ] Focused, fast, serial, and identity gates pass with no Swift 6 escape hatch.

## Implementation notes

- Preserve the renderer's single actor and existing admission fences.
- Do not use cached preview pixels for export, masks, analysis truth, or full-resolution work.
- Do not base filenames on URL/path identity.
- A benchmark claim needs release-build evidence; fake-renderer timing proves orchestration only.

### Comment — claude @ 2026-09-30T17:05:40.431Z

Implementation handoff (uncommitted working tree).

Replaced PreviewDiskCache with LatestPreviewFrameStore (actor, Derived/Previews/<asset-hash>.kframe, one atomically replaced envelope per asset). Added PresentationFrame / FrameSignature / PresentedGeometry / RasterColorSpace / PerceptualDigest and the pure FrameClassifier (exact / staleCompatible / provisionalOnly / unusable), which is the only freshness implementation. RenderPipeline.cacheVersion is split into pixelEpoch (stale-compatible on mismatch) and PresentationFrameEnvelope.storageFormatVersion (per-entry miss); neither wipes the directory. Stored-frame lookup starts at selection; exact hits skip the render and go through the confirmed tail (persistsFrame: false); stale/provisional hits paint inert pixels and the first settled render is deferred until stored edits resolve, so exactly one render runs. The stored Look identity from the edit revision lets a warm open be exact before the Look scan finishes. Only complete canonical non-ROI settled frames of the resolved edit write; comparison/crop/speculative frames do not. Legacy preview-*.jpg and version are ignored and deleted lazily off-main. Pinning (active asset), 1 GB incremental LRU, coalesced writes, identity invalidation preserved. Docs updated (STORAGE_POLICY, ENGINEERING_GUIDE, APP_ARCHITECTURE).

Gates: focused, scripts/ci-tests.sh fast and identity pass. serial passes except MenuCommandTests.testViewMenuRoutesRelocatedEditorActionsAndKeepsComparisonToolbarStable, which asserts ContentView.swift contains viewModel.toggleInspector(); ContentView.swift is unmodified here and HEAD already lacks that string, so this failure pre-dates this change.

NOT DONE: the 120 ms crossfade itself. FrameRefinementPolicy (threshold 0.02 measured from generated fixtures, Reduce Motion / below-threshold immediate) and PerceptualDigest generation are implemented and pinned by tests, but PreviewSurface does not animate the swap: that needs a PreviewSurface.metal alpha uniform + rebuilt checked-in metallib + previous-texture retention and a timed redraw, which cannot be verified visually in this non-interactive run. Stale replacement currently swaps immediately. Also not measured: no release-build timing evidence (fake-renderer tests prove orchestration only).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-30T17:21:01.166Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] FrameClassifier is the single freshness implementation and classifies source, edit, Look, raster space, pixel epoch, and resolution states correctly. (pass) — Classifier tests cover source replacement, unresolved inputs and Looks, Look hash changes, pixel epoch, working-space compatibility, and invalid resolution.
- [x] Envelope decoding is bounded and rejects bad magic, truncation/overflow, identity mismatch, invalid dimensions, corrupt JPEG, and unsupported storage versions per entry. (pass) — Envelope/store tests cover these cases. Added validation rejecting non-JPEG ImageIO payloads even when they decode successfully.
- [x] At most one durable 2048 px preview exists per asset; writes are atomic/coalesced; directory enumeration is off the main actor. (pass) — Actor isolation, replacement, coalescing, cap, pinning, and lazy cleanup are covered.
- [x] Exact warm reopen suppresses preview rendering and admits histogram/supporting work once through the confirmed publication tail. (pass) — Warm reopen integration and coordinator tests pass.
- [x] Stale/provisional warm reopen presents target pixels early, renders once, and refines at most once. (pass) — Warm reopen tests confirm same-asset provisional presentation and one settled render.
- [ ] Stale replacement crossfades once for 120 ms above the digest threshold; Reduce Motion and below-threshold changes swap immediately. (fail) — FrameRefinementPolicy computes the intended decision and has unit coverage, but PreviewSurface does not consume it. Stale replacement currently swaps immediately. Urgent child KRMA-735 is linked as a dependency.
- [x] Pixel epoch changes preserve stale-compatible frames; incompatible storage formats are local misses; version changes do not wipe unrelated entries. (pass) — Store and classifier regression tests pass.
- [x] Source replacement, package/asset identity mismatch, and raster-space incompatibility never present the stored frame. (pass) — Identity, classifier, and warm reopen tests pass.
- [x] Interactive, ROI, comparison, embedded, provisional, and failed frames do not write the store; complete canonical settled output does. (pass) — Publication and presentation coordinator tests cover excluded output paths and canonical writes.
- [x] Legacy exact-key JPEGs are ignored and lazily removed; PreviewDiskCache and its exact-key production path are removed. (pass) — Legacy cleanup is tested and production references use LatestPreviewFrameStore.
- [ ] Focused, fast, serial, and identity gates pass with no Swift 6 escape hatch. (fail) — Fast passed (1,441 tests) and identity passed (4 tests). Serial completed 452 tests with one pre-existing failure at MenuCommandTests.swift:91: it expects viewModel.toggleInspector() in unchanged ContentView.swift, absent in both working tree and HEAD. Focused coordinator suites passed; a separate store/classifier/refinement run passed 37 tests.
Checks run:
- swift test --filter PreviewDiskCacheTests|PreviewAdmissionCoordinatorTests|PreviewPresentationCoordinatorTests|PreviewPublicationCoordinatorTests — passed, 31 tests
- swift test --filter LatestPreviewFrameStoreTests|PresentationFrameClassifierTests|FrameRefinementPolicyTests — passed, 37 tests
- scripts/ci-tests.sh fast — passed, 1,441 tests, exit 0
- scripts/ci-tests.sh serial — 452 tests, 1 failure (pre-existing MenuCommandTests assertion), 1 skipped
- swift test --no-parallel --filter MenuCommandTests/testViewMenuRoutesRelocatedEditorActionsAndKeepsComparisonToolbarStable — reproduced the unrelated failure at MenuCommandTests.swift:91
- scripts/ci-tests.sh identity — passed, 4 tests including 1,000-asset relocation
- git diff --check — passed
- dg validate — OK; existing model-name warnings
Findings:
- correctness/blocker: The required digest-gated 120 ms crossfade is not wired to PreviewSurface, so stale-frame refinement is immediate. Filed urgent child KRMA-735 and linked it as a KRMA-731 dependency.
Fixes:
- PresentationFrameEnvelope.decodeRaster now rejects non-JPEG payloads; added testEnvelopeRejectsNonJPEGPayloadEvenWhenImageIOCanDecodeIt.
Verification commits:
- None
Actor: codex
Resolved model: unknown
Pickup session: 01MUOCWQDZQSF4BU20
Summary: Stale preview refinement does not implement the required digest-gated 120 ms crossfade; urgent child KRMA-735 tracks the fix.

- 2026-09-30T18:06:09.036Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The classifier covers every source/edit/Look/space/pixel-epoch/storage-resolution row and is the only freshness implementation used by preview callers. (pass) — Classifier and warm-reopen suites passed; current-frame freshness is centralized in FrameClassifier.
- [x] Envelope decoding is bounded and rejects bad magic, truncation/overflow, identity mismatch, invalid dimensions, corrupt JPEG, and unsupported format without affecting other entries. (pass) — LatestPreviewFrameStoreTests passed, including corrupt-entry isolation, unsupported versions, bounds, identity, dimension, and non-JPEG payload cases.
- [x] There is at most one durable 2048 px preview per asset; writes are atomic/coalesced and no cache operation performs synchronous main-actor directory enumeration. (pass) — Store tests cover replacement, coalescing, cap, pinning, lazy cleanup, and actor-backed index loading.
- [x] Exact warm reopen submits zero preview renders and admits histogram/supporting work exactly once through the confirmed publication tail. (pass) — Warm-reopen and admission tests passed for zero render submissions and one confirmed histogram admission.
- [x] Stale/provisional warm reopen shows target pixels before source preparation completes, submits one settled render, and produces at most one replacement. (pass) — Warm-reopen tests passed; KRMA-735 now wires the stale replacement to one digest-gated 120 ms surface crossfade, covered by PreviewSurfaceTests.
- [x] Pixel epoch bumps preserve/show frames as stale-compatible. Storage incompatibility is a local miss. No version change wipes unrelated files. (pass) — Classifier and store regressions passed for pixel epoch and per-entry storage version behavior.
- [x] Source replacement, package identity mismatch, and raster-space incompatibility never show the stored frame. (pass) — Classifier and warm-reopen identity tests passed, including replaced sources and incompatible raster spaces.
- [x] Interactive, ROI, comparison, embedded, provisional, and failed output never writes the store. Canonical settled output does. (pass) — Publication and admission tests passed for excluded paths and canonical settled writes.
- [x] Legacy exact-key JPEGs are ignored and removed lazily; PreviewDiskCache and its old exact-key production path are removed. (pass) — Store regression passed for lazy legacy cleanup; production uses LatestPreviewFrameStore.
- [x] Focused, fast, serial, and identity gates pass with no Swift 6 escape hatch. (pass) — Focused preview/store/classifier/surface run: 113 passed. Fast: 1,441 passed. Serial: 455 run, 1 skipped, 0 failures. Identity: 4 passed including 1,000-asset relocation. Updated the stale MenuCommandTests assertion after the serial rerun exposed that the inspector action had moved to MenuCommands; the focused test and full serial lane then passed.
Checks run:
- swift test --filter PreviewDiskCacheTests|PreviewAdmissionCoordinatorTests|PreviewPresentationCoordinatorTests|PreviewPublicationCoordinatorTests|LatestPreviewFrameStoreTests|PresentationFrameClassifierTests|FrameRefinementPolicyTests|PreviewSurfaceTests — passed, 113 tests, exit 0
- scripts/ci-tests.sh fast — passed, 1,441 tests, exit 0
- scripts/ci-tests.sh serial — passed, 455 tests, 1 skipped, 0 failures, exit 0
- scripts/ci-tests.sh identity — passed, 4 tests including 1,000-asset relocation, exit 0
- swift test --no-parallel --filter MenuCommandTests/testViewMenuRoutesRelocatedEditorActionsAndKeepsComparisonToolbarStable — passed, exit 0
- git diff --check — passed
- dg validate — OK; existing model-name warnings
Findings:
- None
Fixes:
- Updated the stale MenuCommandTests expectation to verify toggleInspector is handled by MenuCommands after the action relocation; added an assertion that it is absent from ContentView.
Verification commits:
- 9433d61
Actor: codex
Resolved model: unknown
Pickup session: 01MUOEHLX3UBX8C1OO
Summary: Verified latest preview frame store and KRMA-735 crossfade integration; all required gates pass. Corrected a stale menu test assertion in 9433d61.
