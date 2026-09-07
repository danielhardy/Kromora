---
id: LUMO-240
title: White balance temperature adjustment updates the Original pane in split view
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: While split view is active, a Temperature edit changes only the Adjusted pane; the Original pane rendered pixels remain unchanged throughout the gesture and after it settles.
      result: pass
    - criterion: The Adjusted pane still provides live/coalesced feedback and the final Temperature value is persisted, undoable, resettable, and reflected when split view is reopened.
      result: pass
    - criterion: Repeated Temperature edits, undo/redo, reset, and switching between split and single view do not cause the Original pane to adopt the current adjusted temperature.
      result: pass
    - criterion: Source switching and an intentional comparison-baseline invalidation still refresh the Original pane correctly, while ordinary Temperature edits do not.
      result: pass
    - criterion: The behavior is correct for both the RAW-aware and standard-image white-balance paths, with environment-dependent RAW coverage skipped explicitly when the decoder is unavailable.
      result: pass
    - criterion: Add regression coverage that records both comparison render requests/outputs and proves the Original request remains at the baseline while the Adjusted request receives the new Temperature.
      result: pass
  checks_run:
    - swift build
    - swift test --filter ComparisonModeTests (12 passed, 0 failures)
    - "swift test (full deterministic lane: 899 passed, 42 expected environment-gated skips, 0 failures)"
    - dg validate
    - Manual trace of AppViewModel.rawDevelopChangedComparisonFrame, updateDocument, applyHistoryDocument, resetPhoto, and scheduleOriginalPreview against the acceptance criteria and comparisonBaseline semantics
  findings:
    - "low: RAW white-balance Tint edits still invalidate the comparison baseline on every tick, reproducing the same class of bug this ticket fixed for Temperature, because rawDevelopChangedComparisonFrame only zeroes neutralTemperature and not neutralTint. Filed as non-blocking child ticket LUMO-252 (label verification, parent LUMO-240); out of scope here since the acceptance criteria and implementation notes for LUMO-240 are explicitly scoped to Temperature."
    - "informational: applyHistoryDocument has two separate if-comparisonChanged blocks that both reset comparisonPreviewScheduledRevision to nil, mirroring updateDocument's split around saveActiveDocument/documentRevision. Redundant but idempotent and harmless; not worth a ticket."
  fixes: []
  verification_commits:
    - 4c3ca82
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-06T05:44:01.514Z
  session: 01MTPDMHWU1E4ZXNPB
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - color
  - comparison
  - rendering
  - editor
created: 2026-09-06T03:32:15.654Z
updated: 2026-09-07T04:02:46.734Z
order: fjve4130
board: product
commits:
  - 4c3ca82
---

## Objective

Keep the Original pane immutable while white-balance Temperature is edited in split view.

## Context

When side-by-side comparison is showing both Original and Adjusted, changing White Balance
Temperature updates the Original pane as well as the Adjusted pane. That makes the before/after
comparison misleading: the reference image changes at the same time as the edit being evaluated.

### Reproduction

1. Open a photo with comparison available and enable split view so Original and Adjusted are both
   visible.
2. Open the White Balance controls.
3. Drag Temperature, or enter a different temperature value.
4. Compare both panes during the interaction and after the value settles.

### Observed

The Original pane changes temperature along with the Adjusted pane.

### Expected

The Adjusted pane should update continuously and show the new temperature. The Original pane should
remain fixed at the comparison baseline until the source or an intentional comparison-baseline
change occurs.

## Acceptance criteria

- [ ] While split view is active, a Temperature edit changes only the Adjusted pane; the Original
      pane's rendered pixels remain unchanged throughout the gesture and after it settles.
- [ ] The Adjusted pane still provides live/coalesced feedback and the final Temperature value is
      persisted, undoable, resettable, and reflected when split view is reopened.
- [ ] Repeated Temperature edits, undo/redo, reset, and switching between split and single view do
      not cause the Original pane to adopt the current adjusted temperature.
- [ ] Source switching and an intentional comparison-baseline invalidation still refresh the
      Original pane correctly, while ordinary Temperature edits do not.
