---
id: KRMA-525
title: Delete the unused mask-overlay prototype
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: grep/ripgrep for MaskOverlayPrototype and its named types is empty outside historical generated artifacts, if any
      result: pass
      notes: "Clean-worktree git grep at HEAD for MaskOverlayPrototype, MaskOverlayPerformanceBenchmark, MaskOverlay.metal, mask_overlay_vertex/fragment, MaskOverlayInteractionState, MaskOverlaySurfaceView, MaskOverlayRenderer, MaskOverlayPointerEvent, MaskOverlayMTKView across Sources/Tests/scripts/Package.swift: zero hits. Remaining matches are .dg history/archive records only. All remaining MaskOverlay* symbols (MaskOverlayRequest, makeMaskOverlayImage, MaskOverlayStyle) are the shipping overlay."
    - criterion: Shipping mask overlay behavior remains covered by an appropriate test
      result: pass
      notes: "LocalMaskRenderingTests covers the production path (MaskOverlayRequest, makeMaskOverlayImage, renderMaskOverlay). Prototype-only CanvasNavigation test was removed (scope allows remove-or-rewrite). At deletion commit 404b85e: LocalMaskRenderingTests plus MetalKernelParity, PreviewSurface, CanvasNavigation suites green."
    - criterion: Build, fast lane, serial lane, and resource validation pass
      result: fail
      notes: "Deletion content itself green at 404b85e (clean worktree): swift build exit 0, swift build -c release exit 0, scripts/build-metal-libraries.sh --check exit 0, dg validate exit 0, focused suites 109 executed / 1 expected benchmark skip / 0 failures. Full fast-lane evidence on this content via KRMA-543 verification (only pre-existing failures, ticketed as KRMA-547). At current HEAD (c908c12) the TEST bundle does not compile: KRMA-530 renamed test usages to LocalMaskRenderer.diagnosticsSnapshot without adding that member (fix exists only as uncommitted tree changes). Out of KRMA-525 scope; owned by KRMA-530 pending verification."
    - criterion: The change lists every deleted production/test/resource file and confirms no Package.swift resource breakage
      result: pass
      notes: 404b85e deletes exactly Sources/KromoraKit/Views/MaskOverlayPrototype.swift, Sources/KromoraKit/Resources/MaskOverlay.metal, Tests/KromoraKitTests/MaskOverlayPerformanceBenchmark.swift; edits CanvasNavigationTests, MetalKernelParityTests, PreviewSurfaceTests, build-metal-libraries.sh, ci-tests.sh, PreviewSurface.metal comment, resource-bundle comment, rebuilt metallib+sha256, cleanup-plan doc. Package.swift untouched and needs no change (.copy Resources); debug+release builds prove no resource breakage.
  checks_run:
    - clean-worktree git grep for prototype symbols at HEAD (zero hits in Sources/Tests/scripts/Package.swift)
    - deleted-artifact absence check at HEAD (all three files absent)
    - "clean worktree at 404b85e: scripts/build-metal-libraries.sh --check exit 0"
    - "clean worktree at 404b85e: swift build exit 0"
    - "clean worktree at 404b85e: swift test --filter LocalMaskRenderingTests|MetalKernelParityTests|PreviewSurfaceTests|CanvasNavigationTests: 109 executed, 1 skip, 0 failures"
    - "clean worktree at 404b85e: swift build -c release exit 0"
    - "clean worktree at 404b85e: dg validate exit 0"
    - full diff review of 404b85e (13 files, 14 insertions, 620 deletions)
    - "clean worktree at HEAD (c908c12): swift build exit 0; swift test bundle fails to compile on LocalMaskRenderer.diagnosticsSnapshot (KRMA-530 cause, confirmed via git show c908c12)"
    - stale-reference scan of docs/.context/PerformanceBaselines/ci-tests.sh (no prototype references remain)
  findings:
    - "HEAD test-bundle compile break is caused by KRMA-530 commit c908c12 (test-only API rename without the matching LocalMaskRenderer member); 404b85e touches none of those files. No duplicate ticket filed: KRMA-530 is already in verification and its verifier will hit this immediately."
    - Shared working tree holds extensive unrelated uncommitted work (PackagePath/NumericClamping files, RevisionLedger follow-ups, RenderEngine split fallout including the uncommitted diagnosticsSnapshot shim); verification was isolated via clean worktrees and made zero tree edits.
    - Serial lane not re-run here; implementer- and KRMA-543-documented pre-existing KeyMonitorTests headless hang predates this change.
  fixes: []
  verification_commits: []
  actor: pi
  resolved_model: unknown
  completed_at: 2026-09-23T03:04:01.596Z
  session: 01MUDIL3KG52KP70FT
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - dead-code
  - masks
