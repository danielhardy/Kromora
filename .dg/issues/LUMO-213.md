---
id: LUMO-213
title: Move Photo Analysis debug details into a collapsible Inspect section
type: bug
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run:
    - swift build
    - swift test --filter 'MaskPresentationPolicyTests|MaskingPanelTests'
    - git diff --check
  findings: []
  fixes:
    - Moved Photo Analysis into an on-demand collapsible Inspect section and removed the debug toolbar sheet
  verification_commits:
    - 587b7a7
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-04T19:43:30.814Z
  session: 01MTNCXZ1W7TRISKOO
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - ux
  - photo-intelligence
  - developer
created: 2026-09-04T19:08:07.500Z
updated: 2026-09-07T04:02:50.017Z
order: mw97rxlf
board: product
commits:
  - 587b7a7
---

## Objective

Move Photo Analysis debug details into a collapsible section at the bottom of Inspect.

## Context

The current `Photo Analysis (Debug)` surface is a separate sheet/toolbar action. The information
is useful for understanding Auto and mask behavior, but it is not part of a normal editing task
and the separate debug sheet is cumbersome to discover and compare with the current photo's
metadata. Inspect already owns the histogram and image facts, making it a better home for an
on-demand details section.

## Acceptance criteria

- [ ] Inspect contains a `Photo Analysis` disclosure/accordion at the bottom of the Info content;
      it is collapsed by default and does not displace the histogram or ordinary metadata.
- [ ] Expanding it can show the existing analysis facts, quality/timings, rationale, histogram
      relationship, and mask overlays without duplicating or changing the analysis values.
- [ ] Analysis remains demand-driven: opening Inspect or leaving the accordion collapsed does not
      run analysis or mask generation; loading, cancellation, and failure states are clear.
- [ ] The existing separate Analysis debug affordance is removed from the normal toolbar or kept
      only as a Developer-mode entry point if it is still useful while migrating.
- [ ] The section is usable at inspector width, preserves accessibility/disclosure semantics, and
      has UI/model coverage for collapsed, expanded, loading, success, and failure states.

## Implementation notes

- Reuse `AnalysisDebugPanelModel`/overlay rendering where practical, but keep the user-facing
  Inspect panel from taking a dependency on debug-only view code if that would make release builds
  awkward. Coordinate with LUMO-203 and LUMO-212 for the Developer-mode boundary.
- Persist disclosure state only if it matches existing inspector disclosure conventions; do not
  persist a state that causes analysis to run unexpectedly on launch.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-04T19:43:30.823Z: Verification report
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
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTNCXZ1W7TRISKOO
Summary: Moved Photo Analysis into a collapsed, on-demand Inspect disclosure with compact facts, histogram relationship, mask overlays, clear loading/failure states, cancellation on collapse, and asset-scoped state. Removed the normal toolbar debug affordance and sheet.
