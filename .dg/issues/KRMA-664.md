---
id: KRMA-664
title: Add optional wire refinement for rough retouch strokes
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Add a cancellable wire-refinement step that analyzes a committed rough stroke corridor and snaps the region centerline to the thin dark/light ridge consistent with the surrounding wire evidence, then tightens width to the wire. Preserve endpoints and bends where supported; reject ambiguous corridors rather than warping the stroke unpredictably.
      result: pass
      notes: RetouchWireRefiner.refine (Sources/KromoraKit/Models/RetouchAnalysis/RetouchWireRefiner.swift) walks the resampled brush corridor, scores a polarity-agnostic ridge response against both flanks, recenters on connected ridge support, and rejects via .ambiguous/.invalidInput when evidence is weak, a second competing ridge is present, or polarity/contrast medians fail. Cancellation is polled per corridor sample via isCancelled and surfaced as .cancelled. Sagging/bend test (testSaggingLowContrastWireCrossesAHorizontalEdgeAndPreservesBend) confirms bend tracking through a horizontal edge crossing.
    - criterion: Keep the refined region editable and show its proposed boundary before acceptance, with a clear way to keep the original brush region or undo the refinement. Accepted geometry uses the standard RetouchRegion and Remove fill path.
      result: pass
      notes: RetouchInteractionState tracks isRefiningWire/wireProposal/wireProposalSpotID separately from the committed document; RetouchCanvasOverlay draws the proposed boundary only while the proposal's spot is selected; RetouchInspectorView offers Keep Brush Region (cancelWireRefinement) vs Accept Refinement (acceptWireRefinement), which only then writes proposal.region into the existing RetouchRegion/RetouchSpot via the normal updateDocument path. Found and fixed one bug in this area during verification (see fixes).
    - criterion: Test straight and sagging 1-8 px wires, deliberate overspray, crossings over roof/branch/horizon edges, low-contrast wires, and ambiguous textured backgrounds using KRMA-658 ground truth. Report when refinement improves wire cases and ensure it does not regress ordinary dust/speck removal.
      result: pass
      notes: "RetouchWireRefinerTests covers straight/sagging/1-8px widths with deliberate overspray, a low-contrast sagging wire crossing a horizontal roof-like edge, an ambiguous textured-background rejection, cancellation, and single-point dust ineligibility. testKRMA658WireFixturesReportAcceptedAndImprovedCases runs the real KRMA-658 fixtures: 5/12 wire corridors accepted with centerline error 3.93px to 0.59px, 7/12 correctly declined as ambiguous; re-ran and reproduced identical numbers. Wire refinement is opt-in per spot (Refine to Wire button) and does not touch dust/speck spots (ineligible below 2 samples), so ordinary Heal/Clone/dust behavior is unchanged; full RetouchQualityEvaluationTests corpus still passes unrelated to this change."
    - criterion: Record limitations and measured quality in docs/RETOUCH.md; keep this optional and do not make completion of wire refinement a dependency for baseline Remove unless the product workflow deliberately adopts it later.
      result: pass
      notes: docs/RETOUCH.md 'Optional wire refinement' section documents the analysis approach, the accepted/rejected KRMA-658 measurements (5/12 accepted, 3.93px to 0.59px), the 1-8px and sagging/edge-crossing synthetic results, and states these are centerline measurements only, not Remove fill-quality claims. The feature is gated behind an explicit per-spot action and RetouchSpot/Remove baseline behavior is unmodified when declined or unused.
  checks_run:
    - swift build (clean, 0 errors, before and after fix)
    - swift test --filter 'RetouchWire|PatchMatch|RetouchWorkflow' (20 tests, 0 failures, before and after fix)
    - dg validate (OK; only pre-existing unrelated agent-model-name warnings)
    - git diff --check on the implementation commit (clean)
  findings:
    - "[correctness, fixed] RetouchInspectorView.swift: the 'Cancel Wire Refinement' button was gated only on the global interaction.isRefiningWire flag, not on whether the currently selected spot was the one actually being refined. Selecting a different eligible Remove spot while another spot's refinement was in flight showed a 'Cancel Wire Refinement' button that actually cancelled the other spot's analysis, which is confusing but does not corrupt document state (the canvas overlay itself correctly gates on wireProposalSpotID == selectedSpotID). Fixed by also requiring interaction.wireProposalSpotID == spot.id to show the cancel action."
    - "[performance, fixed] RetouchWorkflowCoordinator.refineSelectedSpotToWire only cancelled the wrapping wireRefinementTask, not the Task.detached wireAnalysisTask doing the actual corridor walk; since detached tasks do not inherit cancellation from their spawning task, re-invoking refine while a prior analysis was still running left the old detached analysis running to completion untracked. Not reachable through the shipped UI in its pre-fix form (the cancel-button gating above prevented a second concurrent invocation through normal clicks), but fixed defensively by also cancelling wireAnalysisTask at the start of refineSelectedSpotToWire so re-entry is safe."
  fixes:
    - "Sources/KromoraKit/Views/RetouchInspectorView.swift: scope the Cancel Wire Refinement button to the spot whose id matches wireProposalSpotID."
    - "Sources/KromoraKit/ViewModels/RetouchWorkflowCoordinator.swift: cancel wireAnalysisTask (not just wireRefinementTask) when refineSelectedSpotToWire starts a new refinement."
  verification_commits:
    - 9dd9ae8
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T23:39:19.301Z
  session: 01MUKGIIUV03EPUBVJ
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - retouch
  - remove-heal-clone
