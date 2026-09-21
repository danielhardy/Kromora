---
id: KRMA-397
title: "Phase 1.1: opaque UUID + content-hash identity core types"
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Portable identity uses opaque UUID plus content hash, source revision, decoder version, and optional geometry with no path/inode/mtime storage
      result: pass
      notes: PortablePhotoAssetID, PortablePhotoSourceFingerprint, and PortablePhotoIdentity contain only portable value fields; file hashing consumes URL bytes without retaining the URL.
    - criterion: Package-relative paths resolve only at the render boundary and do not enter identity values
      result: pass
      notes: RenderBoundarySourceResolver is a dedicated boundary helper; tests cover valid resolution and package escape rejection, and portable identity cache/canonical data contain no paths.
    - criterion: Existing call sites remain unaffected
      result: pass
      notes: The legacy PhotoAssetID/PhotoSourceFingerprint and all existing consumers remain unchanged; the new layer is additive.
    - criterion: Relocation-equivalence tests pass
      result: pass
      notes: Different paths and a move/rename produce equal portable fingerprints and byte-identical combined identities when the durable UUID is preserved.
    - criterion: Required verification passes
      result: pass
      notes: swift build; swift test --filter PortablePhotoIdentityTests; scripts/ci-tests.sh fast (937 passed); dg validate; git diff --check.
  checks_run:
    - swift build
    - swift test --filter PortablePhotoIdentityTests
    - scripts/ci-tests.sh fast
    - dg validate
    - git diff --check
  findings: []
  fixes: []
  verification_commits:
    - 7e3a5b9
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-12T21:30:02.924Z
  session: 01MTYW8L5XPWNTUOQD
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - identity
created: 2026-09-12T19:44:11.717Z
updated: 2026-09-12T21:30:02.925Z
depends_on:
  - KRMA-389
order: zzv
board: product
commits:
  - 7e3a5b9
---

## Objective

Define and implement the new opaque-identity core types — the mechanical foundation every other
Phase 1 change (cache-layer migration, persistence migration) builds on — without wiring them into
`RenderCacheKey`, `MaskStore`, `PreviewDiskCache`, or `EditRecord` yet.

## Dependencies

- KRMA-389 (Phase 0 baseline must be committed before any identity change lands).

## Scope

- Design and implement the new identity shape for `PhotoAssetID` and `PhotoSourceFingerprint`:
  opaque UUID for durable identity, plus an immutable content hash, source revision, decoder version,
  and geometry where applicable — with no path, inode/device, canonical-path, or content-modification
  date as an input.
- Add the resolution boundary: package-relative paths may only be turned into absolute URLs at the
  render boundary (i.e. add/adjust the specific function(s) that do this resolution), and must never
  leak into any durable or cache identity value.
- Land the new types alongside the existing ones (do not yet delete the old identity path — that
  happens once every consumer listed in the sibling cache-layer and persistence tickets has migrated),
  so this change is independently reviewable and does not regress current behavior.
- Unit tests for the new types: two different paths/filesystems for the same content produce
  byte-identical identity; moving/renaming the same content preserves identity; different content at
  the same path produces different identity.

## Acceptance criteria

- [ ] `PhotoAssetID` and `PhotoSourceFingerprint` are derived only from opaque UUID + content hash +
  source revision + decoder version + geometry (where applicable) — no path/inode/mtime input.
- [ ] Package-relative-to-absolute-URL resolution exists only at the render boundary; a grep/test
  confirms no identity/cache-key type holds a resolved absolute path.
- [ ] Existing call sites are unaffected (new types are additive in this ticket; migration is scoped
  to the sibling tickets).
- [ ] Relocation-equivalence unit tests pass (same content, different path/filesystem → identical
  identity).
- [ ] `swift build`, `swift test` (fast lane), `dg validate`, and `git diff --check` pass.

## Verification lane

Identity/unit lane. Focused tests on the new types only — no render-cache or persistence
integration yet (covered by sibling tickets).

## Context

- context.files: Sources/KromoraKit/Models (PhotoAssetID, PhotoSourceFingerprint)
- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/ENGINEERING_GUIDE.md
- context.issues: KRMA-390, KRMA-389

## Agent log

- 2026-09-12T21:30:02.924Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Portable identity uses opaque UUID plus content hash, source revision, decoder version, and optional geometry with no path/inode/mtime storage (pass) — PortablePhotoAssetID, PortablePhotoSourceFingerprint, and PortablePhotoIdentity contain only portable value fields; file hashing consumes URL bytes without retaining the URL.
- [x] Package-relative paths resolve only at the render boundary and do not enter identity values (pass) — RenderBoundarySourceResolver is a dedicated boundary helper; tests cover valid resolution and package escape rejection, and portable identity cache/canonical data contain no paths.
- [x] Existing call sites remain unaffected (pass) — The legacy PhotoAssetID/PhotoSourceFingerprint and all existing consumers remain unchanged; the new layer is additive.
- [x] Relocation-equivalence tests pass (pass) — Different paths and a move/rename produce equal portable fingerprints and byte-identical combined identities when the durable UUID is preserved.
- [x] Required verification passes (pass) — swift build; swift test --filter PortablePhotoIdentityTests; scripts/ci-tests.sh fast (937 passed); dg validate; git diff --check.
Checks run:
- swift build
- swift test --filter PortablePhotoIdentityTests
- scripts/ci-tests.sh fast
- dg validate
- git diff --check
Findings:
- None
Fixes:
- None
Verification commits:
- 7e3a5b9
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTYW8L5XPWNTUOQD
Summary: Added additive portable UUID/content-hash identity types, render-boundary relative-path resolution, and relocation/content-change tests.
