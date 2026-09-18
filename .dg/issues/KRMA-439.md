---
id: KRMA-439
title: Vertical pan direction is reversed from macOS convention when zoomed
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Dragging down on a zoomed-in image pans the visible content down (same direction as Preview/Photos/Figma), matching horizontal behavior.
      result: pass
      notes: "Traced the full pipeline: DragGesture.translation (SwiftUI, y-down) -> AppViewModel.panCanvas -> CanvasNavigation.pan -> transform.origin -> quadGeometry -> PreviewSurface.metal vertex shader. The shader carries a pre-existing, authoritative comment confirming CanvasNavigation's origin is y-down pixel space (not Core Image's bottom-left space). Given that, forwarding delta.height unchanged (the fix) is the correct mapping; the removed negation was the actual bug."
    - criterion: Horizontal panning direction is unchanged (still correct).
      result: pass
      notes: delta.width was, and remains, forwarded unmodified in both the old and new code.
    - criterion: Trackpad two-finger pan and any keyboard-driven pan (if present) are consistent with the corrected mouse-drag direction.
      result: pass
      notes: Only one drag-based pan code path exists (PreviewView.dragGesture -> panCanvas), shared by mouse and trackpad drag; MaskingWorkspace's native-pointer space-drag pan also calls the same panCanvas with no independent sign handling. Canvas scrollWheel is wired only to zoom, not pan, and no dedicated keyboard-pan action exists, so there is nothing else that could diverge.
    - criterion: Add or update a regression test around CanvasNavigation.pan / AppViewModel.panCanvas asserting the vertical sign convention.
      result: pass
      notes: CanvasNavigationTests.testPanMovesTheImageInTheDirectionOfTheViewportDelta and CanvasObservationTests.testPanCanvasPreservesPointerDirectionOnBothAxes were added, asserting origin moves by +delta on both axes at the CanvasNavigation and AppViewModel levels.
  checks_run:
    - Read full diff of commit 9dfaa0b (AppViewModel.swift, CanvasNavigationTests.swift)
    - "Manual coordinate-system trace: PreviewView.dragGesture -> AppViewModel.panCanvas -> CanvasNavigation.pan/transform -> PreviewSurface.swift quadGeometry -> PreviewSurface.metal vertex shader, cross-checked against the shader's own y-down documentation comment"
    - Confirmed MaskingWorkspace's separate pan call path uses the same panCanvas with no extra sign handling, so it inherits the fix consistently
    - Confirmed no separate scroll-wheel or keyboard pan path exists (scrollWheel is wired to zoom only)
    - git status/diff review to confirm no unrelated files changed (ResolutionPlanner.swift Self.roi typo mentioned by implementer is untouched, as claimed)
    - "swift build / swift test: BLOCKED in this environment - Xcode license not accepted and no sudo access to run `xcodebuild -license`; CommandLineTools swift toolchain lacks the SwiftUI macro plugin needed to compile the target. Same limitation the implementer reported. Could not execute the test suite directly; relied on manual trace verified against the shader's documented coordinate convention."
  findings:
    - "maintainability (fixed): Sources/KromoraKit/Models/CanvasNavigation.swift:267 - CanvasTransform.origin's doc comment claimed Core Image's bottom-left coordinate system, contradicting the y-down convention the pan fix (and PreviewSurface.metal's vertex shader) actually depends on. Failure scenario: a future contributor reads the stale comment, assumes origin is CI/bottom-left, and reintroduces a vertical-axis sign flip while touching pan/zoom/focal-point code, silently reversing this same bug."
  fixes:
    - Corrected the CanvasTransform.origin doc comment in Sources/KromoraKit/Models/CanvasNavigation.swift to state the actual y-down pixel-space convention and point to PreviewSurface.metal as the authoritative cross-reference.
  verification_commits:
    - 53684b6
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-18T15:14:24.980Z
  session: 01MU73I5A7B1KEOSA9
labels:
  - ui
  - bug
  - editor
  - navigation
created: 2026-09-18T02:22:53.361Z
updated: 2026-09-18T15:14:24.982Z
order: a0
board: product
commits:
  - 53684b6
---

## Objective

When the canvas is zoomed in, vertical drag-to-pan moves the image opposite to how every other macOS app (Preview, Photos, Maps, Figma) pans a zoomed view: dragging down should reveal content below (image moves down with the cursor), but currently it moves the opposite way. Horizontal panning already feels correct.

## Context

`Sources/KromoraKit/Views/PreviewView.swift` `dragGesture(viewportSize:)` (around line 289-308) computes `delta` straight from `DragGesture.Value.translation` with no sign adjustment and forwards it to `AppViewModel.panCanvas(by:viewportSize:)`. The sign flip happens one layer up, in `Sources/KromoraKit/ViewModels/AppViewModel.swift` `panCanvas` (around line 4116-4129): line ~4121 negates only the vertical component before calling into `CanvasNavigation`:

```swift
canvasState.pan(by: CGSize(width: delta.width, height: -delta.height), ...)
```

`CanvasNavigation.pan(by:imageExtent:viewportSize:)` (`Sources/KromoraKit/Models/CanvasNavigation.swift:165-177`) then adds that delta directly to `transform.origin`. The vertical-only negation is the likely root cause — it inverts vertical drag relative to the (correct, un-negated) horizontal drag.

## Acceptance criteria

