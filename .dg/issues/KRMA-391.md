---
id: KRMA-391
title: "Phase 2: implement portable package format, transactions, and import"
type: feature
status: ready
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - library
  - architecture
  - persistence
  - import
created: 2026-09-12T19:19:18.353Z
updated: 2026-09-12T23:35:33.179Z
depends_on:
  - KRMA-390
  - KRMA-401
  - KRMA-402
  - KRMA-403
  - KRMA-404
  - KRMA-405
order: zzx
board: product
---

## Objective

Ship the local-only package format and crash-safe import/edit persistence, without introducing the
large-library index rewrite. The package becomes the canonical source of truth only after its format
and transaction invariants are proven.

## Dependencies

- KRMA-390 — portable identity and the relocation gate must be green.
- Approved package-format, migration, and compatibility decisions recorded against KRMA-384.

## Scope

Implement `manifest.json`, 256 membership shards with denormalised summaries, asset records,
revisioned XMP/Kromora edit sidecars, embedded/deduplicated Look bytes, recovery journals,
same-volume staging, flush/checksum/atomic commit, single-writer lease, and copy-on-import with
streamed SHA-256, duplicate detection, cancellation, and `clonefile` where appropriate. Reserve
referenced-asset fields and resolver support, but expose no referenced-asset UI. Keep derived
thumbnails/previews rebuildable and keep iCloud sync out of scope.

## Acceptance criteria

- [ ] A copied package opens on another path/filesystem with identical asset/edit/cache identity and
  no relink; unknown JSON keys survive rewrite.
- [ ] A commit is serialized, journaled, checksum-verified, atomically published, and recoverable
  after injected failure at every transaction boundary.
- [ ] Imports read each original once for copy/hash, publish progressively, detect duplicates, and
  never modify/delete the external source or publish partial assets.
- [ ] Malformed/truncated XMP, disk-full, cancellation, missing originals, corrupt records/shards,
  and lease contention follow the critical/rebuildable recovery policy.
- [ ] Current deletion behavior and current user data are not silently changed; any migration is a
  separately approved operation.
- [ ] Format, transaction, import, recovery, relocation, compatibility, and fault-injection tests
  pass with `swift build`, `dg validate`, and `git diff --check`.

## Verification lane

Persistence/import fault-injection lane, including clean-profile package-copy tests and filesystem
relocation. No UI performance claim is accepted until the Phase 3 scale lane exists.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
