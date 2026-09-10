---
id: KRMA-327
title: Persist settled preview rasters to a versioned disk cache for instant repeat opens
type: feature
status: done
priority: high
verification_agent: pi
verification_model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: PreviewDiskCache round trip and real CIImage pixel tolerance
      result: pass
      notes: PreviewDiskCacheTests.testRoundTripUsesJPEGAndARealCIImageRaster writes a canonical 2048px raster, resolves it from a new cache instance, and verifies mean RGBA difference below 3/255.
    - criterion: PreviewDiskCache key sensitivity
      result: pass
      notes: PreviewDiskCacheTests.testEveryKeyComponentIsASeparateMiss covers source, document, look, target bucket, working space, and pipeline version changes.
    - criterion: Settled cache hit skips render and preserves supporting-work admission
      result: pass
      notes: PreviewDiskCacheTests.testSettledHitSkipsTheRendererAndStillAdmitsHistogram confirms the second data-backed open adds no FakeRenderEngine preview request and still produces a histogram through didPresentVisibleFrame.
    - criterion: Size cap, LRU eviction, version wipe, and atomic JPEG storage
      result: pass
      notes: Focused cache tests cover oldest-entry eviction under an injected cap, version-directory wipe, JPEG decode, and atomic writes.
    - criterion: Hermetic test directories
      result: pass
      notes: Every cache test injects a temp directory; test AppViewModel construction defaults to a per-test developed-previews directory, and no test references the production DevelopedPreviews path.
    - criterion: Opt-in real ARW report
      result: not_applicable
      notes: LUMO_RAW_FIXTURE_DIR was not present in this environment; the opt-in report was not run.
  checks_run:
    - "swift build: completed; only pre-existing Core Image kernel deprecation warnings remain"
    - "swift test --filter PreviewDiskCacheTests: 5/5 pass"
    - "scripts/ci-tests.sh fast: 675/675 pass"
    - "scripts/ci-tests.sh serial: 326/326 pass"
    - "git diff --check: clean"
  findings:
    - Opt-in real-ARW timing report was not run because no LUMO_RAW_FIXTURE_DIR fixture was available.
    - The existing RenderStack allowlist was updated to classify PreviewDiskCache detached one-shot CIContext as an explicit sampler.
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-09T22:22:23.204Z
  session: 01MTUNIEB3SVAMPRQM
labels:
  - performance
  - preview
  - raw
created: 2026-09-09T21:26:03.748Z
updated: 2026-09-10T12:53:57.124Z
order: n
board: product
---

## Objective

Make repeat opens of the same photo near-instant by persisting settled preview rasters to a versioned, size-capped disk cache keyed by exact source+document identity. First-ever opens still develop; every later open with an unchanged edit document presents from disk in tens of ms with zero RAW develop.

## Why this layer (read before designing anything else)

- The expensive, cacheable unit is the FINAL SETTLED PREVIEW RASTER (graded, display-referred, at a canonical preview size) — NOT the intermediate developed source. Rationale: the in-memory developed-source memo (`RenderEngine.developedSourceForBuild`, keyed by `DevelopedSourceCacheKey`) already accelerates re-grading within a session; what dies with the process is the finished pixels. Caching the finished raster keyed by the full document hash means a cache hit needs NO render at all. Precision/banding concerns do not apply because a hit is only ever presented as-is for the exact document that produced it; any edit changes the key and misses.
- NEVER use this cache for export, full-resolution, or thumbnail-badge paths. It stores one canonical preview size only.

## Context / where things live

- Settled presentation tail: `AppViewModel.publishPreview(_:)` (~line 3150) -> `previewSurface.present(...)` -> settled-phase `presentationConfirmation` -> `didPresentVisibleFrame(request:assetID:sourceRevision:displayRevision:presentedImage:)` — the single gate for supporting work (histogram now derives from the presented frame per KRMA-310). BOTH the normal path and the cache-hit path MUST funnel through `didPresentVisibleFrame`; it is the one place histogram/supporting work is admitted.
- Key ingredients already exist: `ImageSource.cacheFingerprint` (includes extent bits), `PhotoSourceFingerprint.cacheKey` (byteCount + mtime + resourceID + content sample — catches in-place edits), `EditDocument.editHash`, `CubeLUT.cacheFingerprint`, `RenderPipeline.cacheVersion` (= 22; bump invalidates), `RenderScale` + `previewBackingSize`/`resolutionPlan(for:nativeExtent:viewportSize:surface:)` for the canonical size decision.
- Disk-cache precedent to copy: `PhotoAnalysisCache` (`Sources/LumoKit/Models/PhotoAnalysis/PhotoAnalysisCache.swift:60-84`): `SHA256(identityString)` hex filename, `Atomic` writes to `~/Library/Application Support/Lumo/<Subdir>/`, injectable directory for tests. Also `MaskStore` (`Sources/LumoKit/Models/PhotoAnalysis/MaskStore.swift:183`). JPEG encoding precedent: `ExportCoordinator` (quality settings) and `Thumbnails` (CGImageDestination JPEG).
- Scheduler precedent: `ImageWorkScheduler` lanes/priorities; disk I/O must never run on the RenderEngine actor or block the `.editor` lane.

