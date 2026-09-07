---
id: LUMO-255
title: MaskStore pixel payloads out of JSON (binary storage + render-cache reuse)
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: No code path text-encodes mask pixel buffers at any size; a 60MP refine/store/load cycle completes in seconds
      result: pass
    - criterion: Opening a photo with a semantic layer twice recomputes nothing the second time
      result: pass
    - criterion: Legacy inline-JSON mask files either keep loading or are explicitly orphaned with re-analysis
      result: pass
    - criterion: swift build, swift test pass with zero Swift 6 concurrency diagnostics and zero opt-outs (PackageSettingsTests)
      result: pass
  checks_run:
    - swift build (passed)
    - swift test --filter RegionMaskTests|LocalMaskRenderingTests|MaskRefinement (26 passed, 0 failures)
    - swift test --filter PackageSettingsTests (3 passed, 0 failures)
    - swift test (917 passed, 41 skipped, 0 failures)
    - git diff --check on commit 8c5e72f (passed)
  findings: []
  fixes: []
  verification_commits:
    - 8c5e72fef66f72645e687070754f46c5f6063568
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-07T00:09:20.619Z
  session: 01MTQH9F8M1M0V37NA
labels:
  - persistence
  - masking
created: 2026-09-06T22:58:06.369Z
updated: 2026-09-07T04:02:47.091Z
depends_on:
  - LUMO-244
  - LUMO-245
order: g9sifjst
board: product
commits:
  - 8c5e72fef66f72645e687070754f46c5f6063568
---

## Objective

Give `MaskStore` (`~/Library/Application Support/Lumo/Masks/`) the same treatment this epic
gives `edit-records.json`: its pixel payloads must never be text-encoded again, and
full-resolution refinements must be reused, not recomputed per open. This is the second,
independent JSON store the epic as written does not cover — and the more dangerous one.

## Context

Incident (2026-09-06): once semantic-mask resolution started succeeding on a 60MP RAW, opening
any photo with a person layer spun forever. Root cause was `MaskStore.store` JSON-encoding the
refined mask — ~60M floats become a ~500MB JSON document, minutes to encode and minutes to
decode back, on the main-render path. Before that, resolution failed fast (union/gate bugs), so
the photo loaded minus its wash and the cliff stayed hidden.

An interim fix already landed on `main` and bounds the damage, so this ticket is consolidation,
not firefighting:

- `MaskStore.swift` — pixels persist as a raw-Float32 sidecar (`mask-<digest>.bin`) next to a
  small JSON metadata file. Measured: storing 6M floats takes ~0.03s (the JSON equivalent at
  60MP was minutes). `PersistedPixels.values` is optional so pre-sidecar inline-JSON files keep
  loading — the person gate depends on those cached face/foreground entries.
- `MaskRefinement.swift` — `refine` returns a stored `.render` entry when present instead of
  recomputing (and re-persisting) the full-resolution mask on every open.
- `LocalMaskRendering.swift` — `apply` has an identity fast-path (feather 0 / shift 0 /
  density 1) so untouched definitions skip a 60M-element map at render quality.

The critical shift for whoever picks this up: the win is **binary pixels + no recompute**, not
"SwiftData" as such. A 60M-float blob in a SwiftData `Data` attribute without external storage
is 240MB inside the SQLite file, faulted in whole on every read — better than JSON, but no
better than the sidecar, with more machinery around it. If this store moves into SwiftData,
model the *metadata* there and keep pixels as external-storage blobs (or keep the sidecars and
say so explicitly); stuffing text-encoded floats into any backend re-creates this bug exactly.

## Work

- Decide: (a) move `MaskStore` metadata (+ binary pixel blobs) into the epic's SwiftData
  container, or (b) keep the sidecar files as the permanent design and document the split
  (edits in SwiftData, mask pixels in flat files). Either is defensible; "pixels as JSON inside
  SwiftData" is not an option.
- If (a): `Data` blob attributes with external storage enabled; preserve the exact-key lookup
  semantics (`mask(for:quality:)` never substitutes a lower quality) and the metadata-only
  existence check (gating lookups must not fault pixel blobs).
- Either way, preserve: the `.render` reuse check in `refine`, the `apply` identity fast-path,
  and loading of legacy inline-JSON payloads — or explicitly orphan them, accepting a full
  Vision re-analysis pass on first launch after upgrade (masks are a recomputable cache, so
  orphaning is viable but must be a conscious choice, not a silent gate failure).
- Coordinator/provider API surface unchanged (`mask`, `pixels`, `refineMask` signatures stand).

## Acceptance criteria

- [ ] No code path text-encodes mask pixel buffers at any size (no `[Float]` → JSON numbers);
      a 60MP refine/store/load cycle completes in seconds, not minutes, in a debug build.
- [ ] Opening a photo with a semantic layer twice in a row recomputes nothing the second time
      (refinement reused from the store).
- [ ] Legacy inline-JSON mask files either keep loading or are explicitly orphaned with
      re-analysis; neither case surfaces as "mask could not be resolved."
- [ ] `swift build`, `swift test` pass with zero Swift 6 concurrency diagnostics and zero
      opt-outs (`PackageSettingsTests`).

## Depends on

Epic (LUMO-244) for shared constraints (Swift 6 zero-opt-out, no CloudKit); spike (LUMO-245)
for the `@Model`/`@ModelActor` viability answer if option (a) is chosen.


### Comment — codex @ 2026-09-07T00:03:25.257Z

Implemented and verified LUMO-255. MaskStore now writes raw Float32 sidecars with metadata-only JSON, structurally prevents new float arrays from being JSON-encoded, validates sidecar sizes, and keeps legacy inline payloads readable. Render refinement reuses exact-size cached results, neutral semantic definitions use the identity fast path, and the permanent sidecar/edit-persistence split is documented in docs/MASK_PERSISTENCE.md. Added focused sidecar, legacy-load, cache-reuse, target-size, and metadata tests. Verification: swift build; swift test (917 passed, 41 skipped, 0 failures); git diff --check; dg validate. Commit: 8c5e72f.

## Agent log

- 2026-09-07T00:09:20.625Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] No code path text-encodes mask pixel buffers at any size; a 60MP refine/store/load cycle completes in seconds (pass)
- [x] Opening a photo with a semantic layer twice recomputes nothing the second time (pass)
- [x] Legacy inline-JSON mask files either keep loading or are explicitly orphaned with re-analysis (pass)
- [x] swift build, swift test pass with zero Swift 6 concurrency diagnostics and zero opt-outs (PackageSettingsTests) (pass)
Checks run:
- swift build (passed)
- swift test --filter RegionMaskTests|LocalMaskRenderingTests|MaskRefinement (26 passed, 0 failures)
- swift test --filter PackageSettingsTests (3 passed, 0 failures)
- swift test (917 passed, 41 skipped, 0 failures)
- git diff --check on commit 8c5e72f (passed)
Findings:
- None
Fixes:
- None
Verification commits:
- 8c5e72fef66f72645e687070754f46c5f6063568
Actor: claude
Resolved model: sonnet
Pickup session: 01MTQH9F8M1M0V37NA
Summary: Verified: mask pixels persist as raw Float32 sidecars with metadata-only JSON, refinement reuses stored render results, and legacy inline payloads still load. No blockers.
