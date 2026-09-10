---
id: KRMA-242
title: Use the demonstrated Person or Subject result in Info as an editing mask
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The Info pane exposes a clearly labeled action for using the demonstrated Person result as an editing mask, and the Subject result where supported.
      result: pass
      notes: PhotoAnalysisInspectSection.infoEditingMaskAction renders a "Use <Title> as editing mask" button for .subject/.person entries (AnalysisDebugPanel.swift).
    - criterion: Invoking the action creates or reuses the corresponding semantic mask for the active photo, selects it in the Masking workflow, and does not create duplicate masks on repeated activation.
      result: pass
      notes: AppViewModel.useInfoAnalysisMask looks up an existing component by SemanticTarget before creating a new layer; testInfoAnalysisMaskCreatesAndReusesTheDemonstratedSemanticMask asserts a second invocation leaves localAdjustments.count == 1.
    - criterion: A local adjustment applied through the resulting mask changes the expected Person/Subject pixels in preview and export; invert, enable/disable, amount, solo, and overlay continue to use the shared mask semantics.
      result: pass
      notes: The created recipe is the ordinary .semantic(SemanticMaskDefinition(target:)) MaskSource, so it goes through the existing shared render/overlay path; InfoSemanticMaskRenderingTests confirms preview/export pixel parity for both targets.
    - criterion: The action communicates loading, unavailable, unsupported-source, and analysis-failure states clearly and never creates an inert successful-looking mask.
      result: pass
      notes: useInfoAnalysisMask validates assetID/fingerprint/kind/pixel-size/coverage/MaskPresentationPolicy before creating anything and reports a message via markMaskUnavailable otherwise; AnalysisDebugPanel shows loading/providerError/unavailable states via editingMaskUnavailableMessage. Added a new test for the low-confidence rejection path (MaskPresentationPolicy != .actionable) that was previously untested.
    - criterion: The existing Info-pane visualization remains available, while the editing-mask action uses the shared analysis/provider result rather than launching a divergent debug-only path.
      result: pass
      notes: onUseEditingMask passes the already-fetched entry.mask/entry.pixels through to the view model; no second inference path is started.
    - criterion: The mask is persisted with the active photo, survives reopening, and is isolated correctly when switching to another source.
      result: pass
      notes: testInfoAnalysisMaskCreatesAndReusesTheDemonstratedSemanticMask covers flushPendingWrites + reopen and source-switch isolation.
    - criterion: Add regression coverage for Person and Subject creation/reuse, local-adjustment rendering, persistence, source switching, and unavailable-analysis behavior.
      result: pass
      notes: Existing tests covered creation/reuse/rendering/persistence/source-switch and a stale-source rejection; added testInfoAnalysisMaskRejectsALowConfidenceResultWithoutCreatingARecipe to close the remaining unavailable-analysis (MaskPresentationPolicy) gap.
  checks_run:
    - swift build
    - swift test --filter "InfoSemanticMaskRenderingTests|MaskingWorkspaceTests" (27 passed, 0 failures)
    - "swift test (full deterministic lane, before fix: 902 passed, 42 expected skips; after adding coverage: 903 passed, 42 expected skips, 0 failures)"
    - Manual read of AppViewModel+Masking.useInfoAnalysisMask, AnalysisDebugPanel.infoEditingMaskAction, and InfoInspectorView wiring against RegionMask/RegionMaskReference/MaskPresentationPolicy invariants
  findings:
    - "informational: the guard in useInfoAnalysisMask includes `result.reference.quality == result.quality`, which is always true given RegionMaskReference's init (quality is derived from the same value used to build the reference); harmless dead invariant, not worth a fix."
    - "informational: the working tree at claim time already contained unrelated, uncommitted changes to CanvasNavigation/MaskInteractionState/AppViewModel+Masking (linear-gradient two-stage creation) and their tests, pre-dating this verification session and touching none of the LUMO-242 files. Left untouched per verification scope; flagged since it means the tree was not clean before this ticket was picked up."
  fixes:
    - Added testInfoAnalysisMaskRejectsALowConfidenceResultWithoutCreatingARecipe to MaskingWorkspaceTests.swift, closing the unavailable-analysis (MaskPresentationPolicy rejection) regression gap; test-only, no behavior change.
  verification_commits:
    - 4623a3d
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-06T06:10:13.614Z
  session: 01MTPEJMFBMJ1AOOT0
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - masking
  - analysis
  - editor
  - epic:masking
