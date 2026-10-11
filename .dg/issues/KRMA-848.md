---
id: KRMA-848
title: Stop restarting mask overlay resolve on every adjustment slider tick
type: bug
status: done
priority: medium
agent: codex
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Dragging Exposure with a smart mask selected no longer restarts mask resolution for look-only slider ticks or flashes the status spinner.
      result: pass
      notes: Reviewed task identity projection and confirmed adjustment, name, and auto provenance are excluded; implementation handoff also records successful manual drag log capture.
    - criterion: Mask geometry, soften/strength, inversion, amount, or selection changes still refresh the overlay.
      result: pass
      notes: Projected layer retains components, inversion, amount, enabled state, ownership, and identity; task key retains layer/component selection and resolution epoch.
    - criterion: Masking panel and overlay tests pass.
      result: pass
      notes: 93 tests passed, one opt-in preview benchmark skipped, zero failures.
  checks_run:
    - "swift test --filter Masking(Panel|Workspace)Tests|LocalMaskRenderingTests — passed: 93 tests executed, 1 opt-in benchmark skipped, 0 failures."
    - Independent code review of task identity and renderer inputs — passed; look-only fields are excluded while coverage-driving fields and other invalidation inputs remain represented.
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: unknown
  completed_at: 2026-10-10T14:54:40.800Z
  session: 01MV2ILO331AQ63ETH
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:02:24.529Z
updated: 2026-10-10T14:54:40.804Z
blockers: []
order: z
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-10T13:03:48.744Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - f6fe20677e504c5435b1e52c6adfeac902c8ccc8
  - ecf5d0aadba63bc6e93c34d85c386019069916b5
---

## Objective

Dragging an adjustment slider (Exposure, etc.) while a mask was selected restarted the mask overlay resolve on every tick and flashed "Analyzing mask…" in the status bar, even though mask coverage had not changed.

## Root cause

`MaskCanvasOverlay.OverlayTaskID` (used as the `.task(id:)` key) contained the full `[LocalAdjustmentLayer]`, including each layer's `adjustments`. Any look change cancelled and restarted overlay resolution. Mask-resolution logs showed about 20 loading/cancelled pairs in 1.5 s during an exposure drag.

## Work done

In `Sources/KromoraKit/Views/MaskingWorkspace.swift` the task id now uses `layers.map(\.overlayIdentity)`, a private `LocalAdjustmentLayer` projection that neutralises `adjustments`, `name` and `autoProvenance`. Membership, components/geometry, inversion, amount, selection, size and style still invalidate the task. The overlay is rendered with `includeIdentity: true`, so adjustments never affect it.

## Acceptance criteria

- Dragging Exposure with a smart mask selected no longer produces loading/cancelled bursts or a flashing status-bar spinner.
- Editing mask geometry, soften/strength, inversion, amount or selection still refreshes the overlay.
- Masking panel and overlay tests pass.


### Comment — claude @ 2026-10-10T13:03:48.276Z

Implemented in f6fe2067 (doc-comment placement fixed in ecf5d0aa). Masking panel/overlay tests pass; manual dev-build log capture showed the loading/cancelled bursts gone during an Exposure drag.


### Comment — claude @ 2026-10-10T13:11:12.412Z

Verifier note: implementation commit(s) f6fe2067 and ecf5d0aa are now recorded in the ticket's commits field. Review with: git show f6fe2067 ecf5d0aa. Verifier is codex (verification_agent). Acceptance criteria and known gaps are in the ticket body.

## Agent log

- 2026-10-10T14:54:40.800Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Dragging Exposure with a smart mask selected no longer restarts mask resolution for look-only slider ticks or flashes the status spinner. (pass) — Reviewed task identity projection and confirmed adjustment, name, and auto provenance are excluded; implementation handoff also records successful manual drag log capture.
- [x] Mask geometry, soften/strength, inversion, amount, or selection changes still refresh the overlay. (pass) — Projected layer retains components, inversion, amount, enabled state, ownership, and identity; task key retains layer/component selection and resolution epoch.
- [x] Masking panel and overlay tests pass. (pass) — 93 tests passed, one opt-in preview benchmark skipped, zero failures.
Checks run:
- swift test --filter Masking(Panel|Workspace)Tests|LocalMaskRenderingTests — passed: 93 tests executed, 1 opt-in benchmark skipped, 0 failures.
- Independent code review of task identity and renderer inputs — passed; look-only fields are excluded while coverage-driving fields and other invalidation inputs remain represented.
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: unknown
Pickup session: 01MV2ILO331AQ63ETH
Summary: Verified mask overlay task invalidation ignores look-only slider changes; focused masking suites pass.
