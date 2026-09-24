---
id: KRMA-559
title: Stop the preview canvas from measuring MTKView through Auto Layout
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: PreviewSurfaceView.sizeThatFits returns the proposed canvas size for a finite proposal and a small size for an unspecified proposal, and it never returns nil.
      result: pass
      notes: PreviewSurfaceView.sizeThatFits (PreviewSurface.swift ~719) always returns Self.layoutSize(for:), which substitutes a 1pt fallback per non-finite/nil dimension via proposedDimension; the function's return type is CGSize? but the implementation never produces a nil case.
    - criterion: "Laying out an NSHostingView of PreviewSurfaceView inside the same .frame(maxWidth: .infinity, maxHeight: .infinity) plus fixed-size frame used by singleView gives the MTKView that fixed size."
      result: pass
      notes: testPreviewSurfaceLayoutUsesProposedSizeWithoutIntrinsicMeasurement hosts PreviewSurfaceView in the exact nested-frame shape from PreviewView.singleView (maxWidth/maxHeight .infinity, then fixed 320x240) and asserts the resulting MTKView frame is 320x240.
    - criterion: A regression test covers that hosting layout (single-view frame nest, and a fixed-height host such as the analysis overlay). Existing PreviewSurfaceTests still pass.
      result: pass
      notes: "Same test also hosts PreviewSurfaceView.frame(height: 130) matching AnalysisDebugPanel's fixed-height overlay. Full PreviewSurfaceTests suite: 40/40 passed."
    - criterion: Pan, zoom, double-click, crop hit-testing, and drawable-size preview scheduling are unchanged. sizeThatFits does not call updatePreviewBackingSize.
      result: pass
      notes: Diff is additive-only (15 new lines in PreviewSurface.swift); no existing hit-testing, gesture, or drawable-size code paths were touched. sizeThatFits only computes a CGSize from the proposal and does not reference surface, AppViewModel, or updatePreviewBackingSize.
    - criterion: If the inspector is still hot, NeutralOriginSlider gets the same kind of sizeThatFits and a test that a row lays out without depending on NSSlider's intrinsic width. If a probe shows slider measurement is cheap, say so in the handoff and leave the slider alone.
      result: not_applicable
      notes: The captured 13/13-sample hang stack names only PreviewMTKView/AppKitPlatformViewHost via the nested canvas frames; NeutralOriginSlider does not appear in that stack. No follow-up sample was taken (no WindowServer access in this environment) to confirm or rule out the slider as a second leaf, so leaving it untouched matches the issue's conditional instruction, though a human should capture a follow-up sample after this fix lands to close this out definitively.
    - criterion: "Manual check: swift run, open a photo, resize the window, toggle side-by-side, enter and leave crop. The window stays responsive."
      result: not_applicable
      notes: Not performable in this non-interactive environment (no WindowServer to drive/observe the AppKit window). swift build succeeds cleanly and the full fast test lane passes; a human should still run the manual resize/side-by-side/crop smoke before considering the beachball fully closed in practice.
  checks_run:
    - swift test --filter PreviewSurfaceTests (40/40 passed)
    - scripts/ci-tests.sh fast (1179/1179 passed, exit 0)
    - swift build (clean, 0 errors)
    - git diff --check (clean)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-23T23:21:46.387Z
  session: 01MUEQ3REQONMYJRM3
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - performance
  - preview
  - stability
created: 2026-09-23T22:56:20.863Z
updated: 2026-09-23T23:21:46.389Z
order: zx
board: product
context:
  files:
    - Sources/KromoraKit/Views/PreviewSurface.swift
    - Sources/KromoraKit/Views/PreviewView.swift
    - Sources/KromoraKit/Views/MaskingPanel.swift
    - Sources/KromoraKit/Views/AnalysisDebugPanel.swift
    - Sources/KromoraKit/Views/NeutralOriginSlider.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
    - Tests/KromoraKitTests/PreviewSurfaceTests.swift
  docs:
    - docs/APP_ARCHITECTURE.md
  issues:
    - KRMA-557
    - KRMA-482
    - KRMA-483
  commands:
    - swift test --filter PreviewSurfaceTests
    - scripts/ci-tests.sh fast
    - swift run
---

## Objective

Stop the editor canvas from hanging the main thread while SwiftUI measures the preview `MTKView`. A sampled beachball spent the entire window inside one SwiftUI layout transaction, asking AppKit for the hosted view's intrinsic size and solving temporary Auto Layout constraints. The canvas is already sized by its parent frames; that measurement is unnecessary.

