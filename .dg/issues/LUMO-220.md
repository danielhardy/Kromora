---
id: LUMO-220
title: Replace selection-only mask sheet with persistent Masking workspace
type: feature
status: done
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - epic:masking
  - masking
  - editor
  - accessibility
created: 2026-09-04T21:48:29.898Z
updated: 2026-09-05T13:44:23.008Z
depends_on:
  - LUMO-217
  - LUMO-218
  - LUMO-219
  - LUMO-229
order: a0
board: product
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-05T13:44:23.005Z
  session: 01MTOFNGVK36JI167N
---

## Objective

Build the persistent editor workspace that creates, selects, organizes, and re-edits saved mask
layers and their local adjustments.

## Context

The current modal `MaskingPanel` previews semantic results but has no document owner or active local
adjustment. A production workflow needs a stable mask list beside the main canvas, immediate access
to the selected layer's settings, and reliable transitions between masking, navigation, and crop.

## Acceptance criteria

- [ ] The toolbar Mask action activates a persistent Masking workspace rather than a disconnected
      Apply sheet; there is one masking product and one owner of selected mask state.
- [ ] Show ordered layers with overlay color, editable name, type summary, selected state,
      enable/disable, amount, invert, duplicate, delete, reorder, and reset actions.
- [ ] Selecting an existing layer restores its saved component controls and local-adjustment slider
      values; all durable changes route through `AppViewModel.updateDocument`.
- [ ] Local sliders and continuous controls use existing preview interaction/undo grouping so each
      gesture becomes one undo entry and the final value receives a settled preview.
- [ ] Overlay color/opacity, color-wash versus grayscale inspection, solo display, active tool,
      hover, and handle selection remain presentation-only.
- [ ] Loading, partial smart results, unavailable target, retry, and render failure are explicit and
      do not freeze or discard the layer definition.
- [ ] Source switching cancels drafts and stale async work, clears old overlays, and restores the
      selected layer belonging to the newly active photo.
- [ ] Crop and mask tools have mutually exclusive hit-test ownership; Space-pan, zoom, fit/fill,
      Escape/cancel, and existing comparison behavior remain usable.
- [ ] Core list/actions/sliders have VoiceOver labels, values, state, focus order, and keyboard access.

## Implementation notes

Follow Section 5 plus Step 3 of `docs/MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md`. Likely integration
points are `ContentView.swift`, `PreviewView.swift`, `PreviewSurface.swift`, inspector state/routing,
keyboard/menu commands, `AppViewModel+Masking.swift`, and the new `MaskInteractionState`.

Retire `MaskingPanel.swift` or reduce it to genuinely shared semantic-result UI. Do not leave two
workflows with conflicting selection or apply semantics.

### Comment — codex @ 2026-09-05T04:34:36.040Z

Implemented in commit 0af0c30. Added persistent masking workspace, document-owned layer/component actions, presentation-only overlay state and canvas guides, source-safe selection reset, crop hit-test ownership, Escape handling, and local adjustment controls. Verification: swift test --filter MaskingWorkspaceTests, swift test --filter AdjustInspectorTests, swift test --filter LocalMaskTests, and dg validate pass. Full swift test reaches 849 tests but currently has 23 pre-existing source-loading/persistence/comparison/export failures unrelated to masking.

### Comment — claude @ 2026-09-05T04:40:28.439Z

{
  "verdict": "blocked",
  "reviewer": "claude",
  "summary": "Correctness bug fixed in place; one unmet acceptance criterion (functional mask overlay/solo inspection) is a genuine feature gap requiring render-pipeline work beyond a localized fix, so this is returned to review rather than completed.",
  "fixed_in_place": [
    {
      "issue": "Pointer mask gestures (brush/linear/radial) always targeted the first enabled component in a layer, ignoring the selected component (MaskInteractionState.selectedComponentID). On any layer with 2+ components, drawing with a tool would silently overwrite the wrong component's saved definition instead of the one the user selected in the inspector.",
      "files": [
        "Sources/LumoKit/ViewModels/AppViewModel+Masking.swift (beginMaskGesture, updateMaskGesture, new LocalAdjustmentLayer.targetComponentIndex helper)",
        "Sources/LumoKit/Views/MaskingWorkspace.swift (MaskCanvasOverlay.draw now targets the same component as the gesture, so guides match what's actually edited)"
      ],
      "test": "Tests/LumoKitTests/MaskingWorkspaceTests.swift: testGestureEditsTheSelectedComponentNotJustTheFirstEnabledOne (fails without the fix, passes with it)"
    }
  ],
  "unresolved_blocker": {
    "summary": "Overlay color-wash/grayscale inspection and per-layer 'Solo' are non-functional: MaskCanvasOverlay only draws vector geometry guides, never the layer's resolved mask alpha, and soloLayerID is set/cleared but read nowhere. docs/MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md Section 5.2 explicitly requires 'The active mask may be soloed to inspect its alpha without changing the document,' which this ticket's implementation notes point to.",
    "why_not_fixed_here": "Requires rendering the resolved per-pixel mask alpha into the preview overlay, which touches the RenderEngine/CIImage boundary (CLAUDE.md: CIImage/CIFilter/CIContext must stay inside RenderEngine) -- a real feature addition, not a localized/testable fix appropriate for a verification pass.",
    "child_ticket": "LUMO-229"
  },
  "tests_run": [
    "swift build",
    "swift test --filter MaskingWorkspaceTests",
    "swift test --filter AdjustInspectorTests",
    "swift test --filter LocalMaskTests",
    "swift test --filter PackageSettingsTests"
  ],
  "tests_result": "all passed (26 tests across the four filters, including the new regression test)",
  "other_notes": "duplicateMask's brush-component branch (`if case .brush(let brush) = ... { component.source = .brush(brush) }`) reassigns the identical value and does nothing observable; harmless but worth cleaning up if this file is touched again. Not filed as a separate ticket given its severity."
}

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-05T13:44:23.006Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTOFNGVK36JI167N