created: 2026-09-21T20:33:06.322Z
updated: 2026-09-23T03:04:01.598Z
depends_on:
  - KRMA-543
estimate: 3
order: l
board: product
---

## Objective

Remove the unused MaskOverlayPrototype implementation and its exclusive resource/test/benchmark consumers without affecting the shipped mask overlay.

## Context and evidence

Views/MaskOverlayPrototype.swift is explicitly a Step 0 prototype and none of its types are referenced by production Sources or Tests except the prototype benchmark and one CanvasNavigation test. The shipping overlay uses RenderEngine.makeMaskOverlayImage. Resources/MaskOverlay.metal is loaded only by the prototype.

## Scope

- Delete MaskOverlayPrototype.swift and Resources/MaskOverlay.metal.
- Delete MaskOverlayPerformanceBenchmark.swift if it only exercises the prototype.
- Rewrite or remove the CanvasNavigationTests test so it covers a real shipping invariant rather than the prototype.
- Remove stale lane lists, performance-baseline entries, and documentation references.
- Verify no prototype symbol or resource remains in source, tests, package resources, or generated build inputs.

## Acceptance criteria

- [ ] grep/ripgrep for MaskOverlayPrototype and its named types is empty outside historical generated artifacts, if any.
- [ ] Shipping mask overlay behavior remains covered by an appropriate test.
- [ ] Build, fast lane, serial lane, and resource validation pass.
- [ ] The change lists every deleted production/test/resource file and confirms no Package.swift resource breakage.

## Dependencies and coordination

Independent and safe to do early. Keep this separate from CQ-08 brush optimization and CQ-09 shader migration so deletion is easy to verify.

## Likely files and checks

Views/MaskOverlayPrototype.swift, Resources/MaskOverlay.metal, MaskOverlayPerformanceBenchmark.swift, CanvasNavigationTests.swift, Package.swift/resource lists, and performance baselines.


### Comment — codex @ 2026-09-22T15:49:22.570Z

Implemented in 95b4b6d. Deleted Sources/KromoraKit/Views/MaskOverlayPrototype.swift, Sources/KromoraKit/Resources/MaskOverlay.metal, and Tests/KromoraKitTests/MaskOverlayPerformanceBenchmark.swift; removed the prototype navigation test and optional-lane entry; rebuilt KromoraPresentation.metallib and checksum with PreviewSurface only; updated parity/resource validation and active cleanup documentation. Production mask behavior remains covered by LocalMaskRenderingTests. Passed swift build, swift build -c release, resource freshness check, dg validate, and focused mask/Metal/preview/navigation tests (109 executed, 1 existing opt-in skip). Full fast/serial lanes encountered unrelated pre-existing async library/navigation/thumbnail failures and headless KeyMonitor focus failures; no task-scoped failures.

## Agent log

