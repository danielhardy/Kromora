---
id: KRMA-894
title: Do not replace a Look-graded stored frame with an ungraded render when the Look is unresolved
type: bug
status: backlog
priority: high
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - looks
  - preview
created: 2026-10-12T12:47:35.850Z
updated: 2026-10-12T12:47:35.850Z
blockers: []
order: w
board: product
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
