---
id: KRMA-417
title: "Fix: cacheIdentity re-reads and re-hashes entire file on every access, regressing render/mask perf"
type: bug
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: cacheIdentity does not re-read/re-hash the full file bytes more than once per source-session for an unchanged file.
      result: pass
      notes: ImageSource.init computes the full PortablePhotoSourceFingerprint once and captures a bounded PhotoSourceFingerprint (size/mtime/resourceID/64KiB sample digest) as fileChangeSignature. cacheIdentity re-checks only the bounded signature on each access and reuses portableIdentity unless it differs, in which case it recomputes the full hash. Verified by reading Sources/KromoraKit/Models/ImageSource.swift and the cheap-check implementation in PhotoAsset.swift.
    - criterion: Preserve in-place content-change invalidation and relocation-safe identity.
      result: pass
      notes: testImageSourceCacheIdentityRefreshesAfterFileMetadataChanges (added in 7186c8a) and the pre-existing PortableCacheIdentityTests relocation/replacement tests all pass (5/5 focused run).
    - criterion: scripts/ci-tests.sh fast passes reliably (no timeout) for PreviewDiskCacheTests under normal parallel execution, 3x back-to-back.
      result: pass
      notes: "Ran scripts/ci-tests.sh fast three consecutive times: 942/942 passed each run, including both previously-flaky PreviewDiskCacheTests timeout cases, no timeouts observed."
    - criterion: Existing relocation/replacement-invalidation regressions from KRMA-398 (PortableCacheIdentityTests) continue to pass.
      result: pass
      notes: "swift test --filter PortableCacheIdentityTests: 5/5 passed."
    - criterion: swift build, swift test (fast + serial Core Image lanes) pass.
      result: pass
      notes: "swift build: Build complete. scripts/ci-tests.sh serial: 371/371 passed."
  checks_run:
    - swift build
    - scripts/ci-tests.sh fast (x3 consecutive)
    - scripts/ci-tests.sh serial
    - swift test --filter PortableCacheIdentityTests
    - git status --porcelain diff against session baseline (no unexpected tree changes)
    - manual code review of Sources/KromoraKit/Models/ImageSource.swift cacheIdentity/init and PhotoAsset.swift PhotoSourceFingerprint.file cheap-check path
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-12T22:33:24.451Z
  session: 01MTYYKG3MFA1I1OHB
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - performance
  - library
  - identity
created: 2026-09-12T22:15:26.896Z
updated: 2026-09-12T22:33:24.453Z
order: a0
board: product
---

## Objective

`PortablePhotoIdentity`/`ImageSource.cacheIdentity` for URL-backed sources performs a full
`Data(contentsOf: url)` read plus SHA-256 over the entire file on **every access** (see
`ImageSource.cacheIdentity` in `Sources/KromoraKit/Models/ImageSource.swift`, which calls
`PortablePhotoSourceFingerprint.file(at:)` unconditionally instead of the old lightweight
file-resource-metadata check). `cacheIdentity` is read at 12+ call sites across the render/mask hot
path (`RenderCacheKey`, `RenderEngine` x3, `AppViewModel` preview-cache key, mask verification in
`LocalMaskRendering`, `MaskedToneAnalyzer`, `VisionSemanticMaskProvider`), so a single render/mask
pass now re-reads and re-hashes the same file multiple times synchronously instead of once.

## Context

Introduced in commit 2fc62b4 (KRMA-398) and already visible as CI flakiness: under the parallel
fast test lane, `PreviewDiskCacheTests.testSettledHitSkipsTheRendererAndStillAdmitsHistogram` and
`testZoomedSettledRequestRendersInsteadOfAdoptingTheCanonicalDiskEntry` time out waiting for the
disk-cache write (5s budget). Both pass in isolation, both pass on the parent commit (7e3a5b9) under
the same parallel load, and both pass again on 2fc62b4 once the test's wait timeout is raised to
30s in a scratch worktree. That isolates the cause to added synchronous cost on the render path, not
a correctness bug or pre-existing flakiness.

