---
id: KRMA-663
title: Add retouch visualization, dust detection, and multi-frame spot workflow
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Implement A / Visualize Spots as an in-canvas display mode with adjustable threshold, revealing candidate blemishes without changing the rendered image or edit recipe. Integrate with KRMA-661 overlay policy and keyboard routing; retire the DustFinderSheet workflow where it is superseded.
      result: pass
      notes: "KeyboardShortcuts.swift binds plain 'A' (gated by isRetouchCanvasActive and KeyMonitorPolicy.isPlainCharacterShortcut) to AppViewModel.toggleRetouchVisualization(), which flips retouchInteractionState.visualizationEnabled and recomputes candidates via RenderEngine.retouchAnalysisProxy + RetouchDustDetector. RetouchCanvasOverlay draws visualizationCandidates only under state.shouldShowOverlay (KRMA-661 overlay policy), and the analysis is a display-only overlay: no document/render mutation. DustFinderSheet.swift was deleted and RetouchInspectorView no longer presents it; grep found zero remaining references."
    - criterion: Implement Detect Dust using difference-of-Gaussians blob detection constrained to smooth image regions so texture, foliage, and real detail are not indiscriminately marked. Present dashed suggestion pins distinct from committed spots; clicking a suggestion accepts it and Accept All creates normal editable Remove spots with deterministic seeds.
      result: pass
      notes: "RetouchDustDetector.detect (Sources/KromoraKit/Models/RetouchAnalysis/RetouchDustDetector.swift) runs a 3-scale DoG over blurred Lab luminance, applies isLocalMaximum + smoothRegion gradient/variance gating to reject textured/edge regions, and derives a stable per-pixel seed. RetouchCanvasOverlay renders dustSuggestions as dashed mint pins distinct from the solid committed-spot markers. RetouchWorkflowCoordinator.beginGesture hit-tests suggestions first; a plain click (no move) calls acceptDustSuggestion, converting to a normal RetouchSpot(mode: .remove) with the suggestion's deterministic seed. acceptAllDustSuggestions wraps all conversions in begin/endUndoGrouping for one undo entry."
    - criterion: Allow suggested positions/size to be adjusted or dismissed before acceptance. Accepted detections must flow through the same source-space region model, undo/history, fill solving, visibility, and rendering path as manually painted spots.
      result: pass
      notes: "RetouchWorkflowCoordinator's .suggestion gesture case supports drag-to-move and drag-from-edge-to-resize (isResizingSuggestion threshold at 0.65 of radius) prior to acceptance; dismissDustSuggestion/dismissAllDustSuggestions remove suggestions without side effects. Accepted spots become ordinary RetouchSpot values appended to document.retouch.spots, so they use the existing Remove solver, undo stack (verified by testAcceptedDustSuggestionUsesNormalUndoHistory: undoDepth == 1, undo empties spots), visibility, and RenderEngine path -- no parallel code path was introduced."
    - criterion: Measure dust detection precision and recall against KRMA-658's synthetic dust fixtures, document initial operating threshold and false-positive behavior, and retain the manual brush as a straightforward fallback.
      result: pass
      notes: "RetouchDustDetectorTests.testDetectionRestrictionsAndPrecisionRecallReport runs the detector against RetouchQualityFixtures (KRMA-658) across all backgrounds/soft-dust/speck combinations and prints/asserts precision and fixture-recall; observed and reproduced locally: pixel_precision=1.000 fixture_recall=0.083 fixtures=12. docs/RETOUCH.md's new 'Dust suggestions use a CPU difference-of-Gaussians...' paragraph documents the 0.025 initial threshold, the 0.005-0.12 adjustable range, the measured precision/recall with an honest description of the low recall and its causes, and states the numbers are fixture-scale, not camera-representative. The manual brush remains available and unchanged; the inspector's fallback copy explicitly says so."
    - criterion: Support copying spots to selected frames as part of selective Retouch copy/paste. Preserve region coordinates where frames are related and automatically re-pick/re-solve on each target because fill caches are source-fingerprint scoped. Report completion or unresolved solves without silently applying a stale field from the source frame.
      result: pass
      notes: EditClipboardPayload.applying clears spot.source (patch offsets) while preserving region/seed/mode/visibility when the .retouch category is copied, forcing each destination to re-pick/re-solve under its own cache fingerprint (RenderEngine caches are source-fingerprint scoped elsewhere in the codebase). AppViewModel.pasteCompletionMessage appends '; retouch sources resolve per photo' whenever the retouch category is included, so batch paste communicates that fields are not carried over stale. EditClipboardTests.testRetouchRecipesCopyOnlyWhenRetouchCategoryIsSelected and CopyPasteTests exercise this.
    - criterion: Add tests for visualization threshold behavior, detection restrictions and precision/recall report, accept-one/Accept-All recipe creation, undo, dismiss, and cross-frame copy with per-source re-solve. Update docs/RETOUCH.md with the dust workflow and its measured limits.
      result: pass
      notes: RetouchDustDetectorTests covers threshold determinism/filtering, precision/recall reporting, and the smooth-region gate. RetouchWorkflowCoordinatorTests.testAcceptOneAcceptAllDismissAndDragSuggestion and testClickingCanvasSuggestionAcceptsIt cover accept-one, Accept-All (grouped undo), drag-move, drag-resize, and dismiss/dismiss-all. CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory covers undo. EditClipboardTests.testRetouchRecipesCopyOnlyWhenRetouchCategoryIsSelected covers cross-frame copy clearing sampled sources. docs/RETOUCH.md was updated with the A/Detect Dust/Accept-All/dismiss workflow, the DoG detector description, the measured precision/recall limits, and the selective-copy re-solve behavior.
  checks_run:
    - swift build (clean, 0 errors)
    - swift test --filter 'RetouchDust|RetouchAnalysis|RetouchInspector' (3 tests, 0 failures; printed 'pixel_precision=1.000 fixture_recall=0.083 fixtures=12')
    - swift test --filter 'RetouchWorkflowCoordinatorTests|EditClipboardTests|CopyPasteTests' (21 tests, 0 failures) -- run in addition to the issue's declared filter because it did not cover the new workflow-coordinator and clipboard tests added by this change
    - scripts/ci-tests.sh fast (1,308 tests, exit 0, 0 failures)
    - dg validate (OK; only pre-existing unrelated agents.pickup/model-name warnings)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T23:22:29.733Z
  session: 01MUKFPCX2C4CIIR5T
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - retouch
  - remove-heal-clone