## Hang sample

Captured 2026-09-23 16:39:49–16:40:04 −0600 (incident `F114DF31-FC54-48D4-9078-7CA7EE9E5A40`). macOS 27.0 (26A428), arm64e, Mac16,11. Process `Kromora` PID 10428, parent `zsh`, responsible process Cursor, about 79 seconds after fork. Path was a local ad-hoc binary (`Codesigning ID: Kromora-5555…`), consistent with `swift run` rather than a signed sandboxed build. The pasted report contained only the heaviest main-thread stack.

- Duration 15.16s. The process was already unresponsive for 14s before sampling; the sample itself covers the last 1.30s (13 samples, 100ms).
- Total CPU time during the hang: 11.883s. This is compute, not a wait. The leaf is `objc_msgSend` inside `addConstraints`, not `mach_msg` or a lock.
- Thermal pressure was 0. Fan speed and battery advisory do not explain the stack.

Every sample (13/13) is on the main thread in one transaction:

`NSApplication` run loop observer → `NSRunLoop.flushObservers` → `NSHostingView.beginTransaction` → `ViewGraphRootValueUpdater` → `GraphHost.flushTransactions` → `AG::Subgraph::update` → `RootGeometry.value.getter` → nested `_FlexFrameLayout.sizeThatFits` → `PlatformViewLayoutEngine.sizeThatFits` → `ViewLeafView.layoutTraits` → `AppKitPlatformViewHost.intrinsicLayoutTraits` → `-[NSView measureMin:max:ideal:stretchingPriority:]` → `NSISEngine` `withBehaviors:performModifications:` → `addConstraints`.

Sample counts along that stack: 12 in `flushTransactions`, 10 in the AttributeGraph update, 7 in `RootGeometry` / `_FlexFrameLayout.sizeThatFits`, 4 in `intrinsicLayoutTraits` / `measureMin:max:ideal:`, 2 in `addConstraints`. `_FlexFrameLayout` appears twice, then a `<deduplicated_symbol>` of the same layout, then the platform view. `_FlexFrameLayout` is SwiftUI's `.frame()`. Each frame measures its child more than once, so nested frames multiply Auto Layout solves of the same leaf.

Nothing in the heaviest stack is `RenderEngine`, Core Image, Metal command-buffer submission, image decode, or package I/O. Do not treat this as a preview-render stall.

## Why this matches the preview canvas

`PreviewSurfaceView` (`Sources/KromoraKit/Views/PreviewSurface.swift`) is an `NSViewRepresentable` whose `makeNSView` returns `PreviewMTKView` (`MTKView`, around line 1440). `MTKView` has no useful intrinsic content size. SwiftUI's default `NSViewRepresentable` sizing returns nil from `sizeThatFits`, which sends layout through `AppKitPlatformViewHost.intrinsicLayoutTraits` and AppKit's `measureMin:max:ideal:` constraint solve. There is no `sizeThatFits` implementation in the repo today.

The single-image canvas wraps that representable in three flexible frames, which is the sampled ancestor chain (outer to inner):

- `PreviewView.singleView` applies `.frame(width: geometry.size.width, height: geometry.size.height)` outside `.frame(maxWidth: .infinity, maxHeight: .infinity)` (`Sources/KromoraKit/Views/PreviewView.swift`, about lines 202–206).
- `canvasSurface` applies another `.frame(maxWidth: .infinity, maxHeight: .infinity)` directly to `PreviewSurfaceView` (about line 259). The third `_FlexFrameLayout` is the deduplicated symbol in the sample.
- `sideBySideView` uses the same `canvasSurface` inside `panelView`'s `.frame(width:)`.

Other `PreviewSurfaceView` hosts take the same representable path and should pick up one fix: `MaskOverlayView` in `MaskingPanel.swift`, and the mask overlay in `AnalysisDebugPanel.swift` (fixed `.frame(height: 130)`).

`updatePreviewBackingSize` (`AppViewModel.swift`, about line 4343) writes a private `previewBackingSize` that views do not read. Drawable-size callbacks in `PreviewSurface.swift` (`draw(in:)` and `mtkView(_:drawableSizeWillChange:)`) are not on this stack. Leave that reporting on the MTKView delegate. `sizeThatFits` must stay a pure size answer and must not publish preview state or call `setNeedsDisplay`.

## Other AppKit leaves (confirm, do not assume)

These also host `NSView`s, but their layout ancestors are not the nested canvas frames in the sample:

