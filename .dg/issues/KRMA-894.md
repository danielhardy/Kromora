---
id: KRMA-894
title: Do not replace a Look-graded stored frame with an ungraded render when the Look is unresolved
type: bug
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: When the document Look is unresolved, keep a presented stored frame or show an explicit unresolved-Look state instead of replacing it with an ungraded render.
      result: pass
      notes: The settled submission defers while a stored frame is visibly presented for the active source generation; the regression test confirms no render is submitted.
    - criterion: Determine why mayUseStoredFrame is false on these switches and record the answer in the ticket.
      result: pass
      notes: "The ticket records all three code conditions: sourceROI is non-nil, original/comparison is showing, or crop tool is active. The original diagnostic did not distinguish which condition occurred; ROI is identified as likely, not certain."
    - criterion: A test covers a document naming a Look, unresolved Look, stored frame present, and expected presentation.
      result: pass
      notes: PreviewAdmissionCoordinatorTests.testUnresolvedLookKeepsThePresentedGradedStoredFrameInsteadOfRenderingUngraded passes.
    - criterion: Remove the temporary settledRenderSubmitted diagnostic or keep it only if cheap and intentional.
      result: pass
      notes: The temporary diagnostic was removed.
    - criterion: swift build and scripts/ci-tests.sh fast pass.
      result: pass
      notes: swift build passed. The fast lane exited 1 only on CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory (EditClipboardTests.swift:220-221); the pickup context reports this same failure when the implementation change is reverted. The focused KRMA-894 regression test passes.
  checks_run:
    - swift build (pass)
    - "scripts/ci-tests.sh fast (exit 1: one known unrelated CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory failure)"
    - swift test --filter PreviewAdmissionCoordinatorTests.testUnresolvedLookKeepsThePresentedGradedStoredFrameInsteadOfRenderingUngraded (pass)
  findings:
    - "scripts/ci-tests.sh fast has one unrelated failure already reported as reproducing with the implementation change reverted: CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory."
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-12T21:12:34.452Z
  session: 01MV5QVWHLGMRUVMLQ
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - looks
  - preview
created: 2026-10-12T12:47:35.850Z
updated: 2026-10-12T21:12:34.455Z
blockers: []
order: zzq
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-12T21:05:10.717Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Do not replace a Look-graded stored frame with an ungraded render when the Look is unresolved

## Context

The same log shows `settledRenderSubmitted storedFrame=storedFrameNotAllowed docLutIdentity=false renderLook=nil`: the document asks for a Look, the stored frame was drawn with it, and the settled render has no loaded Look. The ungraded render replaces the graded stored frame, so the Look visibly drops out. An unresolved Look should never replace pixels that were made with it. Related: KRMA-893 removes the most common cause; this covers a Look file that is genuinely missing or still being scanned.

## Acceptance criteria

- [ ] When the document's Look is not resolved, a presented stored frame made with that Look is kept, or an explicit unresolved-Look state is shown, instead of an ungraded render replacing it.
- [ ] Determine why `mayUseStoredFrame` is false on these switches (log shows `storedFrameNotAllowed`) and record the answer in the ticket.
- [ ] A test covers: document names a Look, Look unresolved, stored frame present, expected presentation.
- [ ] Remove the temporary `settledRenderSubmitted` diagnostic in `PreviewAdmissionCoordinator.submitSettledPreview`, or keep it only if it is cheap and intentional.
- [ ] `swift build` and `scripts/ci-tests.sh fast` pass.

## Implementation notes

See `LookSignature` (`unresolved` is documented as provisional, ungraded) and `FrameClassification` (`provisionalOnly` may hide latency only). The `settledRenderSubmitted` log line currently in `submitSettledPreview` is a temporary diagnostic added while investigating.

### Comment — claude @ 2026-10-12T21:05:07.246Z

Why storedFrameNotAllowed: mayUseStoredFrame is false only when request.sourceROI != nil (zoomed/ROI viewport or non-fit crop), the original/comparison baseline is showing, or the crop tool is active. The ticket's log did not record which; the ROI case is the likely one on a photo switch, since the stored frame is the canvas-size edit and cannot cover an ROI. Fix: submitSettledPreview now keeps a presented stored frame and defers the settled render when the document names a Look that is unresolved (request.lut == nil), instead of rendering ungraded over it. The Look catalog resolving reschedules the preview. Removed the temporary settledRenderSubmitted diagnostic. Test: PreviewAdmissionCoordinatorTests.testUnresolvedLookKeepsThePresentedGradedStoredFrameInsteadOfRenderingUngraded. swift build ok; fast lane has one failure, CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory, which fails identically with my change reverted.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-12T21:12:34.452Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] When the document Look is unresolved, keep a presented stored frame or show an explicit unresolved-Look state instead of replacing it with an ungraded render. (pass) — The settled submission defers while a stored frame is visibly presented for the active source generation; the regression test confirms no render is submitted.
- [x] Determine why mayUseStoredFrame is false on these switches and record the answer in the ticket. (pass) — The ticket records all three code conditions: sourceROI is non-nil, original/comparison is showing, or crop tool is active. The original diagnostic did not distinguish which condition occurred; ROI is identified as likely, not certain.
- [x] A test covers a document naming a Look, unresolved Look, stored frame present, and expected presentation. (pass) — PreviewAdmissionCoordinatorTests.testUnresolvedLookKeepsThePresentedGradedStoredFrameInsteadOfRenderingUngraded passes.
- [x] Remove the temporary settledRenderSubmitted diagnostic or keep it only if cheap and intentional. (pass) — The temporary diagnostic was removed.
- [x] swift build and scripts/ci-tests.sh fast pass. (pass) — swift build passed. The fast lane exited 1 only on CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory (EditClipboardTests.swift:220-221); the pickup context reports this same failure when the implementation change is reverted. The focused KRMA-894 regression test passes.
Checks run:
- swift build (pass)
- scripts/ci-tests.sh fast (exit 1: one known unrelated CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory failure)
- swift test --filter PreviewAdmissionCoordinatorTests.testUnresolvedLookKeepsThePresentedGradedStoredFrameInsteadOfRenderingUngraded (pass)
Findings:
- scripts/ci-tests.sh fast has one unrelated failure already reported as reproducing with the implementation change reverted: CopyPasteTests.testAcceptedDustSuggestionUsesNormalUndoHistory.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV5QVWHLGMRUVMLQ
Summary: Verified unresolved-Look stored-frame preservation; focused test and build pass. Fast lane retains one documented unrelated baseline failure.
