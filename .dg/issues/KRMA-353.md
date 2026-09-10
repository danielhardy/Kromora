---
id: KRMA-353
title: Rotate local-adjustment mask geometry along with image rotation
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Determine whether each LocalAdjustmentLayer mask kind's geometry is expressed in oriented-image coordinates or is otherwise rotation-invariant
      result: pass
    - criterion: If not rotation-invariant, remap mask geometry on rotate/reset-rotation the same way CropAdjustments.rotated does for crop
      result: pass
    - criterion: "Add regression coverage: commit a mask, rotate, and assert the mask still selects the same visual content"
      result: pass
  checks_run:
    - swift build
    - swift test --filter ImageRotationTests
    - scripts/ci-tests.sh fast (832 tests, 0 failures)
    - scripts/ci-tests.sh serial (328 tests, 0 failures)
    - empirical grid-coverage probe (RadialGradientMaskMath.insideCoverage before/after rotation on a 96x64 source) before and after the fix
  findings:
    - MaskSource.rotated's radial-gradient case swapped horizontalRadius/verticalRadius directly instead of rescaling by aspect ratio, which only reproduces the same physical ellipse when the oriented source is square (high severity, correctness) — fixed in this verification pass, see fixes[].
  fixes:
    - Threaded orientedSourceSize (pre-rotation oriented pixel size) through MaskSource.rotated and LocalAdjustmentLayer.rotated; radial radii are now rescaled by the aspect ratio (physical pixel radii preserved and renormalized against the swapped width/height) instead of swapped as raw fractions.
    - Updated AppViewModel.rotateImage/resetRotation call sites to pass the current sourceSize captured before the document mutation.
    - Updated the existing geometry unit test to use a non-square oriented size (96x64, matching the fixture used elsewhere) so the aspect-ratio bug is not hidden by an implicit square assumption, and added a new coverage-preservation regression test sampling RadialGradientMaskMath.insideCoverage across a grid of points before/after rotation.
  verification_commits:
    - b3181a8735b471a3c79389be7809c7caa0e04332
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-10T20:02:07.913Z
  session: 01MTVY0RIKZTU7N0R3
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-10T14:49:59.785Z
updated: 2026-09-10T20:02:07.915Z
parent: KRMA-332
order: a0
board: product
commits:
  - b3181a8735b471a3c79389be7809c7caa0e04332
---

## Objective

Rotate local-adjustment mask geometry along with image rotation, matching the crop-rotation fix
made during KRMA-332 verification.

## Context

KRMA-332 (non-destructive image rotation) added a quarter-turn `ImageRotation` to `EditDocument`
and applied it consistently to render/export geometry. Verification found and fixed one gap:
a **committed crop**'s `normalizedRect` — defined in the oriented source's coordinate space — was
not remapped when rotation changed, so it silently framed the wrong region after a rotate. That
was fixed by `CropAdjustments.rotated(byClockwiseQuarterTurns:)`, applied in
`AppViewModel.rotateImage`/`resetRotation` (see KRMA-332 commit history).

The same class of problem likely applies to `EditDocument.localAdjustments`
(`LocalAdjustmentLayer` masks — gradient/radial/region geometry, etc.): if their geometry is
anchored to the oriented-image coordinate space the same way crop is, rotating the image will
leave mask shapes pointing at the wrong region without any user-visible feedback. This was out of
scope for a localized verification fix (the local-adjustment data model is more complex than a
single rect, and remapping each mask kind correctly needs its own design/test pass), so it's
filed here as a follow-up rather than folded into KRMA-332.

## Acceptance criteria

- [ ] Determine whether each `LocalAdjustmentLayer` mask kind's geometry is expressed in
      oriented-image coordinates (same convention as crop) or is otherwise rotation-invariant.
- [ ] If not rotation-invariant, remap mask geometry on rotate/reset-rotation the same way
      `CropAdjustments.rotated(byClockwiseQuarterTurns:)` does for crop.
