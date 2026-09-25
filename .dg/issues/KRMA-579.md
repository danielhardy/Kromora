---
id: KRMA-579
title: Pin the histogram above the edit inspector tabs
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Histogram and channel picker pinned above tab control on all tabs; scrolling doesn't move chart/tabs
      result: pass
      notes: "InfoInspectorView.body places histogramSection and tabSwitcher outside the switched Group, which has .frame(maxHeight: .infinity, alignment: .top)."
    - criterion: Info tab no longer contains a second histogram; still shows identity/metadata/analysis and scrolls
      result: pass
      notes: histogramSection removed from infoContent; ScrollView retains identitySection, metadataSection, analysis section.
    - criterion: No image shows empty state with no chart/tabs; Crop still replaces tabbed inspector with no pinned chart
      result: pass
      notes: body branches on isCropToolActive and sourceImage == nil before the pinned histogram/tab block.
    - criterion: Closed inspector tallies nothing
      result: pass
      notes: testNoHistogramIsRenderedWhileTheInspectorIsClosed passes.
    - criterion: Open inspector tallies on Develop and Color, not only Info; old Info-only tests replaced
      result: pass
      notes: testDevelopAndColorEditsUpdateThePinnedHistogram, testSwitchingTabsDoesNotCancelOrRepeatHistogramWork, testTheColorTabUpdatesThePinnedHistogram all pass; old Info-only tests removed.
    - criterion: Switching tabs does not enqueue a new tally when displayed request is unchanged
      result: pass
      notes: testSwitchingTabsDoesNotCancelOrRepeatHistogramWork asserts request count unchanged across tab switches while a job is queued or already completed.
    - criterion: admissionInspectorTabIsInfo removed; revision/asset fences remain
      result: pass
      notes: Grep confirms no remaining references; fences (assetID, sourceRevision, displayRevision) untouched in PreviewAdmissionCoordinator.updateHistogram.
  checks_run:
    - swift build — pass
    - swift test --filter 'DevelopInspectorTests|AdjustInspectorTests|ExportCutoverTests|HistogramTests|PreviewAdmissionCoordinatorTests' — pass (78 passed, 2 RAW-dependent skipped, 0 failures)
    - git diff --check — pass
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-25T06:00:04.697Z
  session: 01MUGJUYPN17UAPO8B
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - ui
  - inspector
  - histogram
created: 2026-09-25T02:44:38.407Z
updated: 2026-09-25T06:00:04.699Z
blockers: []
order: a0
board: product
---

## Objective

Pin the histogram to the top of the edit inspector, above the tab control, on every tab. The chart stays put. The tab body scrolls in the space under it.

Today the chart is a section inside the Info tab's `ScrollView`, under the Photo identity block (`InfoInspectorView.histogramSection`, called from `infoContent`). Light, Color, Develop, Effects, Look, and Masking never show it. Tallying is refused unless `inspectorState.tab == .info`, in both `AppViewModel.refreshHistogramGate` and `PreviewAdmissionCoordinator.updateHistogram` (entry guard and completion fence), through `admissionInspectorTabIsInfo`.

## Layout

In `InfoInspectorView.body`, when an image is open and crop is inactive, the column is:

1. The existing histogram block, pinned. Keep the title, Original/Edited/Graded capsule, 120pt `HistogramChart`, and the RGB / Luma / R / G / B picker. `@State channel` stays on `InfoInspectorView` so the channel survives tab changes.
2. The existing segmented tab control, pinned directly under the chart.
3. The selected tab's body, in the remaining height.

The chart spans the inspector content width (same horizontal inset as the tab control) and is the first content in the column. It is not inside the Info scroll, and it is not inside the tab-switch transition, so changing tabs does not slide it.

Give the tab body `maxHeight: .infinity` so the existing scrollers keep working in the leftover space:

- Info, Light, Color, Develop, Effects, and Masking already use a `ScrollView`.
- Look uses a `List` inside a `VStack` (`LookInspectorView.lookList`). That list has to shrink under the pinned header instead of pushing the chart off the top.

Remove `histogramSection` from `infoContent`. Info still scrolls Photo identity, metadata, and the analysis section.

No image: keep the current empty state. No chart, no tabs.

Crop: `CropInspectorView` still replaces the tabbed inspector for the whole pane. Do not pin the chart above Crop.

## Histogram work

The chart is on screen for every tab, so the Info-tab gate has to go. A closed inspector still does no tally.

- `refreshHistogramGate`: keep the presented-inspector and not-crop checks. Drop `inspectorState.tab == .info`.
- `PreviewAdmissionCoordinator.updateHistogram`: drop `admissionInspectorTabIsInfo` from the entry guard and from the completion fence. Keep the source, asset, and display-revision fences, and keep tallying the settled presented frame (`maxDimension: 512`). Do not rebuild the source graph.
- `InspectorState.tab`'s `didSet` currently calls `onPresentationChange`, which is what restarts or cancels the tally on a tab change. Stop driving the histogram gate from a tab change. `isPresented`'s `didSet` still opens and closes the gate. A tab change must not cancel in-flight work and must not enqueue another tally when the displayed request is unchanged. `updateHistogram` only skips while the same job is still queued; a finished tally would be scheduled again on the next gate refresh.
- Remove `admissionInspectorTabIsInfo` from `PreviewAdmissionDestination`, `AppViewModel`, and the test double in `PreviewAdmissionCoordinatorTests` once nothing reads it.
- Update the comments that say the histogram belongs to the Info tab (`InfoInspectorView` header, `AppViewModel` around the inspector-visibility comment and `updateHistogram`).
- Info's accessibility purpose is "Histogram and photo metadata" (`InspectorTab.purpose`, asserted in `AdjustInspectorTests.testInspectorTabsExposeCompactSymbolsAndAccessiblePurposes`). Histogram is no longer that tab's content. Change the purpose to describe photo name, file type, and metadata, and update the assertion.

