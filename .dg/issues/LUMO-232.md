---
id: LUMO-232
title: Dead requestRevision guard in RenderEngine.resolvedLocalMasks gives false staleness protection
type: task
status: done
priority: low
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - masking
  - rendering
created: 2026-09-05T14:58:51.372Z
updated: 2026-09-06T02:44:07.989Z
parent: LUMO-224
depends_on:
  - LUMO-224
order: w
board: product
commits:
  - 49f8b65
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Remove the inert payload requestRevision field/guard or make it genuinely diverge
      result: pass
    - criterion: Add regression coverage that rejects a superseded async mask result
      result: pass
    - criterion: swift build and swift test continue to pass with no caller behavior change
      result: pass
  checks_run:
    - swift build (passes)
    - swift test --filter LocalMaskRenderingTests (9 tests, 0 failures)
    - swift test (882 tests, 42 skipped, 0 failures)
    - dg validate (OK; pre-existing unknown pickup-runner model warning)
    - git diff --check (passes)
  findings: []
  fixes: []
  verification_commits:
    - 49f8b65
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-06T02:44:07.982Z
  session: 01MTP7CD1HGF6FNTO9
---

## Objective

Make `requestRevision` in `RenderEngine.resolvedLocalMasks` actually detect staleness, or remove it
if it cannot, so the field stops implying protection it does not provide.

## Context

LUMO-224 threaded `requestRevision` through `RenderRequest` → `LocalMaskResolveRequest` →
`LocalMaskPayload`, and added a guard in `RenderEngine.resolvedLocalMasks`
(`Sources/LumoKit/Models/RenderEngine.swift`, near the `payload.requestRevision == requestRevision`
check) intended to satisfy the acceptance criterion "request revision ... checked before any async
result is published or rendered."

In review, this guard is vacuously true on every path:
- Cache hits are re-stamped via `LocalMaskPayload.forRequestRevision(requestRevision)` immediately
  before the check, using the very value the check compares against.
- Resolver-produced payloads (`CoordinatorLocalMaskResolver.resolve`, `DefaultLocalMaskResolver`)
  simply echo back `request.requestRevision` into the returned payload.

So `payload.requestRevision` can never differ from the local `requestRevision` parameter at the
comparison site — the guard can never fail, and it currently protects nothing. Real staleness
protection against a revision that changed while an async render was in flight is already handled
independently in `AppViewModel` via its own `sourceRevision`/`displayRevision` gate at publication
(`AppViewModel.swift` around the `publication.sourceRevision == sourceRevision` guard).

This is not a functional bug — no test currently exercises a real mismatch, and the existing
`assetID`/`sourceFingerprint` checks in the same guard clause do the real work of rejecting a
wrong-photo mask. But the `requestRevision` field and check currently exist purely as inert
plumbing, which risks misleading a future reader (or a future refactor) into believing this call
site enforces revision-based staleness rejection when it does not.

## Acceptance criteria

- [ ] Either wire `requestRevision` to a value that can actually diverge from the request's own
      revision at the comparison site (so the guard can fail and a regression test can prove it
      does), or remove the field/guard and document that revision-staleness protection lives solely
      in `AppViewModel`'s publication gate.
- [ ] Add or update a test that would fail if this specific protection regressed (i.e., a test that
      cannot pass by construction the way the current plumbing does).
- [ ] `swift build` and `swift test` continue to pass with no product-behavior change for callers.

## Implementation notes

<!-- Approach, constraints, links -->
Scope is intentionally narrow: this is a maintainability/false-confidence cleanup around one guard
clause, not a request to redesign cancellation or revision tracking.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-06T02:44:07.987Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Remove the inert payload requestRevision field/guard or make it genuinely diverge (pass)
- [x] Add regression coverage that rejects a superseded async mask result (pass)
- [x] swift build and swift test continue to pass with no caller behavior change (pass)
Checks run:
- swift build (passes)
- swift test --filter LocalMaskRenderingTests (9 tests, 0 failures)
- swift test (882 tests, 42 skipped, 0 failures)
- dg validate (OK; pre-existing unknown pickup-runner model warning)
- git diff --check (passes)
Findings:
- None
Fixes:
- None
Verification commits:
- 49f8b65
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTP7CD1HGF6FNTO9
Summary: Removed requestRevision from LocalMaskResolveRequest and LocalMaskPayload so reusable mask payloads no longer imply revision validation; retained RenderEngine supersession checks and added deterministic stale-resolver regression coverage.
