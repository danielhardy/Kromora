---
id: KRMA-525
title: Delete the unused mask-overlay prototype
type: task
status: verification
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - dead-code
  - masks
created: 2026-09-21T20:33:06.322Z
updated: 2026-09-22T15:49:29.255Z
estimate: 3
order: a0
board: product
claim:
  actor: claude
  session: 01MUCUNPRASU9CPPP3
  claimed_at: 2026-09-22T15:49:29.254Z
  expires_at: 2026-09-22T16:49:29.254Z
  model: sonnet
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