Settled-preview coalescing stays. Rapid slider edits still collapse to one tally after the preview settles (`testRapidEditsCoalesceHistogramWorkAfterTheSettledPreview`).

## Acceptance criteria

- [ ] With an image open and the inspector showing, the histogram and its channel picker are pinned above the tab control on Info, Light, Develop, Color, Effects, Look, and Masking. Scrolling a tab does not move the chart or the tab control.
- [ ] The Info tab no longer contains a second histogram. It still shows photo identity, metadata, and analysis, and that content scrolls.
- [ ] No image still shows the empty state, with no chart and no tabs. Crop still replaces the tabbed inspector, with no pinned chart.
- [ ] A closed inspector still tallies nothing (`ExportCutoverTests.testNoHistogramIsRenderedWhileTheInspectorIsClosed`).
- [ ] An open inspector tallies on Develop and Color, not only on Info. Replace `testNoHistogramIsTalliedWhileTheDevelopTabIsShowing`, `testSwitchingBackToInfoRecomputesTheHistogram`, `testLeavingInfoStopsTalliesAndReturningResumesThem`, and `testTheAdjustTabDoesNotTallyAHistogram` so they lock the new rule: an edit on Develop or Color updates the pinned histogram without returning to Info, and leaving Info does not cancel that work.
- [ ] Switching tabs does not enqueue a new tally when the displayed request is unchanged.
- [ ] `admissionInspectorTabIsInfo` is gone, and the revision/asset fences in `updateHistogram` remain.

## Checks

- `swift build`
- `swift test --filter 'DevelopInspectorTests|AdjustInspectorTests|ExportCutoverTests|HistogramTests|PreviewAdmissionCoordinatorTests'`
- `git diff --check`

## Out of scope

Histogram binning, sampling size, or drawing. Auto's separate analyzer. Library grid. Changing Crop's layout or its tally behavior. Comparison still describes the frame on screen (`docs/COMPARISON_MODE.md`).


### Comment — codex @ 2026-09-25T05:58:09.229Z

Pinned the histogram above the inspector tabs, removed it from Info content, and removed the Info-tab tally gate while preserving presentation and revision fences. Updated tab accessibility text and replaced Info-only scheduling tests with Develop, Color, and tab-switch coverage. Verification: swift build; swift test --filter 'DevelopInspectorTests|AdjustInspectorTests|ExportCutoverTests|HistogramTests|PreviewAdmissionCoordinatorTests' (78 passed, 2 RAW-dependent skipped); git diff --check. Commit: 5595c1d.

## Agent log

- 2026-09-25T06:00:04.697Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Histogram and channel picker pinned above tab control on all tabs; scrolling doesn't move chart/tabs (pass) — InfoInspectorView.body places histogramSection and tabSwitcher outside the switched Group, which has .frame(maxHeight: .infinity, alignment: .top).
- [x] Info tab no longer contains a second histogram; still shows identity/metadata/analysis and scrolls (pass) — histogramSection removed from infoContent; ScrollView retains identitySection, metadataSection, analysis section.
- [x] No image shows empty state with no chart/tabs; Crop still replaces tabbed inspector with no pinned chart (pass) — body branches on isCropToolActive and sourceImage == nil before the pinned histogram/tab block.
- [x] Closed inspector tallies nothing (pass) — testNoHistogramIsRenderedWhileTheInspectorIsClosed passes.
- [x] Open inspector tallies on Develop and Color, not only Info; old Info-only tests replaced (pass) — testDevelopAndColorEditsUpdateThePinnedHistogram, testSwitchingTabsDoesNotCancelOrRepeatHistogramWork, testTheColorTabUpdatesThePinnedHistogram all pass; old Info-only tests removed.
- [x] Switching tabs does not enqueue a new tally when displayed request is unchanged (pass) — testSwitchingTabsDoesNotCancelOrRepeatHistogramWork asserts request count unchanged across tab switches while a job is queued or already completed.
- [x] admissionInspectorTabIsInfo removed; revision/asset fences remain (pass) — Grep confirms no remaining references; fences (assetID, sourceRevision, displayRevision) untouched in PreviewAdmissionCoordinator.updateHistogram.
Checks run:
- swift build — pass
- swift test --filter 'DevelopInspectorTests|AdjustInspectorTests|ExportCutoverTests|HistogramTests|PreviewAdmissionCoordinatorTests' — pass (78 passed, 2 RAW-dependent skipped, 0 failures)
- git diff --check — pass
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUGJUYPN17UAPO8B
Summary: Verified: histogram pinned above inspector tabs on all tabs, Info-tab gate removed correctly, tab switches no longer cancel/duplicate tallies. Build, targeted tests (78 pass, 2 RAW-skipped), and git diff --check all pass. No findings.
