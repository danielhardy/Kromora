---
id: KRMA-398
title: "Phase 1.2: migrate render/mask/preview cache keys to new identity"
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: RenderCacheKey, MaskStore, and PreviewDiskCache all key exclusively off the new identity (no path/inode/mtime input remains in these types)
      result: pass
      notes: Re-confirmed by reading RenderCacheKey.swift, MaskStore.swift, RegionMask.swift (MaskCacheKey), and PreviewDiskCache.swift (Key.canonicalKeyString) — all key off PortablePhotoIdentity.cacheKey; no path/inode/mtime fields present.
    - criterion: Moving the same source file to a new path/volume produces a cache hit (no relink, no re-render) for render, mask, and preview caches
      result: pass
      notes: PortableCacheIdentityTests (render, mask filename, preview-key relocation cases) pass in a fresh focused run (5/5).
    - criterion: Changing file content (different hash) at the same path correctly invalidates the cache
      result: pass
      notes: testChangingContentChangesRenderIdentityEvenWhenAssetUUIDIsRetained and testPhotoAssetCacheKeySurvivesRelocationAndInvalidatesReplacement pass; testImageSourceCacheIdentityRefreshesAfterFileMetadataChanges (added in the KRMA-417 fix, commit 7186c8a) confirms the bounded-signature short-circuit still triggers a full re-hash and new identity on in-place content change.
    - criterion: Stale-completion regression tests pass (an in-flight render for a now-invalid identity does not clobber a newer valid entry)
      result: pass
      notes: No behavior change to the stale-completion guard paths; existing regressions in this area pass under both the fast and serial lanes.
    - criterion: swift build, swift test (fast + serial Core Image lanes), dg validate, and git diff --check pass
      result: pass
      notes: "Previously blocked on a reproducible PreviewDiskCacheTests timeout under the parallel fast lane, root-caused to ImageSource.cacheIdentity re-reading and SHA-256-hashing the full file on every access (12+ hot-path call sites). That was fixed and independently verified in KRMA-417 (now done, commit 7186c8a: ImageSource now captures a bounded PhotoSourceFingerprint at construction and only recomputes the full content hash when that bounded signature changes). Re-ran independently on this commit: swift build clean; scripts/ci-tests.sh fast 946/946 passed with no timeouts; scripts/ci-tests.sh serial 371/371 passed; swift test --filter PortableCacheIdentityTests 5/5 passed; dg validate --json ok:true (only pre-existing unrelated model-name warnings); git diff --check clean (both scoped to the changed files and full-tree)."
  checks_run:
    - swift build (debug) — pass
    - scripts/ci-tests.sh fast — 946/946 passed, no timeouts
    - scripts/ci-tests.sh serial — 371/371 passed
    - swift test --filter PortableCacheIdentityTests — 5/5 passed
    - dg validate --json — ok:true (only pre-existing unrelated warnings)
    - git diff --check (scoped + full tree) — clean
    - "Manual code review of the KRMA-417 fix (commit 7186c8a) to ImageSource.swift: cacheIdentity now checks a bounded, cheap PhotoSourceFingerprint (size/mtime/resourceID/64KiB sample) captured once at construction, and only recomputes the full content hash when that bounded signature differs, preserving in-place invalidation while eliminating the per-access full-file re-read/re-hash"
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-12T23:38:58.102Z
  session: 01MTZ0Y565THA1OXMF
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - identity
  - performance
created: 2026-09-12T19:44:12.535Z
updated: 2026-09-12T23:38:58.104Z
depends_on:
  - KRMA-397
  - KRMA-417
order: a0
board: product
---

## Objective

Migrate the render/cache layer — `PhotoAssetSource.cacheKey`, `RenderCacheKey`, `MaskStore`, and
`PreviewDiskCache` — onto the new opaque-identity types, so cache keys are portable across paths and
filesystems.

## Dependencies

- The core-identity-types ticket (this consumes `PhotoAssetID`/`PhotoSourceFingerprint`; do not start
  until it has landed).

## Scope

- Update `PhotoAssetSource.cacheKey`, `RenderCacheKey`, `MaskStore`, and `PreviewDiskCache` to derive
  their keys from the new opaque UUID + content hash + source revision + decoder version + geometry
  identity instead of path/inode/mtime.
- Remove the old path/inode-based identity inputs from these specific call sites once migrated (do
  not leave a dual path in this layer — the core types ticket is what stays additive, this layer
  should fully switch).
- Preserve all current render, mask, and preview behavior: existing renders must still hit their
  cache correctly for unchanged assets, and must still invalidate correctly when content actually
  changes (content hash changes) — moving a file must *not* invalidate its cache.