## Scope

- Stop re-reading/re-hashing the full file on every `cacheIdentity` access. Either memoize the
  computed `PortablePhotoSourceFingerprint` per `ImageSource` value (compute once at source
  construction/open, not per read), or gate the full-content re-hash behind the same kind of cheap
  resource-metadata check the legacy `cacheFingerprint` used, only falling back to a content hash
  when metadata indicates a possible in-place change.
- Preserve the correctness guarantee KRMA-398 added: an in-place content change at the same path
  must still invalidate the cache (content hash must change), and a relocated file must still hit
  the cache when identity is threaded through.
- Keep the fix localized to `ImageSource`/`PortablePhotoIdentity` construction; do not change the
  render pipeline itself.

## Acceptance criteria

- [ ] `cacheIdentity` (or equivalent) does not re-read/re-hash the full file bytes more than once
  per source-session for an unchanged file.
- [ ] `scripts/ci-tests.sh fast` passes reliably (no timeout) for `PreviewDiskCacheTests` under
  normal parallel execution, run at least 3 times back-to-back to confirm it is not flaky.
- [ ] Existing relocation/replacement-invalidation regressions from KRMA-398
  (`PortableCacheIdentityTests`) continue to pass.
- [ ] `swift build`, `swift test` (fast + serial Core Image lanes) pass.

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-12T22:30:03.650Z

Implemented in 7186c8a. ImageSource now captures a bounded file-change signature and reuses the portable content hash while the source is unchanged; a signature change triggers a fresh full hash, preserving same-path replacement invalidation and relocation-safe identities. Added regression coverage for refresh behavior.

Verification: swift build passed; scripts/ci-tests.sh fast passed 3 consecutive times (942 tests each, including both PreviewDiskCache timeout cases); scripts/ci-tests.sh serial passed (371 tests); focused portable/cache identity tests passed (10/10); dg validate passed with existing unknown-model warnings.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-12T22:33:24.451Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] cacheIdentity does not re-read/re-hash the full file bytes more than once per source-session for an unchanged file. (pass) — ImageSource.init computes the full PortablePhotoSourceFingerprint once and captures a bounded PhotoSourceFingerprint (size/mtime/resourceID/64KiB sample digest) as fileChangeSignature. cacheIdentity re-checks only the bounded signature on each access and reuses portableIdentity unless it differs, in which case it recomputes the full hash. Verified by reading Sources/KromoraKit/Models/ImageSource.swift and the cheap-check implementation in PhotoAsset.swift.
- [x] Preserve in-place content-change invalidation and relocation-safe identity. (pass) — testImageSourceCacheIdentityRefreshesAfterFileMetadataChanges (added in 7186c8a) and the pre-existing PortableCacheIdentityTests relocation/replacement tests all pass (5/5 focused run).
- [x] scripts/ci-tests.sh fast passes reliably (no timeout) for PreviewDiskCacheTests under normal parallel execution, 3x back-to-back. (pass) — Ran scripts/ci-tests.sh fast three consecutive times: 942/942 passed each run, including both previously-flaky PreviewDiskCacheTests timeout cases, no timeouts observed.
- [x] Existing relocation/replacement-invalidation regressions from KRMA-398 (PortableCacheIdentityTests) continue to pass. (pass) — swift test --filter PortableCacheIdentityTests: 5/5 passed.
- [x] swift build, swift test (fast + serial Core Image lanes) pass. (pass) — swift build: Build complete. scripts/ci-tests.sh serial: 371/371 passed.
Checks run:
- swift build
- scripts/ci-tests.sh fast (x3 consecutive)
- scripts/ci-tests.sh serial
- swift test --filter PortableCacheIdentityTests
- git status --porcelain diff against session baseline (no unexpected tree changes)
- manual code review of Sources/KromoraKit/Models/ImageSource.swift cacheIdentity/init and PhotoAsset.swift PhotoSourceFingerprint.file cheap-check path
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTYYKG3MFA1I1OHB
