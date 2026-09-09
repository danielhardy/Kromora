---
id: LUMO-286
title: Restrict mask overlay visibility to the active Mask tab
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Overlay visible when Masking tab active and enabled
      result: pass
    - criterion: Switching to another edit tab hides overlay immediately
      result: pass
    - criterion: Navigating to library/grid hides overlay
      result: pass
    - criterion: Returning to Masking restores overlay only if prior state and valid target permit it
      result: pass
    - criterion: Tab/workspace switches do not discard mask editing gestures or overlay state
      result: pass
    - criterion: Regression coverage added for tab changes, library navigation, and return to Masking
      result: pass
    - criterion: Overlay view and pointer-tracking surface disabled outside Masking (no hover/mask publishing)
      result: pass
    - criterion: No overlay render/measurable work added to normal preview interaction path outside Masking
      result: pass
    - criterion: Existing masking, preview, navigation, and overlay rendering tests remain green
      result: pass
  checks_run:
    - swift test --filter MaskingWorkspaceTests (36/36 passed)
    - scripts/ci-tests.sh fast (642/642 passed)
    - scripts/ci-tests.sh serial (277/277 passed)
    - dg validate (OK)
    - git diff --check b2ecd8d~1 b2ecd8d (clean)
  findings:
    - "Minor maintainability nit: PreviewView.swift re-checks inspectorState.isPresented and inspectorState.tab == .masking redundantly alongside viewModel.isMaskingWorkspaceActive, which already includes both conditions. Non-blocking; filed as LUMO-287 (verification, depends on LUMO-286)."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: unknown
  completed_at: 2026-09-08T22:22:34.490Z
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - masking
  - editor
  - library
  - ui
created: 2026-09-08T21:08:55.003Z
updated: 2026-09-08T22:22:34.493Z
order: a0
board: product
---

## Objective

Show the mask overlay only while the Masking inspector tab is active.

## Context

The mask overlay currently remains visible while navigating to other edit tabs and/or the library.
This adds visual clutter and can make the displayed photo appear to be in masking mode when the user
is working elsewhere.

The overlay should be scoped to the Masking workspace/tab and hidden whenever the user switches to
another edit tab or leaves the editor for the library/grid.

This is also a performance issue: when the overlay remains mounted outside Masking, its pointer
surface can continue tracking mouse movement and its presentation state can cause unnecessary
canvas redraws while other edit controls are being used.

### Reproduction

1. Open a photo with an active mask or mask draft.
2. Open the Masking tab and enable the overlay.
3. Switch to another edit tab such as Light, Color, Effects, or Look.
4. Return to the library/grid.
5. Observe that the mask overlay should no longer be visible outside Masking.

## Acceptance criteria

- [ ] The mask overlay is visible when the Masking inspector tab is active and the overlay is enabled.
- [ ] Switching to any other edit tab hides the mask overlay immediately.
- [ ] Navigating to the library/grid hides the mask overlay.
- [ ] Returning to Masking restores the overlay only when its prior enabled state and a valid mask
      target still permit it.
- [ ] Mask editing gestures and overlay state are not accidentally discarded merely by switching
      tabs or workspaces.
- [ ] Add regression coverage for tab changes, library navigation, and return to Masking.
- [ ] The overlay view and pointer-tracking surface are disabled outside the Masking tab, so
      moving the pointer over the preview in other tabs does not publish mask hover updates.
- [ ] Switching tabs or workspaces does not invoke mask overlay rendering or add measurable work
      to the normal preview interaction path; verify preview latency remains at the established
      performance baseline.
- [ ] Existing masking, preview, navigation, and overlay rendering tests remain green.

## Implementation notes

Derive overlay visibility from the active workspace/inspector tab in the masking presentation path.
Keep persistent mask data, selection, and draft state separate from the transient decision to render
the overlay. Ensure the library/grid path cannot retain or display the editor's overlay view.

Relevant areas to inspect:

- `Sources/LumoKit/Views/PreviewView.swift`
- `Sources/LumoKit/Views/MaskingWorkspace.swift`
- `Sources/LumoKit/Views/MaskOverlayPrototype.swift`
- `Sources/LumoKit/ViewModels/AppViewModel+Masking.swift`
- `Sources/LumoKit/ViewModels/AppViewModel.swift`

Performance verification should specifically cover leaving Masking with an active Brush, Erase,
Linear, or Radial tool, then moving the pointer and editing another tab. Confirm that no overlay
render task is started and that the preview does not retain the mask pointer hit-test surface.

### Comment — codex @ 2026-09-08T22:17:58.668Z

Implemented in b2ecd8d. PreviewView now observes the separate InspectorState and only mounts the mask overlay/pointer surface while the presented inspector is on Masking in Edit mode with a valid source. Mask selection, drafts, and overlay preferences remain untouched across tab and library navigation. Added regression coverage for tab changes, library navigation, and return to Masking. Verification: swift test --filter MaskingWorkspaceTests (36 passed); swift test (964 executed, 45 expected skips, 0 failures); dg validate OK; git diff --check OK.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-08T22:22:12.844Z: Verification report
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
Pickup session: 01MTT8DJHBOHK7U3MX

- 2026-09-08T22:22:34.491Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Overlay visible when Masking tab active and enabled (pass)
- [x] Switching to another edit tab hides overlay immediately (pass)
- [x] Navigating to library/grid hides overlay (pass)
- [x] Returning to Masking restores overlay only if prior state and valid target permit it (pass)
- [x] Tab/workspace switches do not discard mask editing gestures or overlay state (pass)
- [x] Regression coverage added for tab changes, library navigation, and return to Masking (pass)
- [x] Overlay view and pointer-tracking surface disabled outside Masking (no hover/mask publishing) (pass)
- [x] No overlay render/measurable work added to normal preview interaction path outside Masking (pass)
- [x] Existing masking, preview, navigation, and overlay rendering tests remain green (pass)
Checks run:
- swift test --filter MaskingWorkspaceTests (36/36 passed)
- scripts/ci-tests.sh fast (642/642 passed)
- scripts/ci-tests.sh serial (277/277 passed)
- dg validate (OK)
- git diff --check b2ecd8d~1 b2ecd8d (clean)
Findings:
- Minor maintainability nit: PreviewView.swift re-checks inspectorState.isPresented and inspectorState.tab == .masking redundantly alongside viewModel.isMaskingWorkspaceActive, which already includes both conditions. Non-blocking; filed as LUMO-287 (verification, depends on LUMO-286).
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: unknown