- `CIImage`, `CIFilter`, and `CIContext` remain confined to `RenderEngine`; this migration only
  touches how cache keys are computed, not the render pipeline itself.

## Acceptance criteria

- [ ] `RenderCacheKey`, `MaskStore`, and `PreviewDiskCache` all key exclusively off the new identity
  (no path/inode/mtime input remains in these types).
- [ ] Moving the same source file to a new path/volume produces a cache hit (no relink, no
  re-render) for render, mask, and preview caches.
- [ ] Changing file content (different hash) at the same path correctly invalidates the cache.
- [ ] Stale-completion regression tests pass (an in-flight render for a now-invalid identity does not
  clobber a newer valid entry).
- [ ] `swift build`, `swift test` (fast + serial Core Image lanes), `dg validate`, and
  `git diff --check` pass.

## Verification lane

Render-cache regression lane (serial Core Image tests) plus the relocation benchmark gate from
KRMA-389's generator (same content, moved path → cache hit).

## Context

- context.files: Sources/KromoraKit (RenderCacheKey, MaskStore, PreviewDiskCache, PhotoAssetSource)
- context.docs: docs/ENGINEERING_GUIDE.md, docs/LIBRARY_PACKAGE_PLAN.md
- context.issues: KRMA-390


### Comment — codex @ 2026-09-12T22:05:01.049Z

Implemented in commit 2fc62b4. Migrated render, mask, and preview cache identities to portable opaque asset UUID + content hash + source revision + decoder version + geometry; propagated persisted identities through source import and prepared/thumbnail paths; retained legacy Codable/key bridges. Added relocation, replacement-invalidation, mask-store, preview-key, and render-cache regressions. Verification: swift build -c release; scripts/ci-tests.sh fast (940 passed); focused PortableCacheIdentityTests (4 passed); dg validate; git diff --check.

## Agent log

- 2026-09-12T22:19:29.752Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] RenderCacheKey, MaskStore, and PreviewDiskCache all key exclusively off the new identity (no path/inode/mtime input remains in these types) (pass) — Confirmed by reading RenderCacheKey.swift, MaskStore.swift (filename derivation), RegionMask.swift (MaskCacheKey), PreviewDiskCache.swift (Key.canonicalKeyString) — all now key off PortablePhotoIdentity.cacheKey with no path/inode/mtime fields.
- [x] Moving the same source file to a new path/volume produces a cache hit (no relink, no re-render) for render, mask, and preview caches (pass) — Verified via PortableCacheIdentityTests (render, mask filename, preview-key) when the same portable identity is threaded through a relocation. Non-blocking observation filed as KRMA-417 follow-up scope note: first-encounter identity minting in PhotoAssetSource.init(url:) / PhotoAsset.makePortableIdentity still bootstraps the UUID from legacy PhotoAssetID.file(url) (resource-id/path) when no persisted identity exists yet; this is unchanged from prior behavior and is a persistence/relink concern (KRMA-390), not a cache-key regression, but should be tracked.
- [x] Changing file content (different hash) at the same path correctly invalidates the cache (pass) — PortableCacheIdentityTests.testChangingContentChangesRenderIdentityEvenWhenAssetUUIDIsRetained and testPhotoAssetCacheKeySurvivesRelocationAndInvalidatesReplacement cover this.
- [x] Stale-completion regression tests pass (an in-flight render for a now-invalid identity does not clobber a newer valid entry) (pass) — No behavior change to the stale-completion guard paths; existing regressions in this area pass.
- [ ] swift build, swift test (fast + serial Core Image lanes), dg validate, and git diff --check pass (fail) — swift build passes. swift test fast lane is flaky: PreviewDiskCacheTests.testSettledHitSkipsTheRendererAndStillAdmitsHistogram and testZoomedSettledRequestRendersInsteadOfAdoptingTheCanonicalDiskEntry reproducibly time out (5s budget) under the parallel fast lane on this commit (2fc62b4), while both pass in isolation and both pass on the parent commit (7e3a5b9) under identical parallel load. Root cause isolated to ImageSource.cacheIdentity performing a full Data(contentsOf:) read + SHA-256 over the entire file on every access (12+ call sites on the render/mask hot path) instead of the prior lightweight file-resource-metadata check. dg validate passes cleanly (only pre-existing unrelated warnings).
Checks run:
- swift build (debug) — pass
- scripts/ci-tests.sh fast — fails: PreviewDiskCacheTests timeouts under parallel load (reproducible 2x)
- scripts/ci-tests.sh fast on parent commit 7e3a5b9 in isolated worktree — pass (no timeouts)
- scripts/ci-tests.sh fast on 2fc62b4 in isolated worktree with test wait-timeout raised 5s->30s — pass, confirming slowness not a hard failure
- dg validate --json — ok:true (only pre-existing unrelated warnings)
- Manual code review of RenderCacheKey.swift, PreviewDiskCache.swift, MaskStore.swift, RegionMask.swift, MaskedToneAnalyzer.swift, VisionSemanticMaskProvider.swift, LocalMaskRendering.swift, ImageSource.swift, PhotoAsset.swift, PortablePhotoIdentity.swift, PortableCacheIdentityTests.swift
Findings:
- PERFORMANCE (confirmed): Sources/KromoraKit/Models/ImageSource.swift cacheIdentity re-reads and SHA-256-hashes the entire file on every access for URL-backed sources, and is called from 12+ hot-path sites per render/mask pass (RenderCacheKey, RenderEngine x3, AppViewModel preview-cache key, LocalMaskRendering, MaskedToneAnalyzer, VisionSemanticMaskProvider). Opening/navigating a folder-backed RAW library repeatedly re-reads and re-hashes each multi-MB/GB RAW file synchronously instead of once, which already reproduces as CI test timeouts under load (PreviewDiskCacheTests) and will show up as UI latency on real RAW libraries. Filed as KRMA-417 (urgent).
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTYXOC1LCK4LZP8O
Summary: KRMA-398's cache-key migration is otherwise correct, but ImageSource.cacheIdentity now re-reads and SHA-256-hashes the full file on every access (12+ hot-path call sites), causing reproducible CI timeouts in PreviewDiskCacheTests under the parallel fast lane. Filed KRMA-417 (urgent) to fix the perf regression before this can pass verification.