created: 2026-09-27T18:53:56.169Z
updated: 2026-09-27T23:22:29.735Z
parent: KRMA-599
depends_on:
  - KRMA-661
  - KRMA-665
blockers: []
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/Views/RetouchInspectorView.swift
    - Sources/KromoraKit/Models/RetouchAnalysis/
    - Sources/KromoraKit/Models/RetouchWorkflowCoordinator.swift
    - Sources/KromoraKit/KeyboardShortcuts.swift
  docs:
    - .context/2026-09-27-heal-remove-plan.md
    - docs/RETOUCH.md
  issues:
    - KRMA-658
    - KRMA-661
    - KRMA-662
    - KRMA-665
  commands:
    - swift test --filter 'RetouchDust|RetouchAnalysis|RetouchInspector'
    - scripts/ci-tests.sh fast
    - dg validate
---

## Objective

Add in-canvas spot visualization and suggested dust repairs, then make accepted retouch spots
practical to copy across selected related frames.

## Context

The dust finder sheet is being retired as the primary working surface by KRMA-661's canvas tool.
Photographers still need to reveal faint dust, create reliable suggestions without painting every
spot manually, and reuse sensor-dust corrections across related frames. This phase is workflow
polish after the canvas and Remove fill lifecycle exist; detections must become ordinary editable
spots rather than a second correction system.

## Acceptance criteria

- [ ] Implement A / Visualize Spots as an in-canvas display mode with adjustable threshold,
      revealing candidate blemishes without changing the rendered image or edit recipe. Integrate
      with KRMA-661 overlay policy and keyboard routing; retire the DustFinderSheet workflow where
      it is superseded.
- [ ] Implement Detect Dust using difference-of-Gaussians blob detection constrained to smooth
      image regions so texture, foliage, and real detail are not indiscriminately marked. Present
      dashed suggestion pins distinct from committed spots; clicking a suggestion accepts it and
      Accept All creates normal editable Remove spots with deterministic seeds.