- [ ] Add regression coverage: commit a mask, rotate, and assert the mask still selects the same
      visual content (mirroring `ImageRotationTests.testRotatingAnImageWithACommittedCropKeepsTheSameFramedContent`).

## Implementation notes

Start from `Sources/KromoraKit/Models/CropAdjustments.swift`'s new `rotated(byClockwiseQuarterTurns:)`
for the coordinate-transform pattern, and `AppViewModel.rotateImage`/`resetRotation` for where to
apply it. Local adjustment geometry lives in `LocalAdjustmentLayer` — check each mask kind's shape
representation before assuming the crop-rect formula applies directly.

### Comment — codex @ 2026-09-10T19:51:25.359Z

Implemented in commit 4a38acd. Local mask geometry now follows quarter-turn image rotations: brush sample points, linear gradient endpoints, and radial center/axes/orientation are remapped in oriented upper-left coordinates; semantic target recipes remain unchanged. Rotate and reset apply the same transforms as crop in one undoable document update. Added ImageRotationTests coverage for per-kind remapping, inverse restoration, and committed-mask rotate/reset behavior. Verification: swift test — 1,204 executed, 47 skipped, 0 failures.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-10T20:02:07.913Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Determine whether each LocalAdjustmentLayer mask kind's geometry is expressed in oriented-image coordinates or is otherwise rotation-invariant (pass)
- [x] If not rotation-invariant, remap mask geometry on rotate/reset-rotation the same way CropAdjustments.rotated does for crop (pass)
- [x] Add regression coverage: commit a mask, rotate, and assert the mask still selects the same visual content (pass)
Checks run:
- swift build
- swift test --filter ImageRotationTests
- scripts/ci-tests.sh fast (832 tests, 0 failures)
- scripts/ci-tests.sh serial (328 tests, 0 failures)
- empirical grid-coverage probe (RadialGradientMaskMath.insideCoverage before/after rotation on a 96x64 source) before and after the fix
Findings:
- MaskSource.rotated's radial-gradient case swapped horizontalRadius/verticalRadius directly instead of rescaling by aspect ratio, which only reproduces the same physical ellipse when the oriented source is square (high severity, correctness) — fixed in this verification pass, see fixes[].
Fixes:
- Threaded orientedSourceSize (pre-rotation oriented pixel size) through MaskSource.rotated and LocalAdjustmentLayer.rotated; radial radii are now rescaled by the aspect ratio (physical pixel radii preserved and renormalized against the swapped width/height) instead of swapped as raw fractions.
- Updated AppViewModel.rotateImage/resetRotation call sites to pass the current sourceSize captured before the document mutation.
- Updated the existing geometry unit test to use a non-square oriented size (96x64, matching the fixture used elsewhere) so the aspect-ratio bug is not hidden by an implicit square assumption, and added a new coverage-preservation regression test sampling RadialGradientMaskMath.insideCoverage across a grid of points before/after rotation.
Verification commits:
- b3181a8735b471a3c79389be7809c7caa0e04332
Actor: claude
Resolved model: sonnet
Pickup session: 01MTVY0RIKZTU7N0R3
Summary: Counterpoint verification of 4a38acd found a real correctness bug: MaskSource.rotated's radial-gradient case swapped horizontalRadius/verticalRadius instead of rescaling by aspect ratio, only correct on square oriented sources. Empirically confirmed (~33% of sampled points mismatched coverage on a 96x64 source). Fixed by threading orientedSourceSize through MaskSource.rotated/LocalAdjustmentLayer.rotated and the two AppViewModel rotate/reset call sites, updated the existing geometry test to a non-square size, and added a coverage-preservation regression test. Brush/linear point geometry and the crop-rotation path were re-derived independently and are correct as-is. Checks: swift build, swift test --filter ImageRotationTests, ci-tests.sh fast (832) and serial (328), all pass.