- [ ] Dragging down on a zoomed-in image pans the visible content down (same direction as System Preview / Photos / Figma canvas panning), matching horizontal behavior.
- [ ] Horizontal panning direction is unchanged (still correct).
- [ ] Trackpad two-finger pan and any keyboard-driven pan (if present) are consistent with the corrected mouse-drag direction.
- [ ] Add or update a regression test around `CanvasNavigation.pan` / `AppViewModel.panCanvas` asserting the vertical sign convention, so this can't silently flip back.

## Out of scope

- Changing zoom gesture behavior (pinch/scroll-to-zoom) itself — only the pan direction while zoomed.


### Comment — codex @ 2026-09-18T15:10:18.230Z

Implemented in commit 9dfaa0b. Fixed AppViewModel.panCanvas to forward viewport-space deltas unchanged, preserving horizontal behavior and making vertical drag follow the pointer. Added CanvasNavigation and AppViewModel regression coverage for both axes. dg validate passes. Focused Swift target compiles after temporarily correcting the pre-existing ResolutionPlanner Self.roi typo for validation; test execution is unavailable because the local SwiftPM helper cannot load XCTest, and the unrelated baseline typo is restored.

## Agent log

- 2026-09-18T15:14:24.980Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Dragging down on a zoomed-in image pans the visible content down (same direction as Preview/Photos/Figma), matching horizontal behavior. (pass) — Traced the full pipeline: DragGesture.translation (SwiftUI, y-down) -> AppViewModel.panCanvas -> CanvasNavigation.pan -> transform.origin -> quadGeometry -> PreviewSurface.metal vertex shader. The shader carries a pre-existing, authoritative comment confirming CanvasNavigation's origin is y-down pixel space (not Core Image's bottom-left space). Given that, forwarding delta.height unchanged (the fix) is the correct mapping; the removed negation was the actual bug.
- [x] Horizontal panning direction is unchanged (still correct). (pass) — delta.width was, and remains, forwarded unmodified in both the old and new code.
- [x] Trackpad two-finger pan and any keyboard-driven pan (if present) are consistent with the corrected mouse-drag direction. (pass) — Only one drag-based pan code path exists (PreviewView.dragGesture -> panCanvas), shared by mouse and trackpad drag; MaskingWorkspace's native-pointer space-drag pan also calls the same panCanvas with no independent sign handling. Canvas scrollWheel is wired only to zoom, not pan, and no dedicated keyboard-pan action exists, so there is nothing else that could diverge.
- [x] Add or update a regression test around CanvasNavigation.pan / AppViewModel.panCanvas asserting the vertical sign convention. (pass) — CanvasNavigationTests.testPanMovesTheImageInTheDirectionOfTheViewportDelta and CanvasObservationTests.testPanCanvasPreservesPointerDirectionOnBothAxes were added, asserting origin moves by +delta on both axes at the CanvasNavigation and AppViewModel levels.
Checks run:
- Read full diff of commit 9dfaa0b (AppViewModel.swift, CanvasNavigationTests.swift)
- Manual coordinate-system trace: PreviewView.dragGesture -> AppViewModel.panCanvas -> CanvasNavigation.pan/transform -> PreviewSurface.swift quadGeometry -> PreviewSurface.metal vertex shader, cross-checked against the shader's own y-down documentation comment
- Confirmed MaskingWorkspace's separate pan call path uses the same panCanvas with no extra sign handling, so it inherits the fix consistently
- Confirmed no separate scroll-wheel or keyboard pan path exists (scrollWheel is wired to zoom only)
- git status/diff review to confirm no unrelated files changed (ResolutionPlanner.swift Self.roi typo mentioned by implementer is untouched, as claimed)
- swift build / swift test: BLOCKED in this environment - Xcode license not accepted and no sudo access to run `xcodebuild -license`; CommandLineTools swift toolchain lacks the SwiftUI macro plugin needed to compile the target. Same limitation the implementer reported. Could not execute the test suite directly; relied on manual trace verified against the shader's documented coordinate convention.
Findings:
- maintainability (fixed): Sources/KromoraKit/Models/CanvasNavigation.swift:267 - CanvasTransform.origin's doc comment claimed Core Image's bottom-left coordinate system, contradicting the y-down convention the pan fix (and PreviewSurface.metal's vertex shader) actually depends on. Failure scenario: a future contributor reads the stale comment, assumes origin is CI/bottom-left, and reintroduces a vertical-axis sign flip while touching pan/zoom/focal-point code, silently reversing this same bug.
Fixes:
- Corrected the CanvasTransform.origin doc comment in Sources/KromoraKit/Models/CanvasNavigation.swift to state the actual y-down pixel-space convention and point to PreviewSurface.metal as the authoritative cross-reference.
Verification commits:
- 53684b6
Actor: claude
Resolved model: sonnet
Pickup session: 01MU73I5A7B1KEOSA9
Summary: Verified: pan-direction fix is correct per the render pipeline's y-down convention (confirmed via PreviewSurface.metal's shader comment); horizontal path and all pan entry points remain consistent; regression tests added. Build/test execution was blocked by an unaccepted Xcode license in this environment (no sudo), same limitation the implementer hit; verified by full manual trace instead. Applied one small localized fix: corrected a stale, misleading doc comment on CanvasTransform.origin that claimed the wrong coordinate convention.