- [ ] Allow suggested positions/size to be adjusted or dismissed before acceptance. Accepted
      detections must flow through the same source-space region model, undo/history, fill solving,
      visibility, and rendering path as manually painted spots.
- [ ] Measure dust detection precision and recall against KRMA-658's synthetic dust fixtures,
      document initial operating threshold and false-positive behavior, and retain the manual
      brush as a straightforward fallback.
- [ ] Support copying spots to selected frames as part of selective Retouch copy/paste. Preserve
      region coordinates where frames are related and automatically re-pick/re-solve on each
      target because fill caches are source-fingerprint scoped. Report completion or unresolved
      solves without silently applying a stale field from the source frame.
- [ ] Add tests for visualization threshold behavior, detection restrictions and precision/recall
      report, accept-one/Accept-All recipe creation, undo, dismiss, and cross-frame copy with
      per-source re-solve. Update `docs/RETOUCH.md` with the dust workflow and its measured limits.

## Implementation notes

Keep detection CPU/on-device and value-only under Swift 6 rules. Do not reintroduce a separate
sheet-centric retouch workflow; suggestions are an overlay over the same canvas and accepted
spots use the Remove pipeline from KRMA-662 (solver) and KRMA-665 (engine integration).

### Comment — codex @ 2026-09-27T23:12:34.988Z

Implementation complete: in-canvas threshold visualization and CPU DoG dust suggestions, editable accept/dismiss/drag/resize flow, deterministic Remove spots and undo, and selective Retouch paste that clears frame-specific sources so each destination resolves its own fill. Documentation records detector results (precision 1.00, fixture recall 0.083 at threshold 0.025) and limits. Checks: focused retouch tests, scripts/ci-tests.sh fast (1,308 tests completed), dg validate.

### Comment — codex @ 2026-09-27T23:12:46.007Z

