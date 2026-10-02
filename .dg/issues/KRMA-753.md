---
id: KRMA-753
title: Reuse persisted record identity hash in PortableLibrarySession.materializedAsset instead of re-hashing the original off-main on every open
type: task
status: backlog
priority: low
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - performance
created: 2026-10-01T22:51:16.889Z
updated: 2026-10-01T22:51:16.889Z
parent: KRMA-747
blockers: []
order: zz
board: product
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
