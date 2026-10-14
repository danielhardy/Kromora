---
id: KRMA-993
title: Restore live Info histogram updates during slider drags
type: bug
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: While an edit slider is moving, the Info histogram follows the latest presented interactive frame before mouse-up.
      result: pass
      notes: Interactive publication invokes histogram admission only after presentation confirmation; newer texture samples supersede older surface revisions. PreviewPublicationCoordinatorTests and PreviewAdmissionCoordinatorTests cover this path.
    - criterion: The final settled frame replaces the last interactive histogram sample when the drag ends.
      result: pass
      notes: Settled publication forces admission when source content, document, Look, or working space changed since the last settled frame. Tests confirm the final sample replaces the interactive one.
    - criterion: Texture-backed frames use their existing bounded presentation-texture sample without re-evaluating the source preview graph.
      result: pass
      notes: Existing admission coverage verifies presentation samples publish without an engine histogram request; texture fallback tests remain green.
    - criterion: Stale samples cannot replace newer photo, source revision, edit document, Look, or surface revision, and existing inspector, crop, comparison, and failure gates remain intact.
      result: pass
      notes: Revision and identity fences remain in the admission and publication paths; focused stale-sample, stored-frame, crop, and failure coverage passes.
    - criterion: Zoom, pan, fit, and fill do not change the histogram; edits and committed crops refresh it.
      result: pass
      notes: DevelopInspectorTests navigation, pending-zoom, and crop-refresh regressions pass. Settled force-refresh is limited to changed image content.
    - criterion: Deterministic coverage exercises interactive publication through histogram admission, latest-frame wins before mouse-up, and navigation invariants.
      result: pass
      notes: Added settled handoff coverage and verified latest interactive texture sample and navigation behavior in the focused suites.
  checks_run:
    - swift test --filter PreviewPublicationCoordinatorTests|PreviewAdmissionCoordinatorTests — 36 tests, 0 failures
    - swift test --filter PreviewSurfaceTests|DevelopInspectorTests — 90 tests, 0 failures
    - scripts/ci-tests.sh fast — 1,907 required tests, exit 0
    - dg validate — exit 0; existing unrelated model-name warnings
    - git diff --check HEAD^ HEAD — clean
  findings: []
  fixes:
    - Refresh the histogram from the final settled frame after a drag changes image content, while preserving content deduplication for navigation.
  verification_commits:
    - edff3b84
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T13:11:22.767Z
  session: 01MV84B06PDVW7H0L2
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - histogram
  - preview
  - regression
created: 2026-10-14T12:46:47.378Z
updated: 2026-10-14T13:11:22.770Z
blockers: []
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/ViewModels/PreviewCoordinator.swift
    - Sources/KromoraKit/ViewModels/PreviewPublicationCoordinator.swift
    - Sources/KromoraKit/ViewModels/PreviewAdmissionCoordinator.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
    - Sources/KromoraKit/Views/PreviewSurface.swift
    - Sources/KromoraKit/ViewModels/InfoState.swift
    - Tests/KromoraKitTests/PreviewAdmissionCoordinatorTests.swift
    - Tests/KromoraKitTests/PreviewPublicationCoordinatorTests.swift
    - Tests/KromoraKitTests/PreviewSurfaceTests.swift
    - Tests/KromoraKitTests/DevelopInspectorTests.swift
  docs:
    - docs/APP_VIEWMODEL_OBSERVATION_PLAN.md
    - docs/ENGINEERING_GUIDE.md
    - CLAUDE.md
  issues:
    - KRMA-815
    - KRMA-591
    - KRMA-977
    - KRMA-980
    - KRMA-981
  commands:
    - swift test --filter PreviewAdmissionCoordinatorTests
    - swift test --filter PreviewPublicationCoordinatorTests
    - swift test --filter PreviewSurfaceTests
    - swift test --filter DevelopInspectorTests
    - scripts/ci-tests.sh fast
    - dg validate
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T13:00:16.745Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - edff3b84
---

## Objective

Restore live Info histogram updates during active edit-slider drags. The histogram must follow slider movement while the mouse button remains down; updating only after mouse-up does not meet this requirement. The observed behavior appears inconsistent with the live-frame contract recorded as completed in KRMA-815; investigate the current end-to-end publication path and repair any missing interactive-frame admission.

## Context

The histogram already has a bounded sample from the presentation texture, and KRMA-815 records that interactive frames should update the chart while dragging, with the newest frame winning. Current source review found histogram admission in the settled publication tail, while interactive publication presents a frame through a separate branch. Confirm the behavior through the full production path and identify where the interactive sample stops reaching Info state. Do not assume the Observation migration caused the issue.

KRMA-591 establishes the existing navigation contract: zoom, pan, fit, and fill alone do not recompute or change the whole-photo histogram. Preserve that behavior. Image edits and committed crop changes must continue to refresh it. This issue does not change the histogram to a viewport-only scope.

Relevant prior work:
- KRMA-815 — presentation-texture sampling and live-edit histogram contract.
- KRMA-591 — histogram stays unchanged during canvas navigation.
- KRMA-977, KRMA-980, KRMA-981 — InfoState extraction and Observation migration.

## Acceptance criteria

