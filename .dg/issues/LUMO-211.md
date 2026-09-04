---
id: LUMO-211
title: Make masking selection actionable with a clear apply workflow
type: bug
status: done
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - ux
  - masking
created: 2026-09-04T19:08:01.642Z
updated: 2026-09-04T19:18:19.629Z
order: t
board: product
commits:
  - 131495f
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Apply Mask action and accurate selected-mask label
      result: pass
    - criterion: Exact RegionMask/derived mask uses coordinator and MaskOperations
      result: pass
    - criterion: Confirmation and cancel/close affordances
      result: pass
    - criterion: Unavailable masks are impossible with explicit explanation and errors are retryable
      result: pass
    - criterion: Select/invert/apply, current-photo, unavailable, and disabled-handoff regression coverage
      result: pass
  checks_run:
    - swift build
    - swift test --filter MaskingPanelTests
    - git diff --check
    - dg validate
  findings:
    - The existing editor has no local-adjustment model that can own or render an applied RegionMask; production Apply Mask remains truthfully disabled with an explicit explanation, per the ticket implementation note.
  fixes:
    - Added coordinator-owned RegionMask inversion and explicit apply hook carrying PhotoAssetID
    - Added Apply Mask/Cancel UI, selected-target confirmation, unavailable-mask retry flow, and failure messaging
    - Added five focused masking regression tests
  verification_commits:
    - 131495f
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-04T19:18:19.622Z
  session: 01MTNBXZY0LK993HIE
---

## Objective

Give the masking UI a clear way to apply the selected mask to an editing operation.

## Context

The current masking sheet can load Subject/Person/Background/Face, show an overlay, and invert the
preview, but it has no Apply/Use Mask action and no handoff into an adjustment. A user can click a
mask icon and see interesting pixels without any indication of how that selection changes the
photo. This is a UX defect in the LUMO-201 masking feature, not a request to duplicate the shared
mask infrastructure.

## Acceptance criteria

- [ ] After selecting a supported mask (including the inverted form), the UI presents an obvious
      Apply/Use Mask action with an accurate selected-mask label.
- [ ] Applying the mask hands the exact `RegionMask`/derived mask from the shared coordinator and
      `MaskOperations` path to the active local-adjustment workflow; it does not apply only the
      preview pixels or silently do nothing.
- [ ] The user receives clear confirmation of the active masked target and can cancel/close the
      sheet without applying it.
- [ ] Applying a mask to a photo with no available semantic region is impossible with an explicit
      explanation, and mask-generation errors are recoverable.
- [ ] Add UI/model tests proving select → invert (optional) → apply, cancel, and unavailable-mask
      flows, including that the applied mask belongs to the current photo.

## Implementation notes

- Reuse LUMO-184/185/186/195's `RegionMask`, `MaskStore`, and coordinator seams. Do not introduce a
  second mask representation or a direct Vision/Core Image path in the view.
- If the existing local-adjustment model is not yet able to own an applied mask, make that missing
  handoff explicit in the ticket implementation and provide a truthful disabled state/message;
  do not ship a button that only dismisses the sheet.
- Keep the v1 selection scope bounded: paint/brush refinement remains the LUMO-202 concern unless
  applying a selected semantic mask requires a small, already-supported adjustment hook.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-04T19:18:19.627Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Apply Mask action and accurate selected-mask label (pass)
- [x] Exact RegionMask/derived mask uses coordinator and MaskOperations (pass)
- [x] Confirmation and cancel/close affordances (pass)
- [x] Unavailable masks are impossible with explicit explanation and errors are retryable (pass)
- [x] Select/invert/apply, current-photo, unavailable, and disabled-handoff regression coverage (pass)
Checks run:
- swift build
- swift test --filter MaskingPanelTests
- git diff --check
- dg validate
Findings:
- The existing editor has no local-adjustment model that can own or render an applied RegionMask; production Apply Mask remains truthfully disabled with an explicit explanation, per the ticket implementation note.
Fixes:
- Added coordinator-owned RegionMask inversion and explicit apply hook carrying PhotoAssetID
- Added Apply Mask/Cancel UI, selected-target confirmation, unavailable-mask retry flow, and failure messaging
- Added five focused masking regression tests
Verification commits:
- 131495f
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTNBXZY0LK993HIE
Summary: Implemented the masking apply workflow in commit 131495f. The sheet now shows the selected target, explicit Apply Mask and Cancel actions, accurate inverted labels, active-target confirmation, retryable semantic-mask failures, and a clear disabled explanation because the current editor has no local-adjustment owner. Inversion is composed as a derived RegionMask through PhotoAnalysisCoordinator and MaskOperations, with the current asset ID carried through the handoff hook; no preview-only application path was added. Added five focused model/UI regression tests for select/invert/apply, current-photo identity, unavailable masks, disabled handoff, and panel construction.
