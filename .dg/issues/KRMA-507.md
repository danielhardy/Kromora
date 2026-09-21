---
id: KRMA-507
title: Auto should replace existing photo edits instead of doing nothing
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Auto changes an already-edited photo when its computed result differs from the current Auto-owned values.
      result: pass
      notes: "Implementation evaluates from a clean Auto-owned baseline. Verifier closed a gap: when Auto's answer is the neutral baseline (balanced photo) on an edited doc, the engine returned unchanged and left user values; now promoted to improved (commit d94900a) with a regression test."
    - criterion: Existing Auto-owned adjustments are replaced rather than left untouched.
      result: pass
    - criterion: Unrelated crop, rotation, and mask state is preserved.
      result: pass
      notes: Covered by engine and AutoAdjustmentTests assertions on crop, rotation, localAdjustments, adjustments, effects, mixer.
    - criterion: The replacement is undoable and redoable as one coherent history operation.
      result: pass
      notes: AutoAdjustmentTests asserts one undo restores the full prior document and redo restores the Auto result.
    - criterion: Preview, histogram, thumbnail, and export reflect the new values.
      result: pass
      notes: Application goes through the unchanged updateDocument path (persistence/render/thumbnail); not separately exercised end-to-end by new tests.
    - criterion: Focused Auto tests and dg validate pass.
      result: pass
  checks_run:
    - swift build
    - swift test --filter AutoAdjustmentTests|ContentAwareAutoEngineTests|AutoEnhancement|AutoRun|PhotoAnalysis (90 tests, 8 skipped, 0 failures)
    - dg validate (only pre-existing unknown-model warnings)
  findings:
    - "Gap (fixed): unchanged winner on an already-edited photo left existing Auto-owned values in place."
    - "Note (non-blocking): autoAdjustmentBaseline no longer resets Light.toneCurve, unlike the previous light = .neutral analysis reset; the curve is now treated as user-owned and preserved, consistent with the documented contract."
  fixes:
    - ContentAwareAutoEngine promotes .unchanged to .improved when the baseline-derived document differs from current; added testBalancedFrameWithExistingAutoOwnedEditsReplacesThemWithNeutralResult.
  verification_commits:
    - d94900a
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-21T04:22:00.642Z
  session: 01MUAQLSGKOOADD3NR
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - auto
  - adjustments
  - history
created: 2026-09-21T02:40:19.928Z
updated: 2026-09-21T04:22:00.645Z
order: a0
board: product
commits:
  - d94900a
---

## Objective

Make Auto replace existing photo adjustments instead of silently doing nothing when edits already exist.

## Context

Choosing Auto on a photo with existing edits currently has no visible effect. Auto should compute a new automatic adjustment result and apply it as a replacement for the adjustment values it owns, even when the document is already edited.

## Requirements

1. Auto must run and apply its result when the photo already contains edits; existing edits must not cause an unconditional no-op.
2. Replace the global adjustment fields owned by Auto with the newly computed values.
3. Preserve unrelated document state such as crop, rotation, and masks unless the existing Auto contract explicitly owns those categories.
4. Record the replacement as one undoable persistent operation and persist it through the normal document path.
5. Refresh preview, histogram, thumbnails, and export output from the resulting document.
6. Add regression coverage for Auto on both clean and already-edited documents, including undo/redo.

## Acceptance criteria

- [ ] Auto changes an already-edited photo when its computed result differs from the current Auto-owned values.
- [ ] Existing Auto-owned adjustments are replaced rather than left untouched.
- [ ] Unrelated crop, rotation, and mask state is preserved.
- [ ] The replacement is undoable and redoable as one coherent history operation.
- [ ] Preview, histogram, thumbnail, and export reflect the new values.
- [ ] Focused Auto tests and dg validate pass.

## Implementation notes

Trace the current early-return or eligibility guard in the Auto action and the document update/history path. Distinguish no-op because the computed result equals the current values from no-op because any prior edit exists.


### Comment — codex @ 2026-09-21T04:20:21.854Z

Implemented in commit 86d9413. Auto now evaluates from a clean Auto-owned Light/Color baseline, replaces existing global values, preserves unrelated document state, and continues through the normal atomic persistence/history/render path. Added content-aware and editor regression coverage, including one-step undo/redo and preservation checks. Verification: focused Auto suites 38/38 passed; swift build passed; dg validate passed with only pre-existing unknown-model warnings; git diff --check clean.

## Agent log

- 2026-09-21T04:22:00.642Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Auto changes an already-edited photo when its computed result differs from the current Auto-owned values. (pass) — Implementation evaluates from a clean Auto-owned baseline. Verifier closed a gap: when Auto's answer is the neutral baseline (balanced photo) on an edited doc, the engine returned unchanged and left user values; now promoted to improved (commit d94900a) with a regression test.
- [x] Existing Auto-owned adjustments are replaced rather than left untouched. (pass)
- [x] Unrelated crop, rotation, and mask state is preserved. (pass) — Covered by engine and AutoAdjustmentTests assertions on crop, rotation, localAdjustments, adjustments, effects, mixer.
- [x] The replacement is undoable and redoable as one coherent history operation. (pass) — AutoAdjustmentTests asserts one undo restores the full prior document and redo restores the Auto result.
- [x] Preview, histogram, thumbnail, and export reflect the new values. (pass) — Application goes through the unchanged updateDocument path (persistence/render/thumbnail); not separately exercised end-to-end by new tests.
- [x] Focused Auto tests and dg validate pass. (pass)
Checks run:
- swift build
- swift test --filter AutoAdjustmentTests|ContentAwareAutoEngineTests|AutoEnhancement|AutoRun|PhotoAnalysis (90 tests, 8 skipped, 0 failures)
- dg validate (only pre-existing unknown-model warnings)
Findings:
- Gap (fixed): unchanged winner on an already-edited photo left existing Auto-owned values in place.
- Note (non-blocking): autoAdjustmentBaseline no longer resets Light.toneCurve, unlike the previous light = .neutral analysis reset; the curve is now treated as user-owned and preserved, consistent with the documented contract.
Fixes:
- ContentAwareAutoEngine promotes .unchanged to .improved when the baseline-derived document differs from current; added testBalancedFrameWithExistingAutoOwnedEditsReplacesThemWithNeutralResult.
Verification commits:
- d94900a
Actor: claude
Resolved model: sonnet
Pickup session: 01MUAQLSGKOOADD3NR
Summary: Verified; fixed neutral-result no-op on edited photos.
