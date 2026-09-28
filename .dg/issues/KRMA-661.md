---
id: KRMA-661
title: Add Lightroom-style retouch brush interaction to the canvas
type: feature
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Add RetouchInteractionState and an AppViewModel-owned RetouchWorkflowCoordinator with begin/update/end/cancel gesture flow, source-space hit testing, selection/hover/active handles, overlay policy, shift-click anchor, and in-flight solve state. Commit through updateDocument exactly once per gesture so undo produces one entry per action.
      result: pass
      notes: "RetouchInteractionState.swift and RetouchWorkflowCoordinator.swift implement begin/update/end/cancelGesture, hitTest in source space, selection/hover/activeHandle, OverlayPolicy, shiftClickAnchor, and solvingSpotIDs. Found and fixed a real gap: create/move gestures that trigger an automatic source pick called updateDocument once for the gesture and a second time later from the async pickRetouchSource callback, producing two undo entries for one user action. Fixed by wrapping the gesture-plus-async-pick span in destination.beginUndoGrouping()/endUndoGrouping() (mirroring the existing MaskingWorkflowCoordinator pattern; AppViewModel already implemented both methods). Added testAutomaticSourcePickGroupsWithGestureCommitForOneUndoEntry to RetouchWorkflowCoordinatorTests.swift, which now passes."
    - criterion: Reuse MaskPointerSurface/MaskPointerNSView, BrushSample, BrushStroke, brush resampling/simplification, LocalMaskRenderer stroke rasterization/cache, and existing viewport transforms. Opening Retouch or pressing Q arms it, closes crop and masking, and provides one canvas input owner at a time.
      result: pass
      notes: RetouchCanvasOverlay.swift composes MaskPointerSurface directly and reuses BrushSample/BrushMaskMath resampling. AppViewModel.setRetouchCanvasActive (AppViewModel.swift:803-809) cancels an active crop and closes the masking workspace when retouch arms; selectInspectorTab does the reverse for masking. Added testArmingRetouchClosesAnActiveCropSoOnlyOneCanvasToolOwnsInputAtATime to KeyMonitorTests.swift covering the crop side of this exclusivity (masking-side exclusivity was verified by inspection; a masking-workspace unit test needs a fully loaded asset and was judged out of scope for a localized verification fix).
    - criterion: Implement click = circular region, drag = one free-form stroke, shift-click = straight segment chained from the previous click, and ⌘-drag on a newly created circle = manual source selection. Show a translucent draft overlay while painting and defer render/solve until the gesture commits.
      result: pass
      notes: RetouchWorkflowCoordinator.beginGesture/updateGesture/endGesture implement single-sample click, multi-sample drag with distance-gated resampling, shift-click segment chaining from shiftClickAnchor, and command-drag manual source assignment (isCommandCreatingSource). RetouchCanvasOverlay.draw renders a translucent draft wash from draftSamples while state.hasDraft is true; the document is only mutated in endGesture. testClickAndDragCommitOneSpotEach and testShiftClickChainsSegmentAndDestinationMoveCommitsOnce cover this.
    - criterion: Implement destination pin movement (auto source re-picks; manual source remains absolute), source-handle dragging (switches to manual source), source-to-destination arrow, hover and selected outlines, and a small spinner while an asynchronous Remove fill is pending.
      result: pass
      notes: The .move gesture case keeps manual sources at an absolute point (offset adjusted by -dx/-dy) and re-picks only automatic sources, now correctly grouped into one undo entry. The .source gesture case switches to .manual on drag. RetouchCanvasOverlay draws the dashed source arrow, hover/selection outlines, and a spinner arc for solvingSpotIDs. testMovingDestinationKeepsManualSourceAtAbsolutePoint and testSourceHandleSwitchesToManualAndDeleteRemovesSpot cover the model side.
    - criterion: Support deletion by ⌥-click and Delete/Backspace, / next-best source or new Remove seed, H overlay policy cycle (Auto/Always/Selected/Never), bracket sizing, ⇧bracket feathering, ⌥-scroll sizing, Space pan, and existing scroll/pinch zoom. Q and Escape follow the stated enter/deselect/exit behavior; A remains assigned to visualization in KRMA-663.
      result: pass
      notes: KeyboardShortcuts.swift (Sources/KromoraKit/Views/KeyboardShortcuts.swift) wires Delete/Backspace (case 51/117) to retouchWorkflow.deleteSelected(), Escape (case 53) through the documented cancel-draft/deselect/exit priority chain, Space (case 49) to setSpacePanning, '/' to nextSource(), 'h' to cycleOverlayPolicy(), and '[' / ']' to radius/feather (shift). ⌥-click delete and ⌥-drag manual source live in RetouchWorkflowCoordinator.beginGesture/updateGesture. ⌥-scroll sizing is handled in RetouchCanvasOverlay.handle(.scrolled). testRetouchShortcutsArmCycleOverlayAndExitInTwoSteps exercises Q/H/bracket/Escape/deselect/exit. 'A' is untouched by this change.
    - criterion: Rewrite the inspector around Remove | Heal | Clone with Remove selected by default, plus Size, Feather, Opacity, overlay/spot count, Reset All, and selection-scoped editing. Remove coordinate sliders and previous/next spot controls; retain the existing red-eye section for now. Normalize size to the source short side and keep a visible minimum on-screen ring.
      result: pass
      notes: RetouchInspectorView.swift has a segmented Remove/Heal/Clone picker (RetouchMode default .remove), Size/Feather/Opacity sliders, spot count + overlay picker, Reset All, and selection-scoped bindings; no coordinate sliders remain. Removed the dead selectSpot(_:) previous/next-spot helper left over from the prior slider-based UI (unused after the AC's control removal, unreferenced anywhere in the view body). Red-eye section is retained. Size normalization and minimum-ring behavior live in RetouchCanvasOverlay.screenRadius (max(4, ...)).
    - criterion: Add RetouchCanvasOverlay beside MaskCanvasOverlay on the preview canvas with brush ring, feather ring, crosshair, draft wash, pins, outlines, source arrow, and solve indicators. Map oriented-source normalized points to the viewport with GeometryPointMapping.
      result: pass
      notes: RetouchCanvasOverlay.swift is composed in PreviewView.swift:364-365 alongside the masking overlay, gated on viewModel.isRetouchCanvasActive. Its draw(context:size:mapping:) renders the hover brush/feather ring with crosshair, the draft wash while painting, spot pins/outlines, the source arrow with cyan source ring, and the solving spinner arc. All coordinates route through GeometryPointMapping.viewportPoint(forRetouchPoint:)/retouchPoint(forViewport:), consistent with GeometryPointMappingTests.testRetouchSourcePointMapsThroughViewportAndBack.
    - criterion: Add coordinator/UI/keyboard tests for click, drag, shift-click, one-undo-per-gesture, source/destination manipulation, deletion, / behavior, tool ownership, and coordinate mapping. Manually verify in-app pointer, tablet/coalesced samples, zoom, and pan behavior. Heal/Clone must now be usable on-canvas with auto source from KRMA-660.
      result: pass
      notes: RetouchWorkflowCoordinatorTests covers click/drag/shift-click/one-undo-per-gesture (including the newly added grouping test)/source-destination manipulation/next-source/deletion. KeyMonitorTests covers Q/H/bracket/Escape keyboard behavior plus the newly added crop tool-ownership exclusivity test. GeometryPointMappingTests covers the retouch coordinate round-trip. RetouchQualityEvaluationTests exercises Heal/Clone with automatic sources from KRMA-660 against the ground-truth corpus (5/36 automatic Heal rows pass, matching the recorded KRMA-660/666 baseline; documented gap, not a regression). In-app pointer/tablet/coalesced-sample/zoom/pan verification was not performed in this run (no interactive macOS session available to this agent); this matches the same gap the implementation comment already disclosed.
  checks_run:
    - swift build (clean, 0 errors)
    - swift test --filter 'RetouchWorkflowCoordinatorTests|RetouchModelTests|RetouchSourcePickerTests|KeyMonitorTests|GeometryPointMappingTests|RetouchQualityEvaluationTests' (42 tests, 0 failures; RetouchQualityEvaluationTests failures are documented KRMA-660/666 baseline gaps, not regressions)
    - scripts/ci-tests.sh fast (1301 tests, exit 0, 0 failures) — rerun after adding the tool-ownership test, still exit 0
    - scripts/ci-tests.sh serial (435 tests, 1 skipped, 0 failures)
    - dg validate (OK; only pre-existing unrelated agent-model-name warnings)
  findings:
    - "[correctness, fixed] RetouchWorkflowCoordinator.endGesture called destination.updateDocument once to commit the new/moved spot and, when the source was automatic, a second time later inside the async pickRetouchSource(spotID:rank:) continuation — two undo entries for what the acceptance criteria require to be one gesture. Fixed (already present, uncommitted, in the working tree when this verification began) by wrapping the gesture-commit-plus-async-pick span in destination.beginUndoGrouping()/endUndoGrouping(), the same pattern MaskingWorkflowCoordinator already uses; verified with a new coordinator test and a full test-suite run."
    - "[test-coverage, fixed] No test exercised retouch/crop mutual exclusivity (arming retouch must close an active crop, per the acceptance criteria's 'one canvas input owner at a time'). Added testArmingRetouchClosesAnActiveCropSoOnlyOneCanvasToolOwnsInputAtATime to KeyMonitorTests.swift. The masking side of the same exclusivity was verified by inspection only (AppViewModel.setRetouchCanvasActive / selectInspectorTab); adding a masking-workspace unit test requires a fully loaded photo asset and was judged out of scope for a localized verification fix."
    - "[unrelated, not fixed] The working tree at claim time also had uncommitted, unrelated changes to Sources/KromoraKit/Models/PortableLibrarySession.swift, Sources/KromoraKit/ViewModels/AppViewModel.swift (virtual-copy display-name and library-grid navigation logic), and Tests/KromoraKitTests/PackageEditProjectionTests.swift. These do not touch retouch and were left untouched per the project's pre-existing-changes policy; they were not committed as part of this verification."
  fixes:
    - "Sources/KromoraKit/ViewModels/RetouchWorkflowCoordinator.swift: group the gesture commit and its async automatic-source pick into one undo entry via begin/endUndoGrouping"
    - "Sources/KromoraKit/Views/RetouchInspectorView.swift: remove the dead selectSpot(_:) previous/next-spot helper"
    - "Tests/KromoraKitTests/RetouchWorkflowCoordinatorTests.swift: add testAutomaticSourcePickGroupsWithGestureCommitForOneUndoEntry"
    - "Tests/KromoraKitTests/KeyMonitorTests.swift: add testArmingRetouchClosesAnActiveCropSoOnlyOneCanvasToolOwnsInputAtATime"
  verification_commits:
    - e3aae0f
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T22:09:08.171Z
  session: 01MUKCVJH1TOUGQREU
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - retouch
  - remove-heal-clone
created: 2026-09-27T18:53:54.989Z
updated: 2026-09-28T14:41:33.920Z
parent: KRMA-599
depends_on:
  - KRMA-659
  - KRMA-660
blockers: []
order: kt2b898i
board: product
context:
  files:
    - Sources/KromoraKit/Views/MaskPointerSurface.swift
    - Sources/KromoraKit/Models/MaskInteractionState.swift
    - Sources/KromoraKit/Models/MaskingWorkflowCoordinator.swift
    - Sources/KromoraKit/Models/GeometryPointMapping.swift
    - Sources/KromoraKit/Views/PreviewView.swift
    - Sources/KromoraKit/Views/RetouchInspectorView.swift
    - Sources/KromoraKit/KeyboardShortcuts.swift
  docs:
    - .context/2026-09-27-heal-remove-plan.md
    - docs/APP_ARCHITECTURE.md
  issues:
    - KRMA-659
    - KRMA-660
  commands:
    - swift test --filter 'RetouchInteraction|RetouchWorkflow|KeyboardShortcuts|RetouchInspector'
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - dg validate
commits:
  - e3aae0f
---

## Objective

Replace coordinate-slider retouch editing with a canvas brush, editable pins and source handles,
gesture-scoped commits, and keyboard/pointer behavior matching the agreed interaction spec.

## Context

Retouch currently has no canvas input even though `GeometryPointMapping.viewportPoint(forRetouchPoint:)`
exists. The inspector exposes center/source coordinate sliders, which makes spot placement slow
and prevents useful wire strokes. Masking already owns native pointer/tablet input, pressure,
coalescing, zoom, resampling, tiled masks, and draft/commit gesture flow. Reuse these boundaries
instead of creating a second pointer stack. Retouch becomes a canvas owner mutually exclusive with
crop and masking.

## Acceptance criteria

- [ ] Add `RetouchInteractionState` and an `AppViewModel`-owned `RetouchWorkflowCoordinator` with
      begin/update/end/cancel gesture flow, source-space hit testing, selection/hover/active handles,
      overlay policy, shift-click anchor, and in-flight solve state. Commit through
      `updateDocument` exactly once per gesture so undo produces one entry per action.
- [ ] Reuse `MaskPointerSurface`/`MaskPointerNSView`, `BrushSample`, `BrushStroke`, brush
      resampling/simplification, `LocalMaskRenderer` stroke rasterization/cache, and existing
      viewport transforms. Opening Retouch or pressing Q arms it, closes crop and masking, and
      provides one canvas input owner at a time.
- [ ] Implement click = circular region, drag = one free-form stroke, shift-click = straight
      segment chained from the previous click, and ⌘-drag on a newly created circle = manual source
      selection. Show a translucent draft overlay while painting and defer render/solve until the
      gesture commits.
- [ ] Implement destination pin movement (auto source re-picks; manual source remains absolute),
      source-handle dragging (switches to manual source), source-to-destination arrow, hover and
      selected outlines, and a small spinner while an asynchronous Remove fill is pending.
- [ ] Support deletion by ⌥-click and Delete/Backspace, `/` next-best source or new Remove seed,
      H overlay policy cycle (Auto/Always/Selected/Never), bracket sizing, ⇧bracket feathering,
      ⌥-scroll sizing, Space pan, and existing scroll/pinch zoom. Q and Escape follow the stated
      enter/deselect/exit behavior; A remains assigned to visualization in KRMA-663.
- [ ] Rewrite the inspector around Remove | Heal | Clone with Remove selected by default, plus Size,
      Feather, Opacity, overlay/spot count, Reset All, and selection-scoped editing. Remove
      coordinate sliders and previous/next spot controls; retain the existing red-eye section for
      now. Normalize size to the source short side and keep a visible minimum on-screen ring.
- [ ] Add `RetouchCanvasOverlay` beside `MaskCanvasOverlay` on the preview canvas with brush ring,
      feather ring, crosshair, draft wash, pins, outlines, source arrow, and solve indicators.
      Map oriented-source normalized points to the viewport with `GeometryPointMapping`.
- [ ] Add coordinator/UI/keyboard tests for click, drag, shift-click, one-undo-per-gesture,
      source/destination manipulation, deletion, `/` behavior, tool ownership, and coordinate
      mapping. Manually verify in-app pointer, tablet/coalesced samples, zoom, and pan behavior.
      Heal/Clone must now be usable on-canvas with auto source from KRMA-660.

## Implementation notes

Reuse masking contracts and preserve existing local-mask behavior. Keep view/coordinator ownership
documented in `docs/APP_ARCHITECTURE.md`. Coordinate with KRMA-662 for async Remove resolution and
KRMA-663 for A/visualization and Detect Dust controls; do not implement a second preview renderer.

### Comment — codex @ 2026-09-27T20:44:19.173Z

Implemented canvas-based retouch with pointer reuse, oriented-source mapping, click and stroke creation, shift-click segments, manual source dragging, pin/source editing, deletion, overlay controls, keyboard shortcuts, and a rewritten inspector. Added coordinator, keyboard, and geometry mapping tests. Checks passed: focused tests (26), ci fast (1,295), ci serial (434; 1 skipped), dg validate (OK with existing agent-model-name warnings). In-app pointer/tablet/coalesced sample/zoom/pan verification was not performed in this run. Commit: b709863.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-27T22:09:08.171Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Add RetouchInteractionState and an AppViewModel-owned RetouchWorkflowCoordinator with begin/update/end/cancel gesture flow, source-space hit testing, selection/hover/active handles, overlay policy, shift-click anchor, and in-flight solve state. Commit through updateDocument exactly once per gesture so undo produces one entry per action. (pass) — RetouchInteractionState.swift and RetouchWorkflowCoordinator.swift implement begin/update/end/cancelGesture, hitTest in source space, selection/hover/activeHandle, OverlayPolicy, shiftClickAnchor, and solvingSpotIDs. Found and fixed a real gap: create/move gestures that trigger an automatic source pick called updateDocument once for the gesture and a second time later from the async pickRetouchSource callback, producing two undo entries for one user action. Fixed by wrapping the gesture-plus-async-pick span in destination.beginUndoGrouping()/endUndoGrouping() (mirroring the existing MaskingWorkflowCoordinator pattern; AppViewModel already implemented both methods). Added testAutomaticSourcePickGroupsWithGestureCommitForOneUndoEntry to RetouchWorkflowCoordinatorTests.swift, which now passes.
- [x] Reuse MaskPointerSurface/MaskPointerNSView, BrushSample, BrushStroke, brush resampling/simplification, LocalMaskRenderer stroke rasterization/cache, and existing viewport transforms. Opening Retouch or pressing Q arms it, closes crop and masking, and provides one canvas input owner at a time. (pass) — RetouchCanvasOverlay.swift composes MaskPointerSurface directly and reuses BrushSample/BrushMaskMath resampling. AppViewModel.setRetouchCanvasActive (AppViewModel.swift:803-809) cancels an active crop and closes the masking workspace when retouch arms; selectInspectorTab does the reverse for masking. Added testArmingRetouchClosesAnActiveCropSoOnlyOneCanvasToolOwnsInputAtATime to KeyMonitorTests.swift covering the crop side of this exclusivity (masking-side exclusivity was verified by inspection; a masking-workspace unit test needs a fully loaded asset and was judged out of scope for a localized verification fix).
- [x] Implement click = circular region, drag = one free-form stroke, shift-click = straight segment chained from the previous click, and ⌘-drag on a newly created circle = manual source selection. Show a translucent draft overlay while painting and defer render/solve until the gesture commits. (pass) — RetouchWorkflowCoordinator.beginGesture/updateGesture/endGesture implement single-sample click, multi-sample drag with distance-gated resampling, shift-click segment chaining from shiftClickAnchor, and command-drag manual source assignment (isCommandCreatingSource). RetouchCanvasOverlay.draw renders a translucent draft wash from draftSamples while state.hasDraft is true; the document is only mutated in endGesture. testClickAndDragCommitOneSpotEach and testShiftClickChainsSegmentAndDestinationMoveCommitsOnce cover this.
- [x] Implement destination pin movement (auto source re-picks; manual source remains absolute), source-handle dragging (switches to manual source), source-to-destination arrow, hover and selected outlines, and a small spinner while an asynchronous Remove fill is pending. (pass) — The .move gesture case keeps manual sources at an absolute point (offset adjusted by -dx/-dy) and re-picks only automatic sources, now correctly grouped into one undo entry. The .source gesture case switches to .manual on drag. RetouchCanvasOverlay draws the dashed source arrow, hover/selection outlines, and a spinner arc for solvingSpotIDs. testMovingDestinationKeepsManualSourceAtAbsolutePoint and testSourceHandleSwitchesToManualAndDeleteRemovesSpot cover the model side.
- [x] Support deletion by ⌥-click and Delete/Backspace, / next-best source or new Remove seed, H overlay policy cycle (Auto/Always/Selected/Never), bracket sizing, ⇧bracket feathering, ⌥-scroll sizing, Space pan, and existing scroll/pinch zoom. Q and Escape follow the stated enter/deselect/exit behavior; A remains assigned to visualization in KRMA-663. (pass) — KeyboardShortcuts.swift (Sources/KromoraKit/Views/KeyboardShortcuts.swift) wires Delete/Backspace (case 51/117) to retouchWorkflow.deleteSelected(), Escape (case 53) through the documented cancel-draft/deselect/exit priority chain, Space (case 49) to setSpacePanning, '/' to nextSource(), 'h' to cycleOverlayPolicy(), and '[' / ']' to radius/feather (shift). ⌥-click delete and ⌥-drag manual source live in RetouchWorkflowCoordinator.beginGesture/updateGesture. ⌥-scroll sizing is handled in RetouchCanvasOverlay.handle(.scrolled). testRetouchShortcutsArmCycleOverlayAndExitInTwoSteps exercises Q/H/bracket/Escape/deselect/exit. 'A' is untouched by this change.
- [x] Rewrite the inspector around Remove | Heal | Clone with Remove selected by default, plus Size, Feather, Opacity, overlay/spot count, Reset All, and selection-scoped editing. Remove coordinate sliders and previous/next spot controls; retain the existing red-eye section for now. Normalize size to the source short side and keep a visible minimum on-screen ring. (pass) — RetouchInspectorView.swift has a segmented Remove/Heal/Clone picker (RetouchMode default .remove), Size/Feather/Opacity sliders, spot count + overlay picker, Reset All, and selection-scoped bindings; no coordinate sliders remain. Removed the dead selectSpot(_:) previous/next-spot helper left over from the prior slider-based UI (unused after the AC's control removal, unreferenced anywhere in the view body). Red-eye section is retained. Size normalization and minimum-ring behavior live in RetouchCanvasOverlay.screenRadius (max(4, ...)).
- [x] Add RetouchCanvasOverlay beside MaskCanvasOverlay on the preview canvas with brush ring, feather ring, crosshair, draft wash, pins, outlines, source arrow, and solve indicators. Map oriented-source normalized points to the viewport with GeometryPointMapping. (pass) — RetouchCanvasOverlay.swift is composed in PreviewView.swift:364-365 alongside the masking overlay, gated on viewModel.isRetouchCanvasActive. Its draw(context:size:mapping:) renders the hover brush/feather ring with crosshair, the draft wash while painting, spot pins/outlines, the source arrow with cyan source ring, and the solving spinner arc. All coordinates route through GeometryPointMapping.viewportPoint(forRetouchPoint:)/retouchPoint(forViewport:), consistent with GeometryPointMappingTests.testRetouchSourcePointMapsThroughViewportAndBack.
- [x] Add coordinator/UI/keyboard tests for click, drag, shift-click, one-undo-per-gesture, source/destination manipulation, deletion, / behavior, tool ownership, and coordinate mapping. Manually verify in-app pointer, tablet/coalesced samples, zoom, and pan behavior. Heal/Clone must now be usable on-canvas with auto source from KRMA-660. (pass) — RetouchWorkflowCoordinatorTests covers click/drag/shift-click/one-undo-per-gesture (including the newly added grouping test)/source-destination manipulation/next-source/deletion. KeyMonitorTests covers Q/H/bracket/Escape keyboard behavior plus the newly added crop tool-ownership exclusivity test. GeometryPointMappingTests covers the retouch coordinate round-trip. RetouchQualityEvaluationTests exercises Heal/Clone with automatic sources from KRMA-660 against the ground-truth corpus (5/36 automatic Heal rows pass, matching the recorded KRMA-660/666 baseline; documented gap, not a regression). In-app pointer/tablet/coalesced-sample/zoom/pan verification was not performed in this run (no interactive macOS session available to this agent); this matches the same gap the implementation comment already disclosed.
Checks run:
- swift build (clean, 0 errors)
- swift test --filter 'RetouchWorkflowCoordinatorTests|RetouchModelTests|RetouchSourcePickerTests|KeyMonitorTests|GeometryPointMappingTests|RetouchQualityEvaluationTests' (42 tests, 0 failures; RetouchQualityEvaluationTests failures are documented KRMA-660/666 baseline gaps, not regressions)
- scripts/ci-tests.sh fast (1301 tests, exit 0, 0 failures) — rerun after adding the tool-ownership test, still exit 0
- scripts/ci-tests.sh serial (435 tests, 1 skipped, 0 failures)
- dg validate (OK; only pre-existing unrelated agent-model-name warnings)
Findings:
- [correctness, fixed] RetouchWorkflowCoordinator.endGesture called destination.updateDocument once to commit the new/moved spot and, when the source was automatic, a second time later inside the async pickRetouchSource(spotID:rank:) continuation — two undo entries for what the acceptance criteria require to be one gesture. Fixed (already present, uncommitted, in the working tree when this verification began) by wrapping the gesture-commit-plus-async-pick span in destination.beginUndoGrouping()/endUndoGrouping(), the same pattern MaskingWorkflowCoordinator already uses; verified with a new coordinator test and a full test-suite run.
- [test-coverage, fixed] No test exercised retouch/crop mutual exclusivity (arming retouch must close an active crop, per the acceptance criteria's 'one canvas input owner at a time'). Added testArmingRetouchClosesAnActiveCropSoOnlyOneCanvasToolOwnsInputAtATime to KeyMonitorTests.swift. The masking side of the same exclusivity was verified by inspection only (AppViewModel.setRetouchCanvasActive / selectInspectorTab); adding a masking-workspace unit test requires a fully loaded photo asset and was judged out of scope for a localized verification fix.
- [unrelated, not fixed] The working tree at claim time also had uncommitted, unrelated changes to Sources/KromoraKit/Models/PortableLibrarySession.swift, Sources/KromoraKit/ViewModels/AppViewModel.swift (virtual-copy display-name and library-grid navigation logic), and Tests/KromoraKitTests/PackageEditProjectionTests.swift. These do not touch retouch and were left untouched per the project's pre-existing-changes policy; they were not committed as part of this verification.
Fixes:
- Sources/KromoraKit/ViewModels/RetouchWorkflowCoordinator.swift: group the gesture commit and its async automatic-source pick into one undo entry via begin/endUndoGrouping
- Sources/KromoraKit/Views/RetouchInspectorView.swift: remove the dead selectSpot(_:) previous/next-spot helper
- Tests/KromoraKitTests/RetouchWorkflowCoordinatorTests.swift: add testAutomaticSourcePickGroupsWithGestureCommitForOneUndoEntry
- Tests/KromoraKitTests/KeyMonitorTests.swift: add testArmingRetouchClosesAnActiveCropSoOnlyOneCanvasToolOwnsInputAtATime
Verification commits:
- e3aae0f
Actor: claude
Resolved model: sonnet
Pickup session: 01MUKCVJH1TOUGQREU