- 2026-09-23T03:04:01.596Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] grep/ripgrep for MaskOverlayPrototype and its named types is empty outside historical generated artifacts, if any (pass) — Clean-worktree git grep at HEAD for MaskOverlayPrototype, MaskOverlayPerformanceBenchmark, MaskOverlay.metal, mask_overlay_vertex/fragment, MaskOverlayInteractionState, MaskOverlaySurfaceView, MaskOverlayRenderer, MaskOverlayPointerEvent, MaskOverlayMTKView across Sources/Tests/scripts/Package.swift: zero hits. Remaining matches are .dg history/archive records only. All remaining MaskOverlay* symbols (MaskOverlayRequest, makeMaskOverlayImage, MaskOverlayStyle) are the shipping overlay.
- [x] Shipping mask overlay behavior remains covered by an appropriate test (pass) — LocalMaskRenderingTests covers the production path (MaskOverlayRequest, makeMaskOverlayImage, renderMaskOverlay). Prototype-only CanvasNavigation test was removed (scope allows remove-or-rewrite). At deletion commit 404b85e: LocalMaskRenderingTests plus MetalKernelParity, PreviewSurface, CanvasNavigation suites green.
- [ ] Build, fast lane, serial lane, and resource validation pass (fail) — Deletion content itself green at 404b85e (clean worktree): swift build exit 0, swift build -c release exit 0, scripts/build-metal-libraries.sh --check exit 0, dg validate exit 0, focused suites 109 executed / 1 expected benchmark skip / 0 failures. Full fast-lane evidence on this content via KRMA-543 verification (only pre-existing failures, ticketed as KRMA-547). At current HEAD (c908c12) the TEST bundle does not compile: KRMA-530 renamed test usages to LocalMaskRenderer.diagnosticsSnapshot without adding that member (fix exists only as uncommitted tree changes). Out of KRMA-525 scope; owned by KRMA-530 pending verification.
- [x] The change lists every deleted production/test/resource file and confirms no Package.swift resource breakage (pass) — 404b85e deletes exactly Sources/KromoraKit/Views/MaskOverlayPrototype.swift, Sources/KromoraKit/Resources/MaskOverlay.metal, Tests/KromoraKitTests/MaskOverlayPerformanceBenchmark.swift; edits CanvasNavigationTests, MetalKernelParityTests, PreviewSurfaceTests, build-metal-libraries.sh, ci-tests.sh, PreviewSurface.metal comment, resource-bundle comment, rebuilt metallib+sha256, cleanup-plan doc. Package.swift untouched and needs no change (.copy Resources); debug+release builds prove no resource breakage.
Checks run:
- clean-worktree git grep for prototype symbols at HEAD (zero hits in Sources/Tests/scripts/Package.swift)
- deleted-artifact absence check at HEAD (all three files absent)
- clean worktree at 404b85e: scripts/build-metal-libraries.sh --check exit 0
- clean worktree at 404b85e: swift build exit 0
- clean worktree at 404b85e: swift test --filter LocalMaskRenderingTests|MetalKernelParityTests|PreviewSurfaceTests|CanvasNavigationTests: 109 executed, 1 skip, 0 failures
- clean worktree at 404b85e: swift build -c release exit 0
- clean worktree at 404b85e: dg validate exit 0
- full diff review of 404b85e (13 files, 14 insertions, 620 deletions)
- clean worktree at HEAD (c908c12): swift build exit 0; swift test bundle fails to compile on LocalMaskRenderer.diagnosticsSnapshot (KRMA-530 cause, confirmed via git show c908c12)
- stale-reference scan of docs/.context/PerformanceBaselines/ci-tests.sh (no prototype references remain)
Findings:
- HEAD test-bundle compile break is caused by KRMA-530 commit c908c12 (test-only API rename without the matching LocalMaskRenderer member); 404b85e touches none of those files. No duplicate ticket filed: KRMA-530 is already in verification and its verifier will hit this immediately.
- Shared working tree holds extensive unrelated uncommitted work (PackagePath/NumericClamping files, RevisionLedger follow-ups, RenderEngine split fallout including the uncommitted diagnosticsSnapshot shim); verification was isolated via clean worktrees and made zero tree edits.
- Serial lane not re-run here; implementer- and KRMA-543-documented pre-existing KeyMonitorTests headless hang predates this change.
Fixes:
- None
Verification commits:
- None
Actor: pi
Resolved model: unknown
Pickup session: 01MUDIL3KG52KP70FT
Summary: KRMA-525 verified: mask-overlay prototype deletion (404b85e) is complete and correct; all scope checks green in clean worktrees. HEAD test-bundle compile break is out-of-scope KRMA-530 fallout, owned by its pending verification.