- `NeutralOriginSlider` (`NeutralOriginSlider.swift`) wraps `NSSlider`. The comment near `makeNSView` already notes that `NSSlider` has no intrinsic width. Inspectors instantiate many of them (`LightInspectorView`, `DevelopInspectorView`, `ColorInspectorView`, `EffectsInspectorView`, `CropInspectorView`, `LookInspectorView`, `MaskingWorkspace`, `TemperatureSlider`). They are a plausible second leaf if a follow-up sample still sits in `measureMin:max:ideal:` after the preview fix. Only then add `sizeThatFits` (proposed width, fixed control height). Do not restyle or replace slider drawing, tracking, or accessibility in this ticket.
- `MaskPointerSurface` and `KeyMonitorAnchor` are plain `NSView`s. Leave them unless a new sample names them.

## Implementation

`NSViewRepresentable.sizeThatFits(_:nsView:context:) -> CGSize?` is available on the macOS 14 deployment target. Implement it on `PreviewSurfaceView`.

- Return nil and SwiftUI keeps calling `intrinsicLayoutTraits`. Always return a concrete size.
- When the proposal has a finite width and height, return that size. The parent frames already decided the canvas.
- When a dimension is unspecified, substitute a small fallback (1×1, or `ProposedViewSize.replacingUnspecifiedDimensions(by:)` with a tiny size). An unspecified proposal is the ideal-size query from `_FlexFrameLayout`. A large fallback recreates expensive measurement.
- Do not do the work inside `PreviewMTKView.intrinsicContentSize`. AppKit still enters `measureMin:max:ideal:` to produce `noIntrinsicMetric`. The skip has to happen in SwiftUI's `sizeThatFits`.
- Do not add Auto Layout constraints to the `MTKView`.
- Preserve hit testing (`ignoresHits`), pan, magnify, scroll zoom, double-click, the paused-`MTKView` display retry, crop view-space rotation, and comparison / mask overlays.
- Change `PreviewView` frame modifiers only if `sizeThatFits` alone still leaves a sample in `measureMin:max:ideal:` for this leaf, and record why.

## Acceptance criteria

- [ ] `PreviewSurfaceView.sizeThatFits` returns the proposed canvas size for a finite proposal and a small size for an unspecified proposal, and it never returns nil.
- [ ] Laying out an `NSHostingView` of `PreviewSurfaceView` inside the same `.frame(maxWidth: .infinity, maxHeight: .infinity)` plus fixed-size frame used by `singleView` gives the `MTKView` that fixed size.
- [ ] A regression test covers that hosting layout (single-view frame nest, and a fixed-height host such as the analysis overlay). Existing `PreviewSurfaceTests` still pass.
- [ ] Pan, zoom, double-click, crop hit-testing, and drawable-size preview scheduling are unchanged. `sizeThatFits` does not call `updatePreviewBackingSize`.
- [ ] If the inspector is still hot, `NeutralOriginSlider` gets the same kind of `sizeThatFits` and a test that a row lays out without depending on `NSSlider`'s intrinsic width. If a probe shows slider measurement is cheap, say so in the handoff and leave the slider alone.
- [ ] Manual check: `swift run`, open a photo, resize the window, toggle side-by-side, enter and leave crop. The window stays responsive. If it beaches, the new main-thread sample must not still be in `AppKitPlatformViewHost.intrinsicLayoutTraits` for the preview.

## Checks

- `swift test --filter PreviewSurfaceTests` plus the new layout test.
- `scripts/ci-tests.sh fast` if the change touches shared view or view-model code beyond `sizeThatFits`.
- Manual `swift run` smoke above. A full hang sample is enough evidence if the UI check is inconclusive; do not require the opt-in RAW fixture lane.

## Context

- Files: `Sources/KromoraKit/Views/PreviewSurface.swift` (`PreviewSurfaceView`, `PreviewMTKView`), `Sources/KromoraKit/Views/PreviewView.swift` (`singleView`, `canvasSurface`, `panelView`), `Sources/KromoraKit/Views/MaskingPanel.swift`, `Sources/KromoraKit/Views/AnalysisDebugPanel.swift`, `Sources/KromoraKit/Views/NeutralOriginSlider.swift`, `Sources/KromoraKit/ViewModels/AppViewModel.swift` (`updatePreviewBackingSize`), `Tests/KromoraKitTests/PreviewSurfaceTests.swift`.
- Docs: `docs/APP_ARCHITECTURE.md` only if ownership of the preview surface needs a sentence. No packaging or storage-policy change.
- Issues: KRMA-557 is a different beachball (portable-library index open/rebuild on launch). This sample is ~79s after fork and is entirely SwiftUI layout of an AppKit platform view. Do not fold index work into this ticket. KRMA-482 / KRMA-483 own pan and preview hit-testing; do not reopen them.
- Commands: `swift test --filter PreviewSurfaceTests`, `scripts/ci-tests.sh fast`, `swift run`.

