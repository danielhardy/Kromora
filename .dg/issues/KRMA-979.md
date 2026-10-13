---
id: KRMA-979
title: "Observation step 8: Extract white-balance, capabilities and Auto state"
type: task
status: backlog
priority: medium
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - swiftui
created: 2026-10-13T19:37:00.980Z
updated: 2026-10-13T19:37:01.899Z
depends_on:
  - KRMA-978
blockers: []
order: zzzzzq
board: product
---

## Objective

Extract the white-balance sampler, RAW capability, Auto-adjustment and LUT-resolution state into `@Observable` objects so they stop invalidating the root. The loupe image and sampler point change at pointer rate and must not touch any view except the canvas.

## Context

Part of `docs/APP_VIEWMODEL_OBSERVATION_PLAN.md` (read it, "Additions from ticket review" and "Common rules"). Depends on KRMA-978.

Nine properties (declarations in `AppViewModel.swift`, regenerate line numbers):

| Group | Property | Decl | Direct readers |
| --- | --- | --- | --- |
| White balance | `isWhiteBalanceSampling: Bool` | ~L137 | `ColorInspectorView`, `PreviewView` |
| White balance | `whiteBalanceSamplerPoint: CGPoint?` | ~L138 | `PreviewView` |
| White balance | `whiteBalanceLoupeImage: CGImage?` | ~L139 | `PreviewView` |
| Capabilities | `rawCapabilities: RAWCapabilities?` | ~L227 | `ColorInspectorView`, `DevelopInspectorView` |
| Capabilities | `capabilitiesProbeCompleted: Bool` | ~L232 | none directly |
| Capabilities | `editStoreStatus: String?` | ~L203 | none directly |
| Auto | `autoAdjustmentState` | ~L664 | none directly |
| Auto | `autoAdjustmentProgress: Double?` | ~L669 | `StatusBar` |
| Look | `lutResolutionStatus: String?` | ~L432 | `LookInspectorView` |

**Decision made here: `editStoreStatus` moves with the capability state** (call the class `EditorCapabilityState` or similar). It has no view reader and is a storage/probe status, and moving it is what lets step 9's structural assertion about the exact remaining `@Published` set hold.

Grouping to implement (three objects, per the original plan):
1. `WhiteBalanceSamplerState`: sampling flag, point, loupe image.
2. `EditorCapabilityState`: `rawCapabilities`, `capabilitiesProbeCompleted`, `editStoreStatus`.
3. `AutoLookStatusState`: `autoAdjustmentState`, `autoAdjustmentProgress`, `lutResolutionStatus`.

Writers: grep `Sources/KromoraKit/ViewModels/` (`PhotoAnalysisCoordinator`, `PreviewCoordinator`, `AppViewModel` and its extensions, `LookSelectionCoordinator`) for each name; coordinators typically write through closures defined in `AppViewModel`, so most edits are inside `AppViewModel.swift`. There are also helper methods such as `publishAutoAdjustmentState(...)` (used at ~L1440 in the preview-failure handler); keep those method names so call sites do not move.

Pointer-rate caveat: `whiteBalanceSamplerPoint` and `whiteBalanceLoupeImage` update during mouse movement. After this step only `PreviewView`'s loupe subtree should read them. If `PreviewView.body` reads them at the top level, the whole preview view re-evaluates per pointer move. Move those reads into a small child view that takes the sampler state object, so only that child re-evaluates.

## Approach

1. Create the three `@MainActor @Observable final class`es in `Sources/KromoraKit/ViewModels/`; keep `private(set)` where the original has it and add intent-named mutators.
2. `AppViewModel` holds `let whiteBalance`, `let capabilities`, `let autoLook` (names to taste) and removes the nine `@Published`s. Re-point writers. No behavioural changes.
3. Convert readers. `ColorInspectorView`: only the sampling toggle and capabilities read these; keep non-sampling subviews independent of the sampler state.
4. Keep the mask/overlay and loupe rendering identical; this is a state move.

## Acceptance criteria

- [ ] Three `@Observable` state objects own all nine properties; `AppViewModel` has `let` references only (structural test: `@Published` count drops by 9 relative to step 7's result, from 18 to 9).
- [ ] After this step the exact set of remaining `@Published` on `AppViewModel` is `document`, `sourceImage`, `sourceName`, `sourceSize`, `sourceURL`, `navigation`, `presentation`, `isShowingOriginal`, `isSideBySide`; a structural test asserts exactly that set (name-based scan of the file).
- [ ] Probe test (KRMA-972): changing `whiteBalance.samplerPoint` re-evaluates the PreviewView loupe subtree (or PreviewView mirror) and does not re-evaluate StatusBar or the Color inspector's non-sampling subviews; changing `autoLook.autoAdjustmentProgress` re-evaluates the real StatusBar (`toolbarBodyEvaluations`) and does not re-evaluate inspector mirrors.
- [ ] Fast-lane observation tests for the sampler point and `autoAdjustmentProgress`.
- [ ] Existing white-balance, RAW-capability-probe, Auto and Look-resolution tests pass unchanged (RAW-fixture methods stay in the optional lane and are not required).
- [ ] Update the baseline "after" column for rows touched.
- [ ] `AppViewModel.swift` is not longer than before.

## Verification

```
swift build
scripts/ci-tests.sh fast
scripts/ci-tests.sh serial
```

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
