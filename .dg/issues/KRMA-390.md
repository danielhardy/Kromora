---
id: KRMA-390
title: "Phase 1: replace path and inode identity with portable UUID identity"
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Every durable/render/preview/thumbnail/mask/analysis identity uses portable UUID/content identity inputs
      result: pass
      notes: PortablePhotoIdentity is authoritative for render, preview, thumbnail, mask, analysis, and current-edit measurement keys; package paths are not encoded.
    - criterion: Relocation preserves byte-identical cache keys without relink
      result: pass
      notes: Relocation and full synthetic-library identity gate pass; URL-backed source construction derives stable portable identity from content fingerprint.
    - criterion: Existing editor, render, mask, preview, thumbnail, import, and deletion behavior is preserved
      result: pass
      notes: Focused editor/deletion/cache tests pass; deletion cleanup now resolves the portable identity before removing analysis/edit records.
    - criterion: Approved current-data disposition is documented and exercised without silent migration
      result: pass
      notes: ADR-001 and docs/EDIT_STORE_IDENTITY_DISPOSITION.md record the approved no-shipped-data clean-slate EditStore.v2 disposition; legacy store is untouched.
    - criterion: Relocation, collision, invalidation, and stale-completion regression tests pass
      result: pass
      notes: Dedicated IdentityRegressionGateTests pass 4/4, including relocation, duplicate/collision behavior, cache invalidation, and stale preview/mask completion.
  checks_run:
    - swift test --no-parallel --filter CurrentEditMeasurementTests|PortableCacheIdentityTests|PhotoAnalysisCacheTests|IdentityRegressionGateTests (38/38 passed)
    - swift test --no-parallel --filter PortableCacheIdentityTests|PhotoAnalysisCacheTests|LibraryDeletionTests|EditDocumentStoreTests|IdentityRegressionGateTests (40/40 passed)
    - scripts/ci-tests.sh identity (4/4 passed)
    - swift build (passed)
    - dg validate --json (passed with existing unknown-model warnings only)
    - git diff --check (passed)
  findings:
    - The shared repository fast/full lanes still fail in unrelated asynchronous workflow tests (AutoAdjustment, export, LUT, semantic-mask I/O, comparison, filmstrip, and thumbnail lifecycle); the dedicated KRMA-390 identity lane and focused KRMA-390 tests pass.
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-13T10:40:00.386Z
  session: 01MTZM8RCM74EG7HJ4
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - library
  - architecture
  - identity
  - performance
created: 2026-09-12T19:19:14.175Z
updated: 2026-09-13T10:40:00.388Z
depends_on:
  - KRMA-389
  - KRMA-397
  - KRMA-398
  - KRMA-400
order: zzq
board: product
---

## Objective

Make durable and cache identity opaque and portable, independently of package layout. This is the
mechanical foundation for every later phase and must remain reviewable on its own.

## Dependencies

- KRMA-389 — the pre-change baseline must be committed before identity changes land.
- Human approval of the migration/disposition of current local `EditStore` data. The plan says no
  shipped user data exists, but this issue must not silently discard or rewrite data if that premise
  changes.

## Scope

Replace path, inode/device, canonical-path, and content-modification-date identity inputs across
`PhotoAssetID`, `PhotoSourceFingerprint`, `PhotoAssetSource.cacheKey`, `RenderCacheKey`, `MaskStore`,
`PreviewDiskCache`, and `EditRecord`/related persistence. Package-relative paths may only be resolved
to absolute URLs at the render boundary and must never enter durable/cache identity.

## Acceptance criteria

- [ ] Every durable/render/preview/thumbnail/mask/analysis identity is derived from opaque UUID plus
  immutable content hash, source revision, decoder version, and geometry where applicable.
- [ ] Moving the same source/package to another path and filesystem produces byte-identical cache
  keys and requires no relink.
- [ ] Existing editor, render, mask, preview, thumbnail, import, and deletion behavior is preserved;
  KRMA-371 deletion behavior is not bundled into this change.
- [ ] The approved current-data disposition is documented and exercised; no existing data is
  silently deleted or migrated by an identity-only change.
- [ ] Relocation, collision, cache invalidation, and stale-completion regression tests pass.

## Verification lane

Identity/unit and render-cache regression lane, plus the committed relocation benchmark gate from
KRMA-389. Run the focused tests, `swift build`, `dg validate`, and `git diff --check`.

### Comment — codex @ 2026-09-13T10:39:46.039Z

Implemented portable identity integration across source construction, thumbnail/render/mask/preview/analysis caches, current-edit measurement persistence, and deletion cleanup. Added relocation/cache/invalidation/serialization regression coverage. Existing legacy path-based types remain compatibility-only; durable/cache keys use PortablePhotoIdentity. Verification: focused identity/cache/measurement tests 38/38; deletion/editor/cache regression set 40/40; dedicated identity CI lane 4/4; swift build, dg validate, and git diff --check pass. The repository fast/full suites still have unrelated pre-existing async workflow failures in AutoAdjustment, export, LUT, masking, comparison, filmstrip, and thumbnail lifecycle tests; no KRMA-390 identity gate failures.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-13T10:40:00.386Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Every durable/render/preview/thumbnail/mask/analysis identity uses portable UUID/content identity inputs (pass) — PortablePhotoIdentity is authoritative for render, preview, thumbnail, mask, analysis, and current-edit measurement keys; package paths are not encoded.
- [x] Relocation preserves byte-identical cache keys without relink (pass) — Relocation and full synthetic-library identity gate pass; URL-backed source construction derives stable portable identity from content fingerprint.
- [x] Existing editor, render, mask, preview, thumbnail, import, and deletion behavior is preserved (pass) — Focused editor/deletion/cache tests pass; deletion cleanup now resolves the portable identity before removing analysis/edit records.
- [x] Approved current-data disposition is documented and exercised without silent migration (pass) — ADR-001 and docs/EDIT_STORE_IDENTITY_DISPOSITION.md record the approved no-shipped-data clean-slate EditStore.v2 disposition; legacy store is untouched.
- [x] Relocation, collision, invalidation, and stale-completion regression tests pass (pass) — Dedicated IdentityRegressionGateTests pass 4/4, including relocation, duplicate/collision behavior, cache invalidation, and stale preview/mask completion.
Checks run:
- swift test --no-parallel --filter CurrentEditMeasurementTests|PortableCacheIdentityTests|PhotoAnalysisCacheTests|IdentityRegressionGateTests (38/38 passed)
- swift test --no-parallel --filter PortableCacheIdentityTests|PhotoAnalysisCacheTests|LibraryDeletionTests|EditDocumentStoreTests|IdentityRegressionGateTests (40/40 passed)
- scripts/ci-tests.sh identity (4/4 passed)
- swift build (passed)
- dg validate --json (passed with existing unknown-model warnings only)
- git diff --check (passed)
Findings:
- The shared repository fast/full lanes still fail in unrelated asynchronous workflow tests (AutoAdjustment, export, LUT, semantic-mask I/O, comparison, filmstrip, and thumbnail lifecycle); the dedicated KRMA-390 identity lane and focused KRMA-390 tests pass.
Fixes:
- None
Verification commits:
- 9c1fd08
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTZM8RCM74EG7HJ4
Summary: Integrated portable UUID/content identity across durable and cache boundaries; preserved legacy compatibility and documented approved clean-slate EditStore disposition.
