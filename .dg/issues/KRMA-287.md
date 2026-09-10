---
id: KRMA-287
title: Redundant inspectorState gate check in PreviewView mask overlay condition
type: task
status: done
priority: low
verification_agent: pi
verification_model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run:
    - "swift test: 964 tests executed, 45 skipped, 0 failures"
    - git diff --check
    - "dg validate: OK"
  findings: []
  fixes: []
  verification_commits:
    - a482a5b282efe67dc3149d047b4f3d52f1ef70e9
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-08T23:57:12.238Z
  session: 01MTTBTMDOY5R47FIB
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - masking
created: 2026-09-08T22:20:14.650Z
updated: 2026-09-10T12:53:53.670Z
depends_on:
  - KRMA-286
order: a0
board: product
commits:
  - a482a5b282efe67dc3149d047b4f3d52f1ef70e9
---

## Context

Found during counterpoint verification of KRMA-286 (commit b2ecd8d).

`PreviewView.body` gates the mask overlay with:

```swift
if inspectorState.isPresented, inspectorState.tab == .masking,
   viewModel.isMaskingWorkspaceActive,
   maskingState.showOverlay, viewModel.sourceSize != .zero, ...
```

but `AppViewModel.isMaskingWorkspaceActive` (Sources/LumoKit/ViewModels/AppViewModel.swift:439)
already includes `inspectorState.isPresented && inspectorState.tab == .masking` in its own
definition. The two leading conditions in `PreviewView` are therefore redundant with the
computed property that follows them.

Not a correctness bug — purely a maintainability nit flagged during verification, left
unresolved because it's outside the localized-fix scope for that verification pass.

## Suggested fix

Drop the two duplicate leading conditions in `PreviewView.swift` and rely solely on
`viewModel.isMaskingWorkspaceActive`.

Parent: KRMA-286

## Agent log

- 2026-09-08T23:57:12.244Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- swift test: 964 tests executed, 45 skipped, 0 failures
- git diff --check
- dg validate: OK
Findings:
- None
Fixes:
- None
Verification commits:
- a482a5b282efe67dc3149d047b4f3d52f1ef70e9
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTTBTMDOY5R47FIB
Summary: Removed the duplicate inspector presentation and masking-tab predicates from PreviewView mask overlay gating; the centralized isMaskingWorkspaceActive property remains the single workspace gate.
