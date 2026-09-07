---
id: LUMO-238
title: Expose smart mask tools in the production masking workspace
type: bug
status: review
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - masking
  - analysis
  - editor
  - epic:masking
created: 2026-09-06T03:14:53.292Z
updated: 2026-09-07T01:14:11.074Z
depends_on:
  - LUMO-251
order: w
board: product
commits:
  - c0aed13
  - a42c5cfafb9370b4e746ed96934814417295912d
---

## Objective

Expose the supported smart-mask actions in the production masking workspace.

## Context

The debug mode exposes smart-mask capabilities, but the production masking workspace does not offer
an equivalent way to create them. Users therefore cannot access the same subject-aware workflow in
the actual editor, and there is no explanation of which smart mask types are available or still
processing.

### Reproduction

1. Open the production masking workspace on a photo suitable for semantic analysis.
2. Compare the available mask creation tools with the smart-mask controls visible in debug mode.

### Observed

Smart mask actions are missing from the production UI even though the underlying analysis/debug path
can expose them. There is no user-facing entry point or status for creating a smart mask.

### Expected

The production masking workspace should expose supported smart-mask creation actions with the same
analysis-backed behavior, clear availability/loading/error states, and durable editable results.

## Acceptance criteria

- [ ] Production masking exposes the supported smart-mask actions, including the smart kinds
      already available in debug mode (for example Subject/Person/Background/Face where supported).
- [ ] Invoking an action creates and selects a durable semantic mask component/layer, or reports a
      clear unavailable/error state without creating an inert layer.
- [ ] The UI communicates analysis progress, partial results, retry, and unsupported-source states
      without freezing the masking workspace.
- [ ] Smart masks can be inspected, enabled/disabled, inverted, combined, and used by local
      adjustments through the same production workflow as other mask components.
- [ ] Production behavior uses the shared analysis/provider boundary rather than a debug-only code
      path, and remains presentation/export consistent.
- [ ] Add UI/model coverage proving the actions are reachable outside Developer mode and that the
      created semantic component persists and reopens.

## Implementation notes

Use LUMO-201 as the product/UI context and the provider work in LUMO-184, LUMO-187, LUMO-188,
LUMO-189, LUMO-191, and LUMO-224 as the implementation seams. Reuse the existing debug labels and
analysis status vocabulary only where it is appropriate for production users; do not expose raw
diagnostics as the primary workflow.

### Comment — codex @ 2026-09-06T04:57:48.630Z

Implemented and verified production smart-mask actions. Add Mask now exposes Subject, Person, Face, Foreground, and Background; requests preflight through the shared analysis coordinator, persist durable semantic components only after actionable results, and surface loading, empty, unavailable, failed, and retry states. Added component preflight and persistence/reopen regression coverage. Tests: swift test (894 passed, 42 skipped). Commit: c0aed13.

### Comment — claude @ 2026-09-06T05:02:18.818Z

Counterpoint verification (blocker found; returning to review)

Scope reviewed: commit c0aed13 (production smart-mask actions: MaskInteractionState resolution
state, AppViewModel+Masking createSmartMask/addSmartMaskComponent, MaskingWorkspace UI, tests).
swift build and swift test --filter MaskingWorkspaceTests both pass (23/23).

Correctness — BLOCKER (filed as LUMO-251, urgent, parent LUMO-238, depends_on wired):
addSmartMaskComponent never sets smartMaskRetryKind (createSmartMask does, at the top of the
function). So when a component-add analysis fails and the UI shows the "Retry mask analysis"
button (AppViewModel+Masking.swift, MaskingWorkspace.renderStatus .unavailable/.failed cases),
retryMaskAnalysis() either (a) falls into its nil-retryKind branch and calls retryPreview(), which
only re-renders the image preview and never resolves maskInteractionState.resolutionState again —
leaving the workspace stuck on "Analyzing mask…" indefinitely, or (b) if a stale retry kind is
present from an earlier top-level createSmartMask call, retries the wrong action entirely
(creates a new top-level mask layer instead of retrying the component add). This contradicts the
LUMO-238 acceptance criterion that the UI communicate retry states "without freezing the masking
workspace." Not covered by existing tests — MaskingWorkspaceTests only exercises the
createSmartMask retry path, not addSmartMaskComponent's failure/retry path.

Everything else checked out: preflight/cache-fingerprint guards against stale async completions
look correct in both createSmartMask and addSmartMaskComponent, MaskPresentationPolicy decision
handling (actionable/empty/lowConfidence) is consistent, Swift 6 mode has no new escape hatches,
and the persistence/reopen + "every supported smart kind reachable outside Developer mode" tests
in c0aed13 pass.

No local fix applied — per the verification action rules, an unresolved blocker gets a child
ticket and this issue goes back to review rather than being patched here, since a correct fix
needs a small retry-context redesign (kind alone doesn't capture "retry this component add on
layer L with mode M") rather than a one-line change.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
