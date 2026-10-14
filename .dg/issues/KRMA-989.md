---
id: KRMA-989
title: Make multi-photo Share immediate and HEIC-fallback safe
type: task
status: done
priority: urgent
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The multi-photo Share picker appears before rendering, or visible progress is shown if lazy rendering is infeasible.
      result: pass
      notes: The picker receives lazy per-item providers before any render request; the ordering test observes zero renders at presentation.
    - criterion: Every selected item preserves its edit snapshot, uses HEIF at quality 0.85, long edge at most 4096 px, current working color space, and retries as JPEG if HEIF encoding fails.
      result: pass
      notes: Batch items and request snapshots are captured before presentation. Tests verify HEIF-first options and JPEG retry for every selected provider. Providers advertise public.image because concrete HEIC or JPEG output is selected lazily; staged filenames match the successful encoder.
    - criterion: The picker is anchored to the Share control and never falls back to the window content view.
      result: pass
      notes: The presentation path requires the registered Share anchor; the no-anchor test verifies that no picker is shown.
    - criterion: Tests cover picker-before-render, JPEG fallback, and an empty temporary share directory after cancellation, success, and failure.
      result: pass
      notes: Focused tests cover all four lifecycle outcomes and confirm staged HEIC/JPEG file extensions and JPEG payloads.
    - criterion: swift build is warning-free and scripts/ci-tests.sh fast exits 0.
      result: pass
      notes: Both declared checks exited 0.
  checks_run:
    - swift build — exit 0; no warnings
    - scripts/ci-tests.sh fast — final run exit 0; lane audit found 1,857 required-fast tests
    - git diff --check — exit 0
    - Reviewed lazy provider type and file naming against the HEIC/JPEG fallback path
  findings:
    - A provider advertised HEIC even when its fallback file contained JPEG data, so the registered type did not describe the actual fallback. Corrected by advertising the common public.image type and testing the staged file extension and JPEG payload.
    - "The first run of the fast lane exposed an invalid test assumption: AppKit returns an extensionless temporary copy for public.image. Updated the assertion to inspect the staged export file; the final fast lane passed."
  fixes:
    - Changed lazy Share providers to advertise public.image so HEIC and JPEG fallback data are represented consistently; added type-conformance, registered-type, staged-extension, and payload assertions.
  verification_commits:
    - 7da3838e
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T23:53:17.650Z
  session: 01MV7BXIAVYJD3DWLE
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - verification
created: 2026-10-13T23:23:32.207Z
updated: 2026-10-13T23:53:17.653Z
parent: KRMA-949
blockers: []
order: t
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T23:45:53.640Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 7da3838e
---

KRMA-949 verification found that ExportWorkflowCoordinator.shareSelectedExports creates a temporary directory and awaits performBatchExport before presenting NSSharingServicePicker. This delays the picker until all selected images render. The batch path requests HEIF only and skips items whose HEIF encode fails, so JPEG fallback is missing. presentSharePicker also falls back to the window content view when shareAnchorView is unavailable, contrary to KRMA-949 anchoring criteria.

Expected outcome: multi-photo sharing presents the picker promptly with per-item lazy file representations; if that is infeasible, present the picker itself with visible progress and document the reason in the review comment. Use the Share control as the picker anchor and do not fall back to the window content view. Preserve each selected item and its edit snapshot; encode HEIF at quality 0.85, long edge no greater than 4096 px, and the current working color space, retrying as JPEG when HEIF encoding fails. Keep temporary files alive while the chosen service uses them and remove the share directory after cancellation, success, and failure.

Acceptance criteria:
- A multi-photo share presents the picker before any render begins, or presents the picker with visible progress and a documented reason lazy rendering cannot be used.
- Each selected item is represented and encoded using the documented HEIF policy; failed HEIF encoding retries JPEG without silently dropping that item.
- The picker is anchored to the Share control; the window content view is never used as a fallback.
- Tests prove picker presentation precedes rendering (or verify picker-visible progress), JPEG fallback, and an empty temporary share directory after cancellation, success, and failure.
- swift build is warning-free and scripts/ci-tests.sh fast exits 0.


### Comment — claude @ 2026-10-13T23:45:57.307Z

Implemented in commit 549724bc. Multi-photo Share presents the picker before any render; each selected item is a lazy file representation carrying its own edit snapshot, encoded HEIF q0.85 / 4096px long edge / current working space, retrying JPEG if HEIF fails (no item dropped). Anchor is the Share control only; the keyWindow contentView fallback is removed. Share directory is removed on cancel, success and failure via the picker/service delegate. Lazy rendering was feasible, so no progress UI was needed. Tests added for picker-before-render, JPEG fallback, cancel/success/failure cleanup, and no-anchor behaviour. swift build is warning-free; scripts/ci-tests.sh fast exits 0 (one unrelated StoredEditAdoptionTests flake on a prior run did not recur).

## Agent log

- 2026-10-13T23:53:17.650Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The multi-photo Share picker appears before rendering, or visible progress is shown if lazy rendering is infeasible. (pass) — The picker receives lazy per-item providers before any render request; the ordering test observes zero renders at presentation.
- [x] Every selected item preserves its edit snapshot, uses HEIF at quality 0.85, long edge at most 4096 px, current working color space, and retries as JPEG if HEIF encoding fails. (pass) — Batch items and request snapshots are captured before presentation. Tests verify HEIF-first options and JPEG retry for every selected provider. Providers advertise public.image because concrete HEIC or JPEG output is selected lazily; staged filenames match the successful encoder.
- [x] The picker is anchored to the Share control and never falls back to the window content view. (pass) — The presentation path requires the registered Share anchor; the no-anchor test verifies that no picker is shown.
- [x] Tests cover picker-before-render, JPEG fallback, and an empty temporary share directory after cancellation, success, and failure. (pass) — Focused tests cover all four lifecycle outcomes and confirm staged HEIC/JPEG file extensions and JPEG payloads.
- [x] swift build is warning-free and scripts/ci-tests.sh fast exits 0. (pass) — Both declared checks exited 0.
Checks run:
- swift build — exit 0; no warnings
- scripts/ci-tests.sh fast — final run exit 0; lane audit found 1,857 required-fast tests
- git diff --check — exit 0
- Reviewed lazy provider type and file naming against the HEIC/JPEG fallback path
Findings:
- A provider advertised HEIC even when its fallback file contained JPEG data, so the registered type did not describe the actual fallback. Corrected by advertising the common public.image type and testing the staged file extension and JPEG payload.
- The first run of the fast lane exposed an invalid test assumption: AppKit returns an extensionless temporary copy for public.image. Updated the assertion to inspect the staged export file; the final fast lane passed.
Fixes:
- Changed lazy Share providers to advertise public.image so HEIC and JPEG fallback data are represented consistently; added type-conformance, registered-type, staged-extension, and payload assertions.
Verification commits:
- 7da3838e
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV7BXIAVYJD3DWLE
Summary: Independent verification passed; corrected the lazy provider type for JPEG fallback and all required checks pass.