created: 2026-09-27T18:53:56.738Z
updated: 2026-09-27T23:39:19.303Z
parent: KRMA-599
depends_on:
  - KRMA-661
  - KRMA-665
blockers: []
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/Models/RetouchAnalysis/
    - Sources/KromoraKit/Models/RetouchWorkflowCoordinator.swift
    - Sources/KromoraKit/Views/RetouchCanvasOverlay.swift
  docs:
    - .context/2026-09-27-heal-remove-plan.md
    - docs/RETOUCH.md
  issues:
    - KRMA-658
    - KRMA-661
    - KRMA-662
    - KRMA-665
  commands:
    - swift test --filter 'RetouchWire|PatchMatch|RetouchWorkflow'
    - dg validate
commits:
  - 9dd9ae8
---

## Objective

Offer optional “Refine to wire” analysis that narrows a rough brush corridor onto a thin linear
defect while preserving the photographer's intended path.

## Context

Thin wires are in scope for high-quality Remove, but freehand input can be wider or less precise
than a 1–8 px wire. This is explicitly a stretch phase after the base brush and Remove solver;
ordinary strokes must continue to work when refinement is unavailable or declined. Do not expand
the feature into generic object selection or large-object inpainting.

## Acceptance criteria

- [ ] Add a cancellable wire-refinement step that analyzes a committed rough stroke corridor and
      snaps the region centerline to the thin dark/light ridge consistent with the surrounding
      wire evidence, then tightens width to the wire. Preserve endpoints and bends where supported;
      reject ambiguous corridors rather than warping the stroke unpredictably.
- [ ] Keep the refined region editable and show its proposed boundary before acceptance, with a
      clear way to keep the original brush region or undo the refinement. Accepted geometry uses
      the standard RetouchRegion and Remove fill path.
- [ ] Test straight and sagging 1–8 px wires, deliberate overspray, crossings over roof/branch/
      horizon edges, low-contrast wires, and ambiguous textured backgrounds using KRMA-658 ground
      truth. Report when refinement improves wire cases and ensure it does not regress ordinary
      dust/speck removal.
- [ ] Record limitations and measured quality in `docs/RETOUCH.md`; keep this optional and do not
      make completion of wire refinement a dependency for baseline Remove unless the product
      workflow deliberately adopts it later.

## Implementation notes

This phase is a stretch goal and should be picked up only after KRMA-661's brush and KRMA-662's
Remove solver and KRMA-665's engine integration are stable. No generative or Core ML model and no large-object removal scope.

### Comment — codex @ 2026-09-27T23:35:31.648Z