- [ ] While the user is actively moving an edit slider and the mouse button remains down, the Info histogram updates to follow the latest presented interactive frame. A change only on mouse-up or after the drag ends does not pass.
- [ ] When the drag ends, the final settled frame replaces the last interactive histogram sample.
- [ ] Texture-backed frames use their existing bounded presentation-texture sample. Do not evaluate the source preview graph again to produce a histogram for a frame that already has a sample.
- [ ] A stale sample cannot replace a newer photo, source revision, edit document, Look, or surface revision. Existing inspector, crop-tool, original-comparison, and failure gates remain intact.
- [ ] Zoom, pan, fit, and fill do not change the histogram. Edit and committed-crop changes still refresh it.
- [ ] Deterministic coverage exercises interactive publication during an active drag through histogram admission, confirms latest-frame wins before mouse-up, and retains the navigation invariant.

## Implementation notes

Start at the interactive and settled branches in `PreviewPublicationCoordinator.publish`, the presentation-sample callback in `AppViewModel`, and `PreviewAdmissionCoordinator.updateHistogram` / `presentationHistogramSampleDidChange`. Follow `PreviewSurface.present` and its texture sample revision fencing. Keep the Observation state boundary narrow; the task is to connect presented interactive samples to the existing Info histogram state.

Likely code and test context:
- `Sources/KromoraKit/ViewModels/PreviewCoordinator.swift`
- `Sources/KromoraKit/ViewModels/PreviewPublicationCoordinator.swift`
- `Sources/KromoraKit/ViewModels/PreviewAdmissionCoordinator.swift`
- `Sources/KromoraKit/ViewModels/AppViewModel.swift`
- `Sources/KromoraKit/Views/PreviewSurface.swift`
- `Sources/KromoraKit/ViewModels/InfoState.swift`
- `Tests/KromoraKitTests/PreviewAdmissionCoordinatorTests.swift`
- `Tests/KromoraKit/PreviewPublicationCoordinatorTests.swift`
- `Tests/KromoraKit/PreviewSurfaceTests.swift`
- `Tests/KromoraKit/DevelopInspectorTests.swift`

Useful focused verification: the four test files above, `scripts/ci-tests.sh fast`, and `dg validate`. Do not run display-bound capture benchmarks for this interaction-path fix.


### Comment — claude @ 2026-10-14T13:00:16.193Z

Cause: PreviewPublicationCoordinator.publish presented interactive frames with onPresented: nil, so histogram admission ran only in the settled tail. Interactive frames now run the same identity/revision-gated updateHistogram (stored-edits-resolved, asset/source/display revision, document checks) via the existing presentation-texture sample; no confirmation, persistence, or lastPresented change, so the settled frame replaces it and zoom/pan dedup (hasSameImageContent) is untouched. Tests updated/added in PreviewPublicationCoordinatorTests. Passed: Preview{Publication,Admission}Coordinator, PreviewSurface, DevelopInspector (124 tests), ci-tests.sh fast, git diff --check. Not run: warning-gate, dg validate, swift format. Commit 5fdb2efd.

## Agent log

- 2026-10-14T13:11:22.767Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] While an edit slider is moving, the Info histogram follows the latest presented interactive frame before mouse-up. (pass) — Interactive publication invokes histogram admission only after presentation confirmation; newer texture samples supersede older surface revisions. PreviewPublicationCoordinatorTests and PreviewAdmissionCoordinatorTests cover this path.
- [x] The final settled frame replaces the last interactive histogram sample when the drag ends. (pass) — Settled publication forces admission when source content, document, Look, or working space changed since the last settled frame. Tests confirm the final sample replaces the interactive one.
- [x] Texture-backed frames use their existing bounded presentation-texture sample without re-evaluating the source preview graph. (pass) — Existing admission coverage verifies presentation samples publish without an engine histogram request; texture fallback tests remain green.
- [x] Stale samples cannot replace newer photo, source revision, edit document, Look, or surface revision, and existing inspector, crop, comparison, and failure gates remain intact. (pass) — Revision and identity fences remain in the admission and publication paths; focused stale-sample, stored-frame, crop, and failure coverage passes.
- [x] Zoom, pan, fit, and fill do not change the histogram; edits and committed crops refresh it. (pass) — DevelopInspectorTests navigation, pending-zoom, and crop-refresh regressions pass. Settled force-refresh is limited to changed image content.
- [x] Deterministic coverage exercises interactive publication through histogram admission, latest-frame wins before mouse-up, and navigation invariants. (pass) — Added settled handoff coverage and verified latest interactive texture sample and navigation behavior in the focused suites.
Checks run:
- swift test --filter PreviewPublicationCoordinatorTests|PreviewAdmissionCoordinatorTests — 36 tests, 0 failures
- swift test --filter PreviewSurfaceTests|DevelopInspectorTests — 90 tests, 0 failures
- scripts/ci-tests.sh fast — 1,907 required tests, exit 0
- dg validate — exit 0; existing unrelated model-name warnings
- git diff --check HEAD^ HEAD — clean
Findings:
- None
Fixes:
- Refresh the histogram from the final settled frame after a drag changes image content, while preserving content deduplication for navigation.
Verification commits:
- edff3b84
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV84B06PDVW7H0L2
Summary: Verified live histogram updates during slider drags; settled samples refresh after edit changes.