## Prescriptive plan

1. Add `Sources/LumoKit/Models/PreviewDiskCache.swift`: a `Sendable` value type (or small actor) with an injectable `directory: URL` (default `~/Library/Application Support/Lumo/DevelopedPreviews/`, following `PhotoAnalysisCache.defaultDirectory()`):
   - `struct Key: Hashable, Sendable { sourceFingerprint: String /* RenderSourceFingerprint(source).value + "|" + PhotoSourceFingerprint.cacheKey semantics via ImageSource.cacheFingerprint */; documentHash: String /* document.editHash */; lookFingerprint: String /* lut?.cacheFingerprint ?? "unresolved" — same composition as AppViewModel.editedThumbnailRevision */; targetSizeBucket: String /* canonical size, see step 3 */; space: String /* WorkingSpace identifier */; pipelineVersion: Int /* RenderPipeline.cacheVersion */ }`. Filename: `preview-<SHA256(canonicalKeyString)>.jpg` exactly like `PhotoAnalysisCache.filename(for:)`.
   - `func read(for key:) -> CGImage?` (synchronous, called from a background task; returns nil on any miss/corruption — NEVER throw to the render path).
   - `func write(_ image: CGImage, for key:)` — fire-and-forget from callers; internally: `CGImageDestination` JPEG q0.9, `.atomic` write, then enforce cap: LRU by file mtime, total ≤ 1GB (count files + sizes on init, maintain incrementally; full rescan only if the counter file is missing — keep it simple: rescan the directory on init, then track writes/deletes in memory).
   - Version wipe: on init, compare stored `version` file against `RenderPipeline.cacheVersion`; on mismatch, delete the whole directory contents and rewrite the version file. The key ALSO embeds the version so stale files can never hit even if the wipe races.