Implemented optional, cancellable Refine to Wire for multi-sample Remove strokes. The proposed ridge boundary remains separate until acceptance; users can keep the original brush geometry, and accepted geometry is stored as a normal RetouchRegion. Single-point dust/speck spots remain ineligible. KRMA-658 generated-fixture measurement: accepted 5/12 oversprayed wire corridors, reducing mean centerline error from 3.93 px to 0.59 px in all accepted cases; ambiguous cases were declined. Synthetic 1–8 px wires and sagging edge-crossing wire tests pass. Checks: swift test --filter 'RetouchWire|PatchMatch|RetouchWorkflow' (20 tests, 0 failures), swift build, dg validate (OK; existing model-name warnings), git diff --check. Commit: 5481f2b.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-27T23:39:19.301Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Add a cancellable wire-refinement step that analyzes a committed rough stroke corridor and snaps the region centerline to the thin dark/light ridge consistent with the surrounding wire evidence, then tightens width to the wire. Preserve endpoints and bends where supported; reject ambiguous corridors rather than warping the stroke unpredictably. (pass) — RetouchWireRefiner.refine (Sources/KromoraKit/Models/RetouchAnalysis/RetouchWireRefiner.swift) walks the resampled brush corridor, scores a polarity-agnostic ridge response against both flanks, recenters on connected ridge support, and rejects via .ambiguous/.invalidInput when evidence is weak, a second competing ridge is present, or polarity/contrast medians fail. Cancellation is polled per corridor sample via isCancelled and surfaced as .cancelled. Sagging/bend test (testSaggingLowContrastWireCrossesAHorizontalEdgeAndPreservesBend) confirms bend tracking through a horizontal edge crossing.
- [x] Keep the refined region editable and show its proposed boundary before acceptance, with a clear way to keep the original brush region or undo the refinement. Accepted geometry uses the standard RetouchRegion and Remove fill path. (pass) — RetouchInteractionState tracks isRefiningWire/wireProposal/wireProposalSpotID separately from the committed document; RetouchCanvasOverlay draws the proposed boundary only while the proposal's spot is selected; RetouchInspectorView offers Keep Brush Region (cancelWireRefinement) vs Accept Refinement (acceptWireRefinement), which only then writes proposal.region into the existing RetouchRegion/RetouchSpot via the normal updateDocument path. Found and fixed one bug in this area during verification (see fixes).
- [x] Test straight and sagging 1-8 px wires, deliberate overspray, crossings over roof/branch/horizon edges, low-contrast wires, and ambiguous textured backgrounds using KRMA-658 ground truth. Report when refinement improves wire cases and ensure it does not regress ordinary dust/speck removal. (pass) — RetouchWireRefinerTests covers straight/sagging/1-8px widths with deliberate overspray, a low-contrast sagging wire crossing a horizontal roof-like edge, an ambiguous textured-background rejection, cancellation, and single-point dust ineligibility. testKRMA658WireFixturesReportAcceptedAndImprovedCases runs the real KRMA-658 fixtures: 5/12 wire corridors accepted with centerline error 3.93px to 0.59px, 7/12 correctly declined as ambiguous; re-ran and reproduced identical numbers. Wire refinement is opt-in per spot (Refine to Wire button) and does not touch dust/speck spots (ineligible below 2 samples), so ordinary Heal/Clone/dust behavior is unchanged; full RetouchQualityEvaluationTests corpus still passes unrelated to this change.
- [x] Record limitations and measured quality in docs/RETOUCH.md; keep this optional and do not make completion of wire refinement a dependency for baseline Remove unless the product workflow deliberately adopts it later. (pass) — docs/RETOUCH.md 'Optional wire refinement' section documents the analysis approach, the accepted/rejected KRMA-658 measurements (5/12 accepted, 3.93px to 0.59px), the 1-8px and sagging/edge-crossing synthetic results, and states these are centerline measurements only, not Remove fill-quality claims. The feature is gated behind an explicit per-spot action and RetouchSpot/Remove baseline behavior is unmodified when declined or unused.
Checks run:
- swift build (clean, 0 errors, before and after fix)
- swift test --filter 'RetouchWire|PatchMatch|RetouchWorkflow' (20 tests, 0 failures, before and after fix)
- dg validate (OK; only pre-existing unrelated agent-model-name warnings)
- git diff --check on the implementation commit (clean)
Findings:
- [correctness, fixed] RetouchInspectorView.swift: the 'Cancel Wire Refinement' button was gated only on the global interaction.isRefiningWire flag, not on whether the currently selected spot was the one actually being refined. Selecting a different eligible Remove spot while another spot's refinement was in flight showed a 'Cancel Wire Refinement' button that actually cancelled the other spot's analysis, which is confusing but does not corrupt document state (the canvas overlay itself correctly gates on wireProposalSpotID == selectedSpotID). Fixed by also requiring interaction.wireProposalSpotID == spot.id to show the cancel action.
- [performance, fixed] RetouchWorkflowCoordinator.refineSelectedSpotToWire only cancelled the wrapping wireRefinementTask, not the Task.detached wireAnalysisTask doing the actual corridor walk; since detached tasks do not inherit cancellation from their spawning task, re-invoking refine while a prior analysis was still running left the old detached analysis running to completion untracked. Not reachable through the shipped UI in its pre-fix form (the cancel-button gating above prevented a second concurrent invocation through normal clicks), but fixed defensively by also cancelling wireAnalysisTask at the start of refineSelectedSpotToWire so re-entry is safe.
Fixes:
- Sources/KromoraKit/Views/RetouchInspectorView.swift: scope the Cancel Wire Refinement button to the spot whose id matches wireProposalSpotID.
- Sources/KromoraKit/ViewModels/RetouchWorkflowCoordinator.swift: cancel wireAnalysisTask (not just wireRefinementTask) when refineSelectedSpotToWire starts a new refinement.
Verification commits:
- 9dd9ae8
Actor: claude
Resolved model: sonnet
Pickup session: 01MUKGIIUV03EPUBVJ
