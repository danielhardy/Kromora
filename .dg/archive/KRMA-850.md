---
id: KRMA-850
title: Move mask analysis failure banner from the Masks panel to the status bar
type: bug
status: done
priority: medium
agent: codex
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The Masks panel never reflows when mask analysis fails or recovers.
      result: pass
      notes: Unavailable and failed resolution states render EmptyView in the inspector.
    - criterion: The status bar shows the failure with a working Retry that calls retryMaskAnalysis.
      result: pass
      notes: StatusBar passes viewModel.retryMaskAnalysis; the masking workspace retry test confirms a failed analysis resolves after retry.
    - criterion: VoiceOver reads the full message.
      result: pass
      notes: The full message is assigned to the status text accessibility label; Retry remains its own button.
  checks_run:
    - swift build (passed)
    - swift test --filter MaskingWorkspaceTests (45 tests passed)
    - git diff --cached --check (passed)
  findings: []
  fixes:
    - Kept the full error message on the status text accessibility element and removed container-level accessibility combining so Retry remains a distinct actionable control.
  verification_commits:
    - dd2a4436
  actor: codex
  resolved_model: unknown
  completed_at: 2026-10-10T14:59:01.528Z
  session: 01MV2IPV1UO7C33WL6
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:02:26.280Z
updated: 2026-10-10T14:59:01.531Z
blockers: []
order: zq
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-10T13:03:50.527Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 2321819e129d6a07ed1ba035dac6ddd58370ea7d
  - dd2a4436
---

## Objective

The "Mask analysis unavailable" / "failed" banner lived in the Masks inspector flow. It appeared and disappeared while the user hovered or clicked the mask, reflowing the panel so the mask row moved under the pointer.

## Work done

- `Sources/KromoraKit/Views/MaskingWorkspace.swift`: `renderStatus` no longer renders `.unavailable` / `.failed`; they join the no-op cases alongside the existing "transient progress lives in the status bar" rationale. The "Preview unavailable" banner is unchanged.
- `Sources/KromoraKit/Views/StatusBar.swift`: `MaskActivityIndicator` now takes a `retry` closure and shows a warning icon, "Mask analysis unavailable" and a Retry button for `.unavailable`/`.failed`, with the full message as help text and accessibility label. `.loading` is unchanged.

## Acceptance criteria

- The Masks panel never reflows when mask analysis fails or recovers.
- The status bar shows the failure with a working Retry (calls `retryMaskAnalysis`).
- VoiceOver reads the full message.
- Existing masking panel tests pass; a verifier may add a view-level assertion.


### Comment — claude @ 2026-10-10T13:03:50.063Z

Implemented in 2321819e. Build and masking panel tests pass; no new view-level test.


### Comment — claude @ 2026-10-10T13:11:12.885Z

Verifier note: implementation commit(s) 2321819e are now recorded in the ticket's commits field. Review with: git show 2321819e. Verifier is codex (verification_agent). Acceptance criteria and known gaps are in the ticket body.

## Agent log

- 2026-10-10T14:59:01.528Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The Masks panel never reflows when mask analysis fails or recovers. (pass) — Unavailable and failed resolution states render EmptyView in the inspector.
- [x] The status bar shows the failure with a working Retry that calls retryMaskAnalysis. (pass) — StatusBar passes viewModel.retryMaskAnalysis; the masking workspace retry test confirms a failed analysis resolves after retry.
- [x] VoiceOver reads the full message. (pass) — The full message is assigned to the status text accessibility label; Retry remains its own button.
Checks run:
- swift build (passed)
- swift test --filter MaskingWorkspaceTests (45 tests passed)
- git diff --cached --check (passed)
Findings:
- None
Fixes:
- Kept the full error message on the status text accessibility element and removed container-level accessibility combining so Retry remains a distinct actionable control.
Verification commits:
- dd2a4436
Actor: codex
Resolved model: unknown
Pickup session: 01MV2IPV1UO7C33WL6
Summary: Verification passed; status bar reports mask analysis failures, retry remains actionable, and VoiceOver receives the full message.