created: 2026-09-06T03:37:57.301Z
updated: 2026-09-10T12:53:50.011Z
order: fp20kqfd
board: product
commits:
  - 4623a3d
---

## Objective

Let users turn the already demonstrated Person or Subject result in the Info pane into a persistent
editing mask.

## Context

The Info pane already demonstrates a Person/Subject analysis result, but that result cannot be used
directly to drive a local edit. Users should not have to rediscover or recreate the same analysis in
another workflow just to adjust the detected person or subject.

### Reproduction

1. Open a photo with a detectable person or subject.
2. Open the Info pane and view the demonstrated Person/Subject result.
3. Try to use that result as the target of a local adjustment, or to add it to the masking workflow.

### Observed

The Info pane result is presentation-only; there is no clear action to select Person/Subject as an
editing mask and no durable mask is created from the demonstrated result.

### Expected

The Info pane should provide a clear action to use Person or Subject as an editing mask. The action
should create/select a durable semantic mask for the active photo and hand it off to the normal
masking/local-adjustment workflow.

## Acceptance criteria

- [ ] The Info pane exposes a clearly labeled action for using the demonstrated Person result as an
      editing mask, and the Subject result where supported.
- [ ] Invoking the action creates or reuses the corresponding semantic mask for the active photo,
      selects it in the Masking workflow, and does not create duplicate masks on repeated activation.
- [ ] A local adjustment applied through the resulting mask changes the expected Person/Subject
      pixels in preview and export; invert, enable/disable, amount, solo, and overlay continue to
      use the shared mask semantics.
- [ ] The action communicates loading, unavailable, unsupported-source, and analysis-failure states
      clearly and never creates an inert successful-looking mask.
- [ ] The existing Info-pane visualization remains available, while the editing-mask action uses
      the shared analysis/provider result rather than launching a divergent debug-only path.
- [ ] The mask is persisted with the active photo, survives reopening, and is isolated correctly
      when switching to another source.
- [ ] Add regression coverage for Person and Subject creation/reuse, local-adjustment rendering,
      persistence, source switching, and unavailable-analysis behavior.

## Implementation notes

Coordinate the Info-pane entry point with KRMA-201, KRMA-220, KRMA-238, and the provider work in
KRMA-184/KRMA-187/KRMA-188/KRMA-191. Reuse the existing demonstrated analysis result and the
persistent mask/document ownership seams; do not duplicate semantic inference or make the Info
pane a second mask editor.

### Comment — codex @ 2026-09-06T05:59:33.601Z