Committed as bd59a9b. Implementation and verification are complete; handing off to review. Detector operating-point limits are recorded in docs/RETOUCH.md.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-27T23:22:29.733Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Implement A / Visualize Spots as an in-canvas display mode with adjustable threshold, revealing candidate blemishes without changing the rendered image or edit recipe. Integrate with KRMA-661 overlay policy and keyboard routing; retire the DustFinderSheet workflow where it is superseded. (pass) — KeyboardShortcuts.swift binds plain 'A' (gated by isRetouchCanvasActive and KeyMonitorPolicy.isPlainCharacterShortcut) to AppViewModel.toggleRetouchVisualization(), which flips retouchInteractionState.visualizationEnabled and recomputes candidates via RenderEngine.retouchAnalysisProxy + RetouchDustDetector. RetouchCanvasOverlay draws visualizationCandidates only under state.shouldShowOverlay (KRMA-661 overlay policy), and the analysis is a display-only overlay: no document/render mutation. DustFinderSheet.swift was deleted and RetouchInspectorView no longer presents it; grep found zero remaining references.
- [x] Implement Detect Dust using difference-of-Gaussians blob detection constrained to smooth image regions so texture, foliage, and real detail are not indiscriminately marked. Present dashed suggestion pins distinct from committed spots; clicking a suggestion accepts it and Accept All creates normal editable Remove spots with deterministic seeds. (pass) — RetouchDustDetector.detect (Sources/KromoraKit/Models/RetouchAnalysis/RetouchDustDetector.swift) runs a 3-scale DoG over blurred Lab luminance, applies isLocalMaximum + smoothRegion gradient/variance gating to reject textured/edge regions, and derives a stable per-pixel seed. RetouchCanvasOverlay renders dustSuggestions as dashed mint pins distinct from the solid committed-spot markers. RetouchWorkflowCoordinator.beginGesture hit-tests suggestions first; a plain click (no move) calls acceptDustSuggestion, converting to a normal RetouchSpot(mode: .remove) with the suggestion's deterministic seed. acceptAllDustSuggestions wraps all conversions in begin/endUndoGrouping for one undo entry.
- [x] Allow suggested positions/size to be adjusted or dismissed before acceptance. Accepted detections must flow through the same source-space region model, undo/history, fill solving, visibility, and rendering path as manually painted spots. (pass) — RetouchWorkflowCoordinator's .suggestion gesture case supports drag-to-move and drag-from-edge-to-resize (isResizingSuggestion threshold at 0.65 of radius) prior to acceptance; dismissDustSuggestion/dismissAllDustSuggestions remove suggestions without side effects. Accepted spots become ordinary RetouchSpot values appended to document.retouch.spots, so they use the existing Remove solver, undo stack (verified by testAcceptedDustSuggestionUsesNormalUndoHistory: undoDepth == 1, undo empties spots), visibility, and RenderEngine path -- no parallel code path was introduced.
- [x] Measure dust detection precision and recall against KRMA-658's synthetic dust fixtures, document initial operating threshold and false-positive behavior, and retain the manual brush as a straightforward fallback. (pass) — RetouchDustDetectorTests.testDetectionRestrictionsAndPrecisionRecallReport runs the detector against RetouchQualityFixtures (KRMA-658) across all backgrounds/soft-dust/speck combinations and prints/asserts precision and fixture-recall; observed and reproduced locally: pixel_precision=1.000 fixture_recall=0.083 fixtures=12. docs/RETOUCH.md's new 'Dust suggestions use a CPU difference-of-Gaussians...' paragraph documents the 0.025 initial threshold, the 0.005-0.12 adjustable range, the measured precision/recall with an honest description of the low recall and its causes, and states the numbers are fixture-scale, not camera-representative. The manual brush remains available and unchanged; the inspector's fallback copy explicitly says so.
- [x] Support copying spots to selected frames as part of selective Retouch copy/paste. Preserve region coordinates where frames are related and automatically re-pick/re-solve on each target because fill caches are source-fingerprint scoped. Report completion or unresolved solves without silently applying a stale field from the source frame. (pass) — EditClipboardPayload.applying clears spot.source (patch offsets) while preserving region/seed/mode/visibility when the .retouch category is copied, forcing each destination to re-pick/re-solve under its own cache fingerprint (RenderEngine caches are source-fingerprint scoped elsewhere in the codebase). AppViewModel.pasteCompletionMessage appends '; retouch sources resolve per photo' whenever the retouch category is included, so batch paste communicates that fields are not carried over stale. EditClipboardTests.testRetouchRecipesCopyOnlyWhenRetouchCategoryIsSelected and CopyPasteTests exercise this.
- [x] Add tests for visualization threshold behavior, detection restrictions and precision/recall report, accept-one/Accept-All recipe creation, undo, dismiss, and cross-frame copy with per-source re-solve. Update docs/RETOUCH.md with the dust workflow and its measured limits. (pass) — RetouchDustDetectorTests covers threshold determinism/filtering, precision/recall reporting, and the smooth-region gate. RetouchWorkflowCoordinatorTests.testAcceptOneAcceptAllDismissAndDragSuggestion and testClickingCanvasSuggestionAcceptsIt cover accept-one, Accept-All (grouped undo), drag-move, drag-resize, and dismiss/dismiss-all. CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory covers undo. EditClipboardTests.testRetouchRecipesCopyOnlyWhenRetouchCategoryIsSelected covers cross-frame copy clearing sampled sources. docs/RETOUCH.md was updated with the A/Detect Dust/Accept-All/dismiss workflow, the DoG detector description, the measured precision/recall limits, and the selective-copy re-solve behavior.
Checks run:
- swift build (clean, 0 errors)
- swift test --filter 'RetouchDust|RetouchAnalysis|RetouchInspector' (3 tests, 0 failures; printed 'pixel_precision=1.000 fixture_recall=0.083 fixtures=12')
- swift test --filter 'RetouchWorkflowCoordinatorTests|EditClipboardTests|CopyPasteTests' (21 tests, 0 failures) -- run in addition to the issue's declared filter because it did not cover the new workflow-coordinator and clipboard tests added by this change
- scripts/ci-tests.sh fast (1,308 tests, exit 0, 0 failures)
- dg validate (OK; only pre-existing unrelated agents.pickup/model-name warnings)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUKFPCX2C4CIIR5T
Summary: Verified in-canvas dust visualization, DoG-based Detect Dust with precision/recall measurement, accept/dismiss/drag suggestion editing feeding the normal Remove spot + undo path, and selective retouch copy clearing sampled sources for per-frame re-solve. Build, focused tests, full fast suite (1308/1308), and dg validate all pass; no findings, no fixes needed.