- 2026-09-12T23:38:58.102Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] RenderCacheKey, MaskStore, and PreviewDiskCache all key exclusively off the new identity (no path/inode/mtime input remains in these types) (pass) — Re-confirmed by reading RenderCacheKey.swift, MaskStore.swift, RegionMask.swift (MaskCacheKey), and PreviewDiskCache.swift (Key.canonicalKeyString) — all key off PortablePhotoIdentity.cacheKey; no path/inode/mtime fields present.
- [x] Moving the same source file to a new path/volume produces a cache hit (no relink, no re-render) for render, mask, and preview caches (pass) — PortableCacheIdentityTests (render, mask filename, preview-key relocation cases) pass in a fresh focused run (5/5).
- [x] Changing file content (different hash) at the same path correctly invalidates the cache (pass) — testChangingContentChangesRenderIdentityEvenWhenAssetUUIDIsRetained and testPhotoAssetCacheKeySurvivesRelocationAndInvalidatesReplacement pass; testImageSourceCacheIdentityRefreshesAfterFileMetadataChanges (added in the KRMA-417 fix, commit 7186c8a) confirms the bounded-signature short-circuit still triggers a full re-hash and new identity on in-place content change.
- [x] Stale-completion regression tests pass (an in-flight render for a now-invalid identity does not clobber a newer valid entry) (pass) — No behavior change to the stale-completion guard paths; existing regressions in this area pass under both the fast and serial lanes.
- [x] swift build, swift test (fast + serial Core Image lanes), dg validate, and git diff --check pass (pass) — Previously blocked on a reproducible PreviewDiskCacheTests timeout under the parallel fast lane, root-caused to ImageSource.cacheIdentity re-reading and SHA-256-hashing the full file on every access (12+ hot-path call sites). That was fixed and independently verified in KRMA-417 (now done, commit 7186c8a: ImageSource now captures a bounded PhotoSourceFingerprint at construction and only recomputes the full content hash when that bounded signature changes). Re-ran independently on this commit: swift build clean; scripts/ci-tests.sh fast 946/946 passed with no timeouts; scripts/ci-tests.sh serial 371/371 passed; swift test --filter PortableCacheIdentityTests 5/5 passed; dg validate --json ok:true (only pre-existing unrelated model-name warnings); git diff --check clean (both scoped to the changed files and full-tree).
Checks run:
- swift build (debug) — pass
- scripts/ci-tests.sh fast — 946/946 passed, no timeouts
- scripts/ci-tests.sh serial — 371/371 passed
- swift test --filter PortableCacheIdentityTests — 5/5 passed
- dg validate --json — ok:true (only pre-existing unrelated warnings)
- git diff --check (scoped + full tree) — clean
- Manual code review of the KRMA-417 fix (commit 7186c8a) to ImageSource.swift: cacheIdentity now checks a bounded, cheap PhotoSourceFingerprint (size/mtime/resourceID/64KiB sample) captured once at construction, and only recomputes the full content hash when that bounded signature differs, preserving in-place invalidation while eliminating the per-access full-file re-read/re-hash
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTZ0Y565THA1OXMF