## Out of scope

Render scheduling, export, LUT derivation, library startup (KRMA-557), and rewriting inspector controls beyond a confirmed `NeutralOriginSlider` sizing fix. The working tree may already contain unrelated edits; leave those untouched.


### Comment — codex @ 2026-09-23T23:17:22.499Z

Implemented and committed as e940a8b. PreviewSurfaceView.sizeThatFits now returns the finite SwiftUI proposal directly and uses a 1×1 fallback for unspecified/non-finite dimensions, avoiding AppKit intrinsic-size measurement for MTKView. Added proposal checks and NSHostingView regression coverage for the nested single-canvas frames and fixed-height overlay. Verified: swift test --filter PreviewSurfaceTests (40 passed), swift run build/launch, git diff --check. The captured stack identifies PreviewMTKView as the hosted leaf; no slider sizing change was warranted. I could not interact with or visually inspect the running app to complete the manual resize/side-by-side/crop check.

## Agent log

- 2026-09-23T23:21:46.387Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] PreviewSurfaceView.sizeThatFits returns the proposed canvas size for a finite proposal and a small size for an unspecified proposal, and it never returns nil. (pass) — PreviewSurfaceView.sizeThatFits (PreviewSurface.swift ~719) always returns Self.layoutSize(for:), which substitutes a 1pt fallback per non-finite/nil dimension via proposedDimension; the function's return type is CGSize? but the implementation never produces a nil case.
- [x] Laying out an NSHostingView of PreviewSurfaceView inside the same .frame(maxWidth: .infinity, maxHeight: .infinity) plus fixed-size frame used by singleView gives the MTKView that fixed size. (pass) — testPreviewSurfaceLayoutUsesProposedSizeWithoutIntrinsicMeasurement hosts PreviewSurfaceView in the exact nested-frame shape from PreviewView.singleView (maxWidth/maxHeight .infinity, then fixed 320x240) and asserts the resulting MTKView frame is 320x240.
- [x] A regression test covers that hosting layout (single-view frame nest, and a fixed-height host such as the analysis overlay). Existing PreviewSurfaceTests still pass. (pass) — Same test also hosts PreviewSurfaceView.frame(height: 130) matching AnalysisDebugPanel's fixed-height overlay. Full PreviewSurfaceTests suite: 40/40 passed.
- [x] Pan, zoom, double-click, crop hit-testing, and drawable-size preview scheduling are unchanged. sizeThatFits does not call updatePreviewBackingSize. (pass) — Diff is additive-only (15 new lines in PreviewSurface.swift); no existing hit-testing, gesture, or drawable-size code paths were touched. sizeThatFits only computes a CGSize from the proposal and does not reference surface, AppViewModel, or updatePreviewBackingSize.
- [ ] If the inspector is still hot, NeutralOriginSlider gets the same kind of sizeThatFits and a test that a row lays out without depending on NSSlider's intrinsic width. If a probe shows slider measurement is cheap, say so in the handoff and leave the slider alone. (not_applicable) — The captured 13/13-sample hang stack names only PreviewMTKView/AppKitPlatformViewHost via the nested canvas frames; NeutralOriginSlider does not appear in that stack. No follow-up sample was taken (no WindowServer access in this environment) to confirm or rule out the slider as a second leaf, so leaving it untouched matches the issue's conditional instruction, though a human should capture a follow-up sample after this fix lands to close this out definitively.
- [ ] Manual check: swift run, open a photo, resize the window, toggle side-by-side, enter and leave crop. The window stays responsive. (not_applicable) — Not performable in this non-interactive environment (no WindowServer to drive/observe the AppKit window). swift build succeeds cleanly and the full fast test lane passes; a human should still run the manual resize/side-by-side/crop smoke before considering the beachball fully closed in practice.
Checks run:
- swift test --filter PreviewSurfaceTests (40/40 passed)
- scripts/ci-tests.sh fast (1179/1179 passed, exit 0)
- swift build (clean, 0 errors)
- git diff --check (clean)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUEQ3REQONMYJRM3
