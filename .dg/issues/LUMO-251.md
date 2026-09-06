---
id: LUMO-251
title: Retry after a failed smart-mask component add does not retry the mask fetch
type: bug
status: done
priority: urgent
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - masking
  - verification
created: 2026-09-06T04:59:26.037Z
updated: 2026-09-06T15:34:13.977Z
parent: LUMO-238
order: n
board: product
commits:
  - 9fe440a998b5aa077a05f81beadb980e1b3e5e8d
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Retrying after a failed addSmartMaskComponent request re-attempts the same layer/kind/mode component add
      result: pass
    - criterion: The workspace does not remain stuck in a loading mask-analysis state after component-add retry
      result: pass
    - criterion: Regression coverage verifies failed component add followed by retry resolves the component without creating a top-level layer
      result: pass
  checks_run:
    - swift test --filter MaskingWorkspaceTests (30 passed, 0 failures)
    - swift test (907 passed, 42 skipped, 0 failures)
    - git diff --check
    - dg validate (OK)
  findings: []
  fixes:
    - Added an explicit SmartMaskRetryContext for top-level creation versus component add, including destination layer and combine mode.
    - Recorded component retry context before analysis and routed retryMaskAnalysis back to addSmartMaskComponent.
  verification_commits:
    - 9fe440a998b5aa077a05f81beadb980e1b3e5e8d
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-06T15:34:13.974Z
  session: 01MTPYW8FG47EFLU0S
---

## Objective

Make "Retry mask analysis" actually retry a failed `addSmartMaskComponent` request, instead of
silently falling back to a generic preview retry (or, if state happens to be stale, retrying an
unrelated top-level mask creation).

## Context

Found during counterpoint verification of LUMO-238 (commit c0aed13), which added production
smart-mask actions (`AppViewModel+Masking.swift`).

`createSmartMask(_:)` sets `smartMaskRetryKind = kind` before starting its task, so
`retryMaskAnalysis()` can call `createSmartMask(kind)` again on failure. `addSmartMaskComponent(to:kind:mode:)`
is documented as "the component equivalent of `createSmartMask`" but never sets
`smartMaskRetryKind` — not before starting, and not on failure. It only clears it to `nil` on
success.

Consequences when `addSmartMaskComponent` fails (`.unavailable`/`.failed` resolution state, which
renders a "Retry mask analysis" button in `MaskingWorkspace.renderStatus`):

- If `smartMaskRetryKind` is currently `nil` (the common case — no prior top-level smart-mask
  create attempt this session), `retryMaskAnalysis()` takes the `else` branch: it calls
  `maskInteractionState.beginMaskResolution()` (state → `.loading`, showing "Analyzing mask…") and
  then `retryPreview()`, which only re-renders the image preview. Nothing ever calls
  `markMaskResolved`/`markMaskFailed`/`markMaskUnavailable` again for this attempt, so the
  workspace is left permanently spinning on "Analyzing mask…" — the masking workspace is
  effectively frozen for that control, which directly contradicts LUMO-238's acceptance criterion
  "communicates ... retry ... without freezing the masking workspace."
- If `smartMaskRetryKind` happens to hold a stale value from an earlier *top-level*
  `createSmartMask` call that is still unresolved, `retryMaskAnalysis()` instead calls
  `createSmartMask(kind)` — creating a brand-new top-level mask layer using that stale kind, which
  has nothing to do with the component add the user actually tried to retry.

Neither failure mode is covered by `MaskingWorkspaceTests`: existing coverage
(`testSmartActionPreflightsSharedProviderThenSelectsDurableMask`,
`testSmartCreationFailureWithoutSupportedSourceDoesNotCreateAnInertLayer`) only exercises
`createSmartMask`, not `addSmartMaskComponent`'s failure/retry path.

## Acceptance criteria

- [ ] Retrying after a failed `addSmartMaskComponent` request re-attempts the same
      layer/kind/mode component add (not a top-level mask creation, and not just a preview retry).
- [ ] The workspace does not get stuck showing a permanent "Analyzing mask…" state after a retry
      is triggered from the component-add failure path.
- [ ] Add regression coverage: an `addSmartMaskComponent` failure followed by `retryMaskAnalysis()`
      results in either a resolved component add or a terminal failed/unavailable state — never an
      indefinitely stuck `.loading` state or a wrongly-created top-level layer.

## Implementation notes

Likely needs the retry context to carry more than just `MaskCreationKind` — e.g. an enum/struct
capturing "retry: create top-level mask of kind K" vs "retry: add component of kind K/mode M to
layer L" — set at the start of both `createSmartMask` and `addSmartMaskComponent`, and consumed by
`retryMaskAnalysis()` to call back into the right function. Keep the fix localized to
`AppViewModel+Masking.swift` / `AppViewModel.swift`; no schema or public API changes should be
required.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-06T15:34:13.975Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Retrying after a failed addSmartMaskComponent request re-attempts the same layer/kind/mode component add (pass)
- [x] The workspace does not remain stuck in a loading mask-analysis state after component-add retry (pass)
- [x] Regression coverage verifies failed component add followed by retry resolves the component without creating a top-level layer (pass)
Checks run:
- swift test --filter MaskingWorkspaceTests (30 passed, 0 failures)
- swift test (907 passed, 42 skipped, 0 failures)
- git diff --check
- dg validate (OK)
Findings:
- None
Fixes:
- Added an explicit SmartMaskRetryContext for top-level creation versus component add, including destination layer and combine mode.
- Recorded component retry context before analysis and routed retryMaskAnalysis back to addSmartMaskComponent.
Verification commits:
- 9fe440a998b5aa077a05f81beadb980e1b3e5e8d
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTPYW8FG47EFLU0S
Summary: Fixed smart-mask component retry routing and added regression coverage.
