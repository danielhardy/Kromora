---
id: KRMA-543
title: "KRMA-525 deletion lost: mask-overlay prototype regressed back onto main"
type: bug
status: ready
priority: urgent
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-22T19:54:12.242Z
updated: 2026-09-22T19:55:39.292Z
order: zzzh
board: product
---

## Objective

Re-apply the KRMA-525 mask-overlay-prototype deletion against the current codebase. The implementation commit that KRMA-525 claimed (`95b4b6dba6215ce214c962924674c680a505155d`, "Remove unused mask overlay prototype") is a dangling commit object not reachable from `main`/HEAD — it was lost, most likely during the history-recovery activity visible in `20cf4cb` (WIP: preserve recovered ticket implementations) and `a974928` (Reconcile recovered ticket lifecycle state), which restored several other tickets' work but not this one.

## Evidence

- `git merge-base --is-ancestor 95b4b6d HEAD` → not an ancestor; `git branch --all --contains 95b4b6d` → no branch contains it (dangling but not yet GC'd: `git cat-file -e 95b4b6d` succeeds).
- On current HEAD, all three files KRMA-525 claimed to delete are still present and unchanged from before the fix:
  - `Sources/KromoraKit/Views/MaskOverlayPrototype.swift`
  - `Sources/KromoraKit/Resources/MaskOverlay.metal`
  - `Tests/KromoraKitTests/MaskOverlayPerformanceBenchmark.swift`
- Stale references the original fix removed are still present: `scripts/ci-tests.sh` optional-lane filter still lists `MaskOverlayPerformanceBenchmark`; `scripts/build-metal-libraries.sh` still concatenates `MaskOverlay.metal`; `Tests/KromoraKitTests/CanvasNavigationTests.swift` still has `testMaskOverlayStateBypassesBroadModelPublisher` exercising the prototype; `Tests/KromoraKitTests/MetalKernelParityTests.swift` still hashes `MaskOverlay` as part of the precompiled metallib; `.context/CODE_QUALITY_CLEANUP_PLAN.md` still lists this as pending work.
- A direct `git cherry-pick 95b4b6d` is NOT safe: the codebase has materially diverged from `95b4b6d`'s parent since it was lost. In particular `Tests/KromoraKitTests/PreviewSurfaceTests.swift` has since been refactored — `PreviewSurfaceView.Coordinator.renderRetainedTextureForTesting` was renamed to `renderRetainedTexture`, and `PreviewSurface.resetPresentationCoreImageEvaluationCount()` / `PreviewSurface.presentationCoreImageEvaluationCount` were replaced by `RenderDiagnostics.reset()` / `RenderDiagnostics.snapshot.presentationCoreImageEvaluations`. A raw cherry-pick would conflict and/or silently reintroduce the old API names.

## Scope

Redo the KRMA-525 deletion against current `main`, re-validated against the current API surface (do not blindly replay the old diff):

- Delete `Sources/KromoraKit/Views/MaskOverlayPrototype.swift` and `Sources/KromoraKit/Resources/MaskOverlay.metal`.
- Delete `Tests/KromoraKitTests/MaskOverlayPerformanceBenchmark.swift`.
- Remove/rewrite the prototype-only test in `Tests/KromoraKitTests/CanvasNavigationTests.swift` (`testMaskOverlayStateBypassesBroadModelPublisher`) so shipping mask overlay behavior stays covered (KRMA-525's original fix pointed to `LocalMaskRenderingTests` as the real coverage — verify that's still true on current HEAD).
- Update `Sources/KromoraKit/Support/KromoraKitResourceBundle.swift`, `Sources/KromoraKit/Resources/PreviewSurface.metal` comments, `scripts/build-metal-libraries.sh`, `scripts/ci-tests.sh`, and `Tests/KromoraKitTests/MetalKernelParityTests.swift` to drop `MaskOverlay` from the precompiled-shader/metallib pipeline, then rebuild `KromoraPresentation.metallib`/`.sha256` with `PreviewSurface` only.
- Update `.context/CODE_QUALITY_CLEANUP_PLAN.md` to reflect completion.
- Re-run: `grep -rn MaskOverlayPrototype` (expect empty outside historical/generated artifacts), `swift build`, `swift build -c release`, resource freshness/parity checks, and the fast + serial test lanes.

## Acceptance criteria

- [ ] `95b4b6d`'s intent is re-applied on current `main` (not cherry-picked verbatim — reconciled against current `RenderDiagnostics`/`renderRetainedTexture` APIs).
- [ ] `grep -rn MaskOverlayPrototype` outside historical generated artifacts is empty.
- [ ] Shipping mask overlay behavior remains covered by a real test (confirm `LocalMaskRenderingTests` or equivalent).
- [ ] `swift build`, fast lane, serial lane, and resource/parity validation pass.
- [ ] KRMA-525 is re-verified after this lands.

## Dependencies and coordination

Blocks re-verification of KRMA-525, which has been returned to `review` pending this fix.
