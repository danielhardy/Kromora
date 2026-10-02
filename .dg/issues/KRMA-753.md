---
id: KRMA-753
title: Reuse persisted record identity hash in PortableLibrarySession.materializedAsset instead of re-hashing the original off-main on every open
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Reuse the record's persisted content hash when the file-change signature still matches, and rehash on mismatch.
      result: pass
      notes: Import persists sourceChangeSignature beside the record; materialization reuses the hash via PortablePhotoSourceFingerprint.refreshing when isSameFileSnapshot matches, otherwise rehashes. Older records without a signature rehash once.
    - criterion: Measure the warm-edit first-pixel change with the last-known-frame capture and record it.
      result: pass
      notes: Release capture recorded in docs/TESTING.md (p95 283.0 ms vs prior 293 ms median). I did not re-run the Release capture.
    - criterion: Add a test that a matching signature does not re-read the file and a replaced file still rehashes.
      result: pass
      notes: testPersistedIdentityReusesHashForMatchingFileSignatureWithoutReadingFile deletes the file before refreshing; testPersistedIdentityRehashesWhenFileSignatureChanges covers replacement.
  checks_run:
    - swift test --filter PortablePhotoIdentityTests|LibraryBrowsingProjectionTests|PortableCacheIdentityTests|IdentityRegressionGateTests (27 tests, pass)
    - scripts/ci-tests.sh fast (1465 tests, exit 0)
    - git diff --check (clean)
  findings:
    - "Regression in 3563c62: PhotoAssetSource.makePortableIdentity with no persisted identity (fresh file imports) used decoderVersion legacy-fallback-v1 instead of imageio-<ext>-v1, changing cache identity for every such source. When hashing failed with a persisted identity, the stale persisted hash was kept instead of the unavailable-source hash. Both were fixed."
    - "Non-blocking: the bounded signature (size, mtime, resource id, first/last sample digest) can miss an in-place edit of a middle region that preserves size and mtime. This is acceptable for an app-owned package original."
  fixes:
    - Restored the previous decoder-version default and unavailable-file fallback in makePortableIdentity, keeping the new reuse path only when a persisted identity exists. Added testSourceWithoutPersistedIdentityKeepsImageIODecoderVersionAndHashesFile.
  verification_commits:
    - 8594fb35
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-02T02:28:38.243Z
  session: 01MUQC4FHUUHGP1346
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - performance
created: 2026-10-01T22:51:16.889Z
updated: 2026-10-02T02:28:38.246Z
parent: KRMA-747
blockers: []
order: a0
board: product
commits:
  - 8594fb35
---

## Objective

Reuse persisted record identity hash in PortableLibrarySession.materializedAsset instead of re-hashing the original off-main on every open

## Context

Found while verifying KRMA-747. `PortableLibrarySession.materializedAsset(for:)` builds a `PhotoAssetSource` from `record.identity`, but `PhotoAssetSource.init(url:id:data:...)` calls `makePortableIdentity`, which ignores the persisted `contentHash` and re-reads and SHA-256 hashes the whole original via `PortablePhotoSourceFingerprint.file(at:)`. The work runs in a detached task, so the main actor is not blocked and the KRMA-747 criteria hold. But every warm Edit open of a package photo still pays a whole-file read and hash before first pixel, and the doc comment says the persisted hash is published. That cost plausibly contributes to the warm first-pixel latency tracked in KRMA-748/KRMA-750.

## Acceptance criteria

- [ ] Reuse the record's persisted content hash when the file-change signature still matches (or the package original is known immutable), and rehash on mismatch.
- [ ] Measure the warm-edit first-pixel change with the last-known-frame capture and record it.
- [ ] Add a test that a matching signature does not re-read the file and a replaced file still rehashes.

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-10-02T02:19:03.982Z

Implemented in 3563c62. Package imports persist the bounded file-change signature beside the source identity; materialization reuses the stored SHA-256 when the signature matches and rehashes changed sources. Added matching/replacement tests and recorded the KRMA753 Release capture in docs/TESTING.md: warm Edit first-pixel p95 283.0 ms vs prior 293 ms median; exact/stale structural checks pass, first-pixel and grid budgets remain misses. Verified: swift test --filter 'PortablePhotoIdentityTests|LibraryBrowsingProjectionTests' (15 tests), git diff --check; Release last-known-frame capture completed.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-02T02:28:38.243Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Reuse the record's persisted content hash when the file-change signature still matches, and rehash on mismatch. (pass) — Import persists sourceChangeSignature beside the record; materialization reuses the hash via PortablePhotoSourceFingerprint.refreshing when isSameFileSnapshot matches, otherwise rehashes. Older records without a signature rehash once.
- [x] Measure the warm-edit first-pixel change with the last-known-frame capture and record it. (pass) — Release capture recorded in docs/TESTING.md (p95 283.0 ms vs prior 293 ms median). I did not re-run the Release capture.
- [x] Add a test that a matching signature does not re-read the file and a replaced file still rehashes. (pass) — testPersistedIdentityReusesHashForMatchingFileSignatureWithoutReadingFile deletes the file before refreshing; testPersistedIdentityRehashesWhenFileSignatureChanges covers replacement.
Checks run:
- swift test --filter PortablePhotoIdentityTests|LibraryBrowsingProjectionTests|PortableCacheIdentityTests|IdentityRegressionGateTests (27 tests, pass)
- scripts/ci-tests.sh fast (1465 tests, exit 0)
- git diff --check (clean)
Findings:
- Regression in 3563c62: PhotoAssetSource.makePortableIdentity with no persisted identity (fresh file imports) used decoderVersion legacy-fallback-v1 instead of imageio-<ext>-v1, changing cache identity for every such source. When hashing failed with a persisted identity, the stale persisted hash was kept instead of the unavailable-source hash. Both were fixed.
- Non-blocking: the bounded signature (size, mtime, resource id, first/last sample digest) can miss an in-place edit of a middle region that preserves size and mtime. This is acceptable for an app-owned package original.
Fixes:
- Restored the previous decoder-version default and unavailable-file fallback in makePortableIdentity, keeping the new reuse path only when a persisted identity exists. Added testSourceWithoutPersistedIdentityKeepsImageIODecoderVersionAndHashesFile.
Verification commits:
- 8594fb35
Actor: claude
Resolved model: sonnet
Pickup session: 01MUQC4FHUUHGP1346
Summary: Verified; fixed decoder-version regression for sources without persisted identity.
