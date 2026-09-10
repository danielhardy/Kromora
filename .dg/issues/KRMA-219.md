---
id: KRMA-219
title: Render ordered local adjustments through resolved soft masks
type: feature
status: done
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - epic:masking
  - masking
  - rendering
  - performance
created: 2026-09-04T21:48:29.389Z
updated: 2026-09-10T12:53:48.097Z
depends_on:
  - KRMA-218
  - KRMA-228
order: lqs82auj
board: product
commits:
  - 58a690a
---

## Objective

Extend the shared render graph so ordered local adjustments blend through resolved soft masks with
structural preview/export parity.

## Context

The masking UI is only useful once `EditDocument` masks affect pixels. Lumo must retain one render
pipeline and keep Core Image/Metal objects inside `RenderEngine`, while supporting disposable
semantic caches, analytic gradients, vector brushes, soft composition, and cancellation.

## Acceptance criteria

- [ ] Introduce a sendable `LocalMaskResolving` boundary; `RenderEngine` remains the owner of all
      `CIImage`, filter, kernel, texture, and live `CIContext` resources.
- [ ] Insert ordered local layers after existing pre-LUT global work and before LUT/crop/vignette/
      grain, as specified in the plan.
- [ ] For each layer, build an adjusted variant from the layer input and blend it over that input
      through the effective soft mask, amount, and inversion before evaluating the next layer.
- [ ] Support the initial local controls: Exposure, Contrast, Highlights, Shadows, Whites, Blacks,
      Temperature, Tint, Saturation, Texture, Clarity, and Dehaze, sharing mapping math with global
      controls instead of creating divergent formulas.
- [ ] Implement renderer seams for semantic payloads, brush rasterization, and analytic linear/radial
      descriptors, plus deterministic replace/add/subtract/intersect composition.
- [ ] Key bounded derived caches by source fingerprint, definition hash, target dimensions/quality,
      transform, and mask-renderer version without invalidating on unrelated global slider changes.
- [ ] Disabled, zero-amount, empty-mask, and neutral-adjustment layers are exact no-ops.
- [ ] Synthetic soft-mask tests pin alpha blending, ordered behavior, extent/orientation/color-space
      contracts, finite output, cancellation/error behavior, and preview/export agreement.
- [ ] Existing render-stack tests still prove there is no additional live-path `CIContext`.

## Implementation notes

Follow Sections 3.3 and 6 plus Step 2 of `docs/ENGINEERING_GUIDE.md`. Primary seams
are `RenderRequest.swift`, `RenderPipeline.swift`, `RenderEngine.swift`, render cache resources, and
the local-mask model from KRMA-218.

Manual/analytic masks must render without a semantic cache. Export must wait for a required valid
smart mask or report an actionable error; it must never silently use another source's pixels.

### Comment — codex @ 2026-09-05T02:28:49.906Z

Implemented in commit 58a690a. Added the sendable LocalMaskResolving seam, RenderEngine-owned mask rasterization/composition and bounded derived cache, ordered local adjustment placement before LUT/crop/vignette/grain, shared global mapping math for the initial local controls, strict semantic export errors, and preview/export parity coverage. Verification: LocalMaskRenderingTests 4/4, RenderEngineTests 26/26, RenderCacheTests 21/21 (1 expected skip), RenderRequestTests 6/6, RenderStackTests 2/2; git diff --check and dg validate pass. Full-suite parallel failures were pre-existing dirty-worktree failures outside this issue.

### Comment — claude @ 2026-09-05T02:33:52.148Z

Verification: BLOCKED (returning to review, not completing to done).

Verdict: blocked
Checks run:
- swift build (working tree as-is): succeeds.
- swift test --filter LocalMaskRenderingTests|RenderEngineTests|RenderCacheTests|RenderRequestTests|RenderStackTests: 59/59 pass, matches the implementation comment's claim.
- swift test --filter PackageSettingsTests: 1 pre-existing failure in untracked Sources/LumoMaskOverlayCapture/MaskOverlayCapture.swift (@unchecked Sendable) — unrelated to this issue's scope, matches the "pre-existing dirty-worktree failures" note already on this ticket.
- Clean-checkout verification: created a throwaway worktree at current HEAD via scripts/agent-worktree.sh (tracked files only) and ran swift build.

Blocking finding:
- Commit 58a690a ("KRMA-219 render local adjustments through soft masks") is not self-contained. It
  references EditDocument.localAdjustments and the LocalAdjustmentLayer/MaskComponent/MaskSource/
  LocalAdjustments/SemanticMaskDefinition/BrushMaskDefinition/LinearGradientDefinition/
  RadialGradientDefinition/MaskCombineMode types from KRMA-218 (Sources/LumoKit/Models/
  LocalMaskModels.swift), none of which were ever committed to git (`git ls-files` shows
  LocalMaskModels.swift and MaskInteractionState.swift as untracked; `git show HEAD:Sources/LumoKit/
  Models/EditDocument.swift` has no `localAdjustments` property). A clean worktree built from HEAD
  fails with "cannot find type 'LocalAdjustmentLayer' in scope" and related errors. KRMA-218 is
  marked done/verification-pass, but that pass recorded no verification_commits and did not catch
  that KRMA-218 has no corresponding commit at all.
- Net effect: the feature only exists in the current uncommitted working tree. Any fresh clone,
  CI checkout, or `git bisect` at this branch's HEAD does not build.

Non-blocking findings (filed as verification-labeled follow-up, not fixed here since they are outside
"localized, testable fix" scope and touch product/UX behavior):
- resolvedLocalMasks in RenderEngine.swift composes a layer's first usable component against an
  empty mask (localMaskRenderer.emptyMask). For mode == .intersect this yields
  MaskComposition.combine(0, b, .intersect) == min(0, b) == 0 always, so a layer whose first usable
  component has isEnabled composition mode "intersect" (e.g. after reordering/deleting an earlier
  "replace" component) is permanently an exact no-op regardless of geometry. This matches the pure
  MaskComposition math and the GPU kernel exactly (so preview/export stay consistent with each
  other), but there is no test coverage for multi-component composition at all, and the "first
  component is intersect" case has no guard the way "first component is subtract" implicitly does
  (subtract against empty is at least visually explainable). Recommend a product decision + test
  coverage in the Step 8 component-composition ticket.

Action taken: created KRMA-228 (urgent) to land KRMA-218's model files as a real commit, made
KRMA-219 depend on it, and returned this issue to review per the "unresolved blocker" verification
path. Lease/claim left in place for DispatchGraph's normal handoff.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-05T04:12:23.188Z: Completed after landing the missing KRMA-218 model prerequisite in fe95f16 and verifying the clean checkout. Render, cache, request, stack, local-mask, and package-settings checks pass; the separate first-component-intersect composition edge case remains tracked as a non-blocking follow-up.
