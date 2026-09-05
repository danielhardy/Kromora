---
id: LUMO-218
title: Add durable local-mask model, document schema v2, and interaction draft state
type: feature
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-05T02:12:04.456Z
  session: 01MTNQM72NLEJBMG0X
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - epic:masking
  - masking
  - domain
  - persistence
created: 2026-09-04T21:48:28.936Z
updated: 2026-09-05T04:03:09.711Z
depends_on:
  - LUMO-217
order: n
board: product
---

## Objective

Add the versioned value-state foundation for editable local-adjustment layers and keep transient
mask gestures outside the durable document until commit.

## Context

`EditDocument` currently cannot own a mask. Persisting `RegionMaskReference` alone would make edits
depend on disposable cache pixels, while mutating the document for every pointer sample would make
undo, hashing, and persistence too expensive. The document must persist recipes: semantic intent,
normalized brush vectors, and analytic gradient geometry.

## Acceptance criteria

- [ ] Add `LocalAdjustmentLayer`, `MaskComponent`, `MaskCombineMode`, `MaskSource`, focused
      `LocalAdjustments`, and semantic/brush/linear/radial definition values as validated
      `Codable`, `Sendable`, and `Equatable` types.
- [ ] Persist all geometry in normalized upper-left oriented-source coordinates; brush radii are
      relative to the source's shorter side and gradients remain resolution independent.
- [ ] Brush definitions store vector samples and settings, not authoritative raster tiles; smart
      definitions store semantic intent/refinement, not only a cache reference.
- [ ] Add ordered `localAdjustments` to `EditDocument`, advance to schema v2, and migrate v1 as an
      empty local-layer array while rejecting unsupported future versions.
- [ ] Update document identity, visible-look detection, comparison baseline, edit hash, reset,
      copy/paste, undo/redo, and persistence semantics.
- [ ] Add narrow `MaskInteractionState` draft/selection/tool state that does not publish through the
      whole `AppViewModel`; commit/cancel behavior is explicit and testable.
- [ ] Neutral/empty local state is byte/pixel behavior-compatible with existing documents, malformed
      numeric/geometry data is handled deterministically, and round-trip/migration tests pass.

## Implementation notes

Follow Sections 3 and 4 plus Step 1 of `docs/MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md`. Likely work is
centered in new local-mask model files plus `EditDocument.swift`, `EditHistory.swift`,
`EditDocumentStore.swift`, `EditClipboard.swift`, and `CanvasNavigation.swift`.

Do not add Core Image or Vision code here. Large pointer streams stay transient and enter the
document once per completed gesture so history snapshots retain Swift Array copy-on-write benefits.

### Comment — codex @ 2026-09-05T04:03:09.698Z

Repair landed in commit fe95f16. Committed LocalMaskModels.swift, MaskInteractionState.swift, LocalMaskTests.swift, and the EditDocument/EditClipboard/EditDocumentStore/AppViewModel integration required by this issue. Clean-checkout build/test verification follows.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-05T02:12:04.462Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTNQM72NLEJBMG0X
Summary: Implemented durable local-mask value state, schema v2 migration, document identity/comparison/copy-paste integration, validated normalized geometry and alpha composition, and isolated mask draft/selection/tool interaction state. Focused model/document tests pass; full-suite note recorded in handoff.
