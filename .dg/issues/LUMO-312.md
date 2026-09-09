---
id: LUMO-312
title: Present preview via textured quad instead of CI render per drawable
type: task
status: ready
priority: medium
labels:
  - perf
  - phase:10
  - preview
  - metal
created: 2026-09-09T02:38:52.036Z
updated: 2026-09-09T04:04:30.320Z
estimate: 5
order: zqh
board: product
---

## Objective

Present preview frames with a textured-quad sampler (transform in the vertex shader) instead of re-running a Core Image graph per drawable — or, minimally, stop re-compositing the letterbox every frame.

## Context

**Why:** Every frame — including pan/zoom presentation-only redraws that need no new render — pays a second GPU kernel chain: transform + crop + `composited(over:)` letterbox via `CIContext.render(to: drawable.texture)`. Saves 1-3ms off `presentationEncodingMS` and smooths pinch/pan.

**Current code:**
- `Sources/LumoKit/Views/PreviewSurface.swift` — `PreviewSurfaceView.Coordinator.draw()`, `presentationImage()` (fit transform + crop + letterbox composite), `context.render(to: drawable.texture)`, `PreviewFrameIdentity(sourceToken/documentHash/space)`, `retrySkippedDraw`, `presentationEncodingMS` telemetry.
- `Sources/LumoKit/ViewModels/AppViewModel.swift` — `publishPreview()` → `previewSurface.present(...)` with `detailIdentity`/`detailFactor`; MTKView is texture-backed with `lastValidImage` retention.
- `PreviewView` background color (`LumoTheme.windowBackground`) — the letterbox color to reproduce exactly.

## Scope / Steps

1. Preferred: textured-quad presentation — upload/retain the completed preview texture once per render revision; per-drawable work becomes viewport transform + clear-color letterbox (no CI evaluation). Invalidate the retained texture on `revision`/`detailIdentity` change.
2. Minimal fallback (if quad is too invasive): cache the letterbox background composition so redraws without a new render skip CI entirely.
3. Preserve: aspect-fit geometry, `workingSpace`→display conversion (exactly once), `PreviewFrameIdentity` dedup, `onPresented` confirmation callback (histogram/comparison gating depends on it), skipped-drawable handling.
4. Keep `device`/`colorPixelFormat` fallback paths (non-GPU seam) working.

## Acceptance criteria

- [ ] `NoCIEvalOnRepaintTest`: pan/zoom presenting with no new render performs zero Core Image evaluations (assert evaluation counter == 0).
- [ ] `GeometryGoldenTest`: ultrawide/square/portrait fixtures match the CPU-composited reference within the test-recorded pixel threshold, and sampled letterbox-border pixels equal `LumoTheme.windowBackground`.
- [ ] `ConfirmationOnceTest`: `didPresentVisibleFrame` fires exactly once per presented settled frame (assert callback log count == presented count).
- [ ] `DisplayChangeTest`: simulated display/color-space change notification re-presents the latest revision with a single confirmation and no duplicate render (assert present/confirm/render counters over a simulated notification).
## Verification

- `swift build` clean (zero diagnostics).
- New/updated XCTest(s) named above green.
- `scripts/ci-tests.sh fast` + `serial` (AppKit/UI lane) green.
- Benchmark (informational, never gating): `presentationEncodingMS` on pan/zoom redraws, Release build, same machine/dataset, before/after in the agent log (use the LUMO-057 harness if it exists).
- No screenshots, no manual interaction: done = all automated checks above pass.
## Out of scope

- Skipped-drawable backoff policy (separate ticket; keep behavior, just preserve the hook).
- Changing the render graph itself.

## Constraints

- macOS 14 minimum; Metal + CoreImage + AppKit only.
- Swift 6: `deinit` is nonisolated — teardown that needs the main actor belongs in an explicit `stop()` (see `KeyMonitor.stop()` precedent). No opt-outs.