Implemented the Info-pane Person/Subject editing-mask handoff. The shared demonstrated result is validated for active source, quality, pixels, and presentation; actionable results create or reuse and select one persisted semantic mask, while stale/unavailable results remain non-editable with visible recovery messaging. Added persistence/source-switch, stale-result, duplicate-reuse, and Person/Subject preview/export regression coverage. Verification: swift test — 902 passed, 42 expected skips.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-06T06:10:13.615Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The Info pane exposes a clearly labeled action for using the demonstrated Person result as an editing mask, and the Subject result where supported. (pass) — PhotoAnalysisInspectSection.infoEditingMaskAction renders a "Use <Title> as editing mask" button for .subject/.person entries (AnalysisDebugPanel.swift).
- [x] Invoking the action creates or reuses the corresponding semantic mask for the active photo, selects it in the Masking workflow, and does not create duplicate masks on repeated activation. (pass) — AppViewModel.useInfoAnalysisMask looks up an existing component by SemanticTarget before creating a new layer; testInfoAnalysisMaskCreatesAndReusesTheDemonstratedSemanticMask asserts a second invocation leaves localAdjustments.count == 1.
- [x] A local adjustment applied through the resulting mask changes the expected Person/Subject pixels in preview and export; invert, enable/disable, amount, solo, and overlay continue to use the shared mask semantics. (pass) — The created recipe is the ordinary .semantic(SemanticMaskDefinition(target:)) MaskSource, so it goes through the existing shared render/overlay path; InfoSemanticMaskRenderingTests confirms preview/export pixel parity for both targets.
- [x] The action communicates loading, unavailable, unsupported-source, and analysis-failure states clearly and never creates an inert successful-looking mask. (pass) — useInfoAnalysisMask validates assetID/fingerprint/kind/pixel-size/coverage/MaskPresentationPolicy before creating anything and reports a message via markMaskUnavailable otherwise; AnalysisDebugPanel shows loading/providerError/unavailable states via editingMaskUnavailableMessage. Added a new test for the low-confidence rejection path (MaskPresentationPolicy != .actionable) that was previously untested.
- [x] The existing Info-pane visualization remains available, while the editing-mask action uses the shared analysis/provider result rather than launching a divergent debug-only path. (pass) — onUseEditingMask passes the already-fetched entry.mask/entry.pixels through to the view model; no second inference path is started.
- [x] The mask is persisted with the active photo, survives reopening, and is isolated correctly when switching to another source. (pass) — testInfoAnalysisMaskCreatesAndReusesTheDemonstratedSemanticMask covers flushPendingWrites + reopen and source-switch isolation.
- [x] Add regression coverage for Person and Subject creation/reuse, local-adjustment rendering, persistence, source switching, and unavailable-analysis behavior. (pass) — Existing tests covered creation/reuse/rendering/persistence/source-switch and a stale-source rejection; added testInfoAnalysisMaskRejectsALowConfidenceResultWithoutCreatingARecipe to close the remaining unavailable-analysis (MaskPresentationPolicy) gap.
Checks run:
- swift build
- swift test --filter "InfoSemanticMaskRenderingTests|MaskingWorkspaceTests" (27 passed, 0 failures)
- swift test (full deterministic lane, before fix: 902 passed, 42 expected skips; after adding coverage: 903 passed, 42 expected skips, 0 failures)
- Manual read of AppViewModel+Masking.useInfoAnalysisMask, AnalysisDebugPanel.infoEditingMaskAction, and InfoInspectorView wiring against RegionMask/RegionMaskReference/MaskPresentationPolicy invariants
Findings:
- informational: the guard in useInfoAnalysisMask includes `result.reference.quality == result.quality`, which is always true given RegionMaskReference's init (quality is derived from the same value used to build the reference); harmless dead invariant, not worth a fix.
- informational: the working tree at claim time already contained unrelated, uncommitted changes to CanvasNavigation/MaskInteractionState/AppViewModel+Masking (linear-gradient two-stage creation) and their tests, pre-dating this verification session and touching none of the KRMA-242 files. Left untouched per verification scope; flagged since it means the tree was not clean before this ticket was picked up.
Fixes:
- Added testInfoAnalysisMaskRejectsALowConfidenceResultWithoutCreatingARecipe to MaskingWorkspaceTests.swift, closing the unavailable-analysis (MaskPresentationPolicy rejection) regression gap; test-only, no behavior change.
Verification commits:
- 4623a3d
Actor: claude
Resolved model: sonnet
Pickup session: 01MTPEJMFBMJ1AOOT0
Summary: Independent verification passed: the Info-pane Person/Subject editing-mask handoff creates/reuses one durable semantic mask, renders correctly in preview and export, persists and is isolated per source, and reports unavailable/stale states without leaving an inert mask. Added regression coverage for the one remaining gap (MaskPresentationPolicy rejection). Full suite green (903 passed, 42 expected skips, 0 failures).
