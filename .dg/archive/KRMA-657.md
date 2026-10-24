---
id: KRMA-657
title: Heal frequency-separation blurs full image extent per spot
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: lowFrequencyImage (or its call sites) computes the blur over a region sized to the spot rather than the full image extent
      result: pass
      notes: The frequency-separation lowFrequencyImage/CIGaussianBlur-over-full-extent path from KRMA-650/aed117d no longer exists. It was superseded by a pull/push membrane technique (commits 353d5a4..4a85eaf) that already confines destination, fill, mask, and the multi-level pyramid to spot-specific workBounds (RetouchRenderer.swift:45-61, 105-145). cd5bf9b adds a clarifying comment and a locking regression test on top of that pre-existing local-bounds behavior; it does not itself change the render graph.
    - criterion: Heal/Clone pixel output is unchanged for existing regression coverage
      result: pass
      notes: "Ran RenderPipelineTests (serial CI lane): testManuallySourcedHealAndCloneProduceDifferentLocalFills, testHealMembraneExcludesPixelsInsideTheHole, testHealOverFlatExteriorDoesNotOvershootDestinationTone, testRetouchSpotChangesRenderedPixelsAndNeutralRetouchIsIdentity, testRetouchRecipeStaysInOrientedSourceSpaceAcrossGeometry all pass (47 tests, 2 skipped RAW-fixture tests, 0 failures)."
    - criterion: A benchmark or reasoned argument shows per-spot cost no longer scales with total image resolution for a fixed spot radius
      result: pass
      notes: New test testSpotWorkBoundsStayConstantForTheSamePixelRadiusAtHigherResolution (RetouchModelTests) asserts workBounds size is identical at 4000x3000 and 8000x6000 for the same pixel radius, and the existing testSpotWorkBoundsStayLocalAtLargeSourceSizes bounds the window as a small fraction of a 6000x4000 image. Since every Gaussian blur/downsample/upsample/pull/push step in healedFill operates on images already cropped to workBounds (not image.extent), per-spot cost tracks the constant work-window size, not total resolution.
  checks_run:
    - swift build
    - swift test --filter 'RetouchModelTests|RetouchWorkflowCoordinatorTests' (12 tests, 0 failures)
    - swift test --filter 'RenderPipelineTests' (47 tests, 2 skipped, 0 failures)
    - swift test --filter 'PackageSettingsTests' (4 tests, 0 failures, confirms Swift 6 mode invariants untouched)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T21:41:27.805Z
  session: 01MUKCCNRDKH3VDKVB
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-27T17:30:27.451Z
updated: 2026-09-28T14:41:34.921Z
parent: KRMA-650
blockers: []
order: ns2n4ak0
board: product
---

## Objective

Restrict the Heal kernel's frequency-separation blur to the spot's local region instead of the
full image extent, so Heal's per-spot cost stops scaling with total image size.

## Context

`RetouchRenderer.healedPatch` (Sources/KromoraKit/Models/RetouchRenderer.swift, added in
KRMA-650/aed117d) computes `lowFrequencyImage` for both the sampled patch and the destination by
running `CIGaussianBlur` over the *entire* `image.extent`, then cropping, once per heal spot. On a
multi-ten-megapixel RAW image with several heal spots this repeats a full-frame blur pass per
spot even though only a small region around each spot's radius is ever sampled by the
`healTexture` kernel. Clone has no equivalent cost. This is a performance-only finding from
verification of KRMA-650, not a correctness defect — the current behavior is pixel-correct, just
more expensive than necessary.

## Acceptance criteria

- [ ] `lowFrequencyImage` (or its call sites) computes the blur over a region sized to the spot
      (e.g. destination/source rect padded by the blur radius) rather than the full image extent.
- [ ] Heal/Clone pixel output is unchanged for existing regression coverage
      (`testHealPreservesDestinationAppearanceWhileCloneCopiesSampledPatch` and friends).
- [ ] A benchmark or reasoned argument shows per-spot cost no longer scales with total image
      resolution for a fixed spot radius.

## Implementation notes

Candidate approach: clamp/crop the patch and destination inputs to
`destinationRect.insetBy(dx: -blurRadius, dy: -blurRadius).intersection(image.extent)` before the
Gaussian blur, then let the kernel's `roiCallback` request only that region.

### Comment — codex @ 2026-09-27T21:39:02.432Z

The heal path in this checkout already evaluates its pull/push pyramid within the spot-specific workBounds. Added a fixed-pixel-radius scaling regression and documented that local boundary. Verified with the work-bounds tests plus the heal/clone difference, hole-exclusion, and flat-exterior regressions; all passed. Commit: cd5bf9b.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-27T21:41:27.805Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] lowFrequencyImage (or its call sites) computes the blur over a region sized to the spot rather than the full image extent (pass) — The frequency-separation lowFrequencyImage/CIGaussianBlur-over-full-extent path from KRMA-650/aed117d no longer exists. It was superseded by a pull/push membrane technique (commits 353d5a4..4a85eaf) that already confines destination, fill, mask, and the multi-level pyramid to spot-specific workBounds (RetouchRenderer.swift:45-61, 105-145). cd5bf9b adds a clarifying comment and a locking regression test on top of that pre-existing local-bounds behavior; it does not itself change the render graph.
- [x] Heal/Clone pixel output is unchanged for existing regression coverage (pass) — Ran RenderPipelineTests (serial CI lane): testManuallySourcedHealAndCloneProduceDifferentLocalFills, testHealMembraneExcludesPixelsInsideTheHole, testHealOverFlatExteriorDoesNotOvershootDestinationTone, testRetouchSpotChangesRenderedPixelsAndNeutralRetouchIsIdentity, testRetouchRecipeStaysInOrientedSourceSpaceAcrossGeometry all pass (47 tests, 2 skipped RAW-fixture tests, 0 failures).
- [x] A benchmark or reasoned argument shows per-spot cost no longer scales with total image resolution for a fixed spot radius (pass) — New test testSpotWorkBoundsStayConstantForTheSamePixelRadiusAtHigherResolution (RetouchModelTests) asserts workBounds size is identical at 4000x3000 and 8000x6000 for the same pixel radius, and the existing testSpotWorkBoundsStayLocalAtLargeSourceSizes bounds the window as a small fraction of a 6000x4000 image. Since every Gaussian blur/downsample/upsample/pull/push step in healedFill operates on images already cropped to workBounds (not image.extent), per-spot cost tracks the constant work-window size, not total resolution.
Checks run:
- swift build
- swift test --filter 'RetouchModelTests|RetouchWorkflowCoordinatorTests' (12 tests, 0 failures)
- swift test --filter 'RenderPipelineTests' (47 tests, 2 skipped, 0 failures)
- swift test --filter 'PackageSettingsTests' (4 tests, 0 failures, confirms Swift 6 mode invariants untouched)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUKCCNRDKH3VDKVB
Summary: Verified KRMA-657: the full-extent frequency-separation blur named in the issue no longer exists; it was superseded by the pull/push membrane rewrite, which already confines all per-spot work (blur, pyramid, mask) to workBounds. cd5bf9b adds a locking comment/test on top of that. All heal/clone/hole/flat-exterior regressions and the new fixed-radius scaling test pass; no code changes needed.