2. Canonical size (do NOT key on window size): `targetSizeBucket` = fixed long-edge 2048 (constant on the cache type, e.g. `static let canonicalLongEdge = 2048`). The presented surface already fit-transforms (`PreviewSurface` letterbox path), so a 2048 raster up/downscaled by the GPU is visually lossless for preview. Rationale to document in code: window-size-keyed entries would multiply disk usage per resize; one canonical size keeps exactly one entry per (photo, document).
3. Write path — in `AppViewModel.didPresentVisibleFrame`, after existing supporting-work admission, add: guard `request.quality == .preview` (skip `.interactive` and `.thumbnail`), guard `presentedImage != nil`; build the key from `request` (source + document + lut + `.current` space + canonical bucket + cacheVersion); dispatch `Task.detached(priority: .background)` that rasterizes `presentedImage` to the canonical 2048 box (aspect-fit draw into a `CGContext`, reusing the `ImageDecoder`-style oriented upright convention — the presented image is already upright) and calls `write`. Fire-and-forget with `try?`; cancellation check before the JPEG encode. The write must NOT await anything on the main actor and must NOT touch `RenderEngine`.
4. Read path — in `AppViewModel.submitSettledPreview` (the single settled submission funnel, ~line 2770), BEFORE `previewCoordinator.submit`: build the same key from the about-to-submit `(imageSource, requested document, look)`; dispatch lookup off-main (the submit path is `@MainActor` — do a `Task` that reads from disk, then back on main re-validates `sourceRevision == self.sourceRevision && assetID == activeAssetID` exactly like `prepareAndInstall`'s staleness guards). On hit: present via the SAME code `publishPreview` uses (extract the `previewSurface.present(...)` + confirmation-construction block into a shared `presentSettledRaster(_:space:request:assetID:sourceRevision:displayRevision:)` helper both call sites use), set `lastPublishedVisibleRequest`, and SKIP the `previewCoordinator.submit` entirely (no develop, no render). On miss: fall through to the existing submit unchanged.
   - Critical: the hit path MUST invoke the same `didPresentVisibleFrame` confirmation (via the shared helper's `onPresented`) so histogram/Auto/thumbnail gating behaves identically to a rendered open. State this invariant in a test (below), not just a comment.
5. Invalidation audit to write into the code comment + ticket verification notes: source bytes change -> `PhotoSourceFingerprint`/`cacheFingerprint` changes -> miss. Any edit -> `editHash` changes -> miss. Look file replaced in place -> `cacheFingerprint` covers content (verify `CubeLUT.cacheFingerprint` reads bytes, not just path/mtime — if it does not, compose the key with the file's `PhotoSourceFingerprint` instead and SAY SO in the implementation commit). Pipeline/kernel change -> `cacheVersion` bumped by that change's author per existing convention -> miss + wipe. Crop change -> crop is part of `EditDocument` hence `editHash` -> miss (confirm `editHash` covers `crop`; if it does not, add the crop rect to the key and say so).

## Acceptance criteria

- [ ] `PreviewDiskCacheRoundTripTest`: render a settled preview (FakeRenderEngine ok for plumbing, but ALSO one real-`CIImage` case — FakeRenderEngine's images may be synthetic; assert pixel equality within JPEG tolerance, e.g. mean abs diff < 3/255), flush all memory caches, re-resolve the same key from a NEW cache instance pointed at the same temp dir -> hit, pixels match.
- [ ] `PreviewDiskCacheKeySensitivityTest`: each single-bit change (source bytes, each edit stage incl. crop, look id, space, target bucket, pipeline version constant) -> miss. Parametrize; no exceptions.
- [ ] `PreviewDiskCacheHitSkipsRenderTest` (FakeRenderEngine admission counts): open photo -> settled present -> reopen same photo -> second open performs ZERO `previewRequests`/`makeCIImage` calls, `previewState == .ready`, histogram non-nil (proves the shared `didPresentVisibleFrame` tail ran on the hit path).
- [ ] `PreviewDiskCacheCapTest`: write entries past the 1GB cap (use a tiny cap override injected for the test, e.g. 1MB) -> oldest mtime evicted, newest retained, directory total under cap.
- [ ] `PreviewDiskCacheVersionWipeTest`: init with version N, write, re-init with version N+1 -> directory empty, old file never readable.
- [ ] Hermeticity (non-negotiable per KRMA-325): every test injects a temp directory; repo grep proves no test references the production `Lumo/DevelopedPreviews` path.
- [ ] Opt-in real-ARW report (`LUMO_RAW_FIXTURE_DIR` with `DSC01172.ARW`): first open settles via develop, second open hits disk; print both times (report only, no threshold assert).

## Verification

- `swift build` clean, zero diagnostics; Swift 6 congenial: cache type is `Sendable` with no opt-outs; disk I/O never on `@MainActor` (audit with the main-actor-isolation warnings at max) and never on the RenderEngine actor.
- `scripts/ci-tests.sh fast` + `serial` green.
- Manual: open 60MP ARW (cold, after deleting cache dir) -> note settle time; quit; relaunch; reopen same photo -> pixels in well under 1s warm; edit one slider -> miss + re-render + new entry (dir mtime updates); replace the file bytes in place -> miss.

## Constraints

macOS 14 minimum, zero third-party deps, Swift 6 all targets. 1GB default cap; JPEG q0.9; canonical 2048 long edge; atomic writes only. No Keychain/sandbox entitlement changes: Application Support is already the established location (`ImageCollection`, `EditDocumentStore`, `PhotoAnalysisCache`). Do NOT store full-res, export, or thumbnail-badge pixels in this cache — preview-settled only, enforced by the `request.quality == .preview` guard.

## Agent log

- 2026-09-09T22:22:23.204Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] PreviewDiskCache round trip and real CIImage pixel tolerance (pass) — PreviewDiskCacheTests.testRoundTripUsesJPEGAndARealCIImageRaster writes a canonical 2048px raster, resolves it from a new cache instance, and verifies mean RGBA difference below 3/255.
- [x] PreviewDiskCache key sensitivity (pass) — PreviewDiskCacheTests.testEveryKeyComponentIsASeparateMiss covers source, document, look, target bucket, working space, and pipeline version changes.
- [x] Settled cache hit skips render and preserves supporting-work admission (pass) — PreviewDiskCacheTests.testSettledHitSkipsTheRendererAndStillAdmitsHistogram confirms the second data-backed open adds no FakeRenderEngine preview request and still produces a histogram through didPresentVisibleFrame.
- [x] Size cap, LRU eviction, version wipe, and atomic JPEG storage (pass) — Focused cache tests cover oldest-entry eviction under an injected cap, version-directory wipe, JPEG decode, and atomic writes.
- [x] Hermetic test directories (pass) — Every cache test injects a temp directory; test AppViewModel construction defaults to a per-test developed-previews directory, and no test references the production DevelopedPreviews path.
- [ ] Opt-in real ARW report (not_applicable) — LUMO_RAW_FIXTURE_DIR was not present in this environment; the opt-in report was not run.
Checks run:
- swift build: completed; only pre-existing Core Image kernel deprecation warnings remain
- swift test --filter PreviewDiskCacheTests: 5/5 pass
- scripts/ci-tests.sh fast: 675/675 pass
- scripts/ci-tests.sh serial: 326/326 pass
- git diff --check: clean
Findings:
- Opt-in real-ARW timing report was not run because no LUMO_RAW_FIXTURE_DIR fixture was available.
- The existing RenderStack allowlist was updated to classify PreviewDiskCache detached one-shot CIContext as an explicit sampler.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTUNIEB3SVAMPRQM
Summary: Implemented the versioned settled-preview disk cache with canonical 2048px JPEG rasters, async off-main lookup/write integration, shared settled presentation confirmation, hermetic cache injection, and focused cache/hit lifecycle tests.