- [ ] The behavior is correct for both the RAW-aware and standard-image white-balance paths, with
      environment-dependent RAW coverage skipped explicitly when the decoder is unavailable.
- [ ] Add regression coverage that records both comparison render requests/outputs and proves the
      Original request remains at the baseline while the Adjusted request receives the new
      Temperature.

## Implementation notes

Trace the white-balance routing from LUMO-030/LUMO-034 through the comparison baseline and render
scheduling established by LUMO-047. Inspect `EditDocument.originalForComparison`, the
`scheduleOriginalPreview` path, and the RAW/post-render Temperature split before changing behavior.
Preserve the documented baseline semantics and guard against stale asynchronous publications to
either pane; do not fix this by merely stopping the Original render if its baseline document is
still mutable.

### Comment — codex @ 2026-09-06T05:33:49.529Z

Implemented in commit 4c3ca82. Added a per-source presentation-only comparison baseline snapshot, excluded RAW Temperature-only changes from baseline invalidation, guarded stale/duplicate Original scheduling, and explicitly refreshes the baseline for Reset Photo. Space-hold and side-by-side now use the stable snapshot. Added standard-image and fake-RAW regression coverage proving adjusted requests receive Temperature while Original requests stay at baseline, including split-view reopen. Verification: swift test — 899 passed, 42 expected environment-gated skips, 0 failures; swift build -c release — passed; git diff --check — passed.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-06T05:44:01.515Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] While split view is active, a Temperature edit changes only the Adjusted pane; the Original pane rendered pixels remain unchanged throughout the gesture and after it settles. (pass)
- [x] The Adjusted pane still provides live/coalesced feedback and the final Temperature value is persisted, undoable, resettable, and reflected when split view is reopened. (pass)
- [x] Repeated Temperature edits, undo/redo, reset, and switching between split and single view do not cause the Original pane to adopt the current adjusted temperature. (pass)
- [x] Source switching and an intentional comparison-baseline invalidation still refresh the Original pane correctly, while ordinary Temperature edits do not. (pass)
- [x] The behavior is correct for both the RAW-aware and standard-image white-balance paths, with environment-dependent RAW coverage skipped explicitly when the decoder is unavailable. (pass)
- [x] Add regression coverage that records both comparison render requests/outputs and proves the Original request remains at the baseline while the Adjusted request receives the new Temperature. (pass)
Checks run:
- swift build
- swift test --filter ComparisonModeTests (12 passed, 0 failures)
- swift test (full deterministic lane: 899 passed, 42 expected environment-gated skips, 0 failures)
- dg validate
- Manual trace of AppViewModel.rawDevelopChangedComparisonFrame, updateDocument, applyHistoryDocument, resetPhoto, and scheduleOriginalPreview against the acceptance criteria and comparisonBaseline semantics
Findings:
- low: RAW white-balance Tint edits still invalidate the comparison baseline on every tick, reproducing the same class of bug this ticket fixed for Temperature, because rawDevelopChangedComparisonFrame only zeroes neutralTemperature and not neutralTint. Filed as non-blocking child ticket LUMO-252 (label verification, parent LUMO-240); out of scope here since the acceptance criteria and implementation notes for LUMO-240 are explicitly scoped to Temperature.
- informational: applyHistoryDocument has two separate if-comparisonChanged blocks that both reset comparisonPreviewScheduledRevision to nil, mirroring updateDocument's split around saveActiveDocument/documentRevision. Redundant but idempotent and harmless; not worth a ticket.
Fixes:
- None
Verification commits:
- 4c3ca82
Actor: claude
Resolved model: sonnet
Pickup session: 01MTPDMHWU1E4ZXNPB
Summary: Independent verification passed: RAW Temperature edits correctly leave the comparison Original pane at its snapshot baseline; standard-image Temperature was already correct pre-fix and is now covered by regression tests. Full suite green (899 passed, 42 expected skips, 0 failures). Filed non-blocking LUMO-252 for the analogous RAW Tint gap, outside this ticket scope.
