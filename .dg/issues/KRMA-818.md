---
id: KRMA-818
title: Balance sandbox access lifetimes for panel-selected and dropped URLs
type: task
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Panel-selected files and recursive folder imports complete in the sandbox after the panel closes.
      result: pass
      notes: The signed sandbox run recorded multi-file panel import and recursive nested-folder import completing after the panel closed.
    - criterion: Window file and folder drops work in the sandbox, or the UI reports a clear unsupported/access error.
      result: pass
      notes: The 2026-10-19 human report says a single Finder image imported directly; a folder drop opened the selection and duplicate review, and the selected three-item import finished. The running Kromora app is ad-hoc signed with App Sandbox and user-selected read/write entitlements. The report does not pin the exact source revision or claim separate per-photo opening.
    - criterion: Removable-media fallback grants remain active until each selected source has been copied into the package.
      result: pass
      notes: The signed run imported a selected removable-media source, matched source and package SHA-256 values, and kept the source volume read-only. Deterministic tests cover grant transfer from scan preflight into the import request and retention through worker completion.
    - criterion: Direct Look saves and other user-selected output writes release panel access after completion.
      result: pass
      notes: Look and derived-Look save paths release access with defer. The scoped export test asserts the grant remains active through the write and releases afterward; the human report also confirms TIFF export and opening in Preview.
    - criterion: Every scope is balanced on success, error, cancellation, and supersession; repeated operations do not exhaust file access grants.
      result: pass
      notes: The shared scope owner releases once, including when explicitly released more than once. Import ownership releases on scheduler terminal outcomes or failed handoff; save paths use defer. Tests cover failed starts, queued-import cancellation, scan cancellation, successful import, and scoped output completion.
    - criterion: A signed sandboxed app run records the panel, window-drop, folder-recursion, removable-media, and output-save cases.
      result: pass
      notes: Coverage is recorded across the signed sandbox run and the 2026-10-19 human follow-up on the running App Sandbox app. The follow-up does not identify the exact source revision; the earlier output run predated the final exclusive-create writer.
  checks_run:
    - swift test --filter SecurityScopedResourceAccessTests|LibraryMediaWorkflowCoordinatorTests|PortableLibrarySessionTests|ExportCoordinatorTests|KromoraSettingsTests — exit 0; 90 tests passed.
    - scripts/ci-tests.sh fast — exit 0; all 1,941 required parallel tests passed.
    - scripts/ci-tests.sh serial — exit 0; 739 tests, 1 skipped, 0 failures.
    - git show --check cfb81be8 — exit 0.
    - Reviewed scope ownership in Sources/KromoraKit/Models/SecurityScopedResourceAccess.swift, Sources/KromoraKit/Models/PortableLibrarySession.swift, Sources/KromoraKit/ViewModels/LibraryMediaWorkflowCoordinator.swift, Sources/KromoraKit/ViewModels/ExportCoordinator.swift, Sources/KromoraKit/ViewModels/DeriveCoordinator.swift, and Sources/KromoraKit/ViewModels/LookSaveCoordinator.swift, plus related tests.
    - "Inspected the running Kromora app signature and entitlements: ad-hoc signed, App Sandbox enabled, and user-selected read/write enabled."
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-19T22:15:24.422Z
  session: local session omitted
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - appstore
created: 2026-10-04T16:06:19.487Z
updated: 2026-10-19T22:15:24.425Z
blockers:
  - id: evt_muvcl1ka_1z9ujn
    type: human
    reason: TIFF output save/open, direct single-image Finder drop/import, and folder Finder drop/enumeration/review now pass by human report and screenshot. The user approves the distinct single-image and folder interactions. Copying/opening the three selected folder photos after confirming the review remains unverified. The old generated removable sample was found only in Recovery/Quarantine, with no matching original under Assets; preserve recovery contents.
    action: In the open folder review, choose Import Selected to Library and confirm all three new photos import and open correctly after the dialog closes. Preserve the existing TIFF and single-image passes and the user-approved distinction between direct image import and folder review, then resume KRMA-818 to verification. Do not delete quarantine/recovery contents as part of this review.
    created_at: 2026-10-05T14:31:08.842Z
    resolved_at: 2026-10-19T21:58:22.713Z
    resolved_by: cli
order: yh
board: product
blocked_reason: TIFF output save/open, direct single-image Finder drop/import, and folder Finder drop/enumeration/review now pass by human report and screenshot. The user approves the distinct single-image and folder interactions. Copying/opening the three selected folder photos after confirming the review remains unverified. The old generated removable sample was found only in Recovery/Quarantine, with no matching original under Assets; preserve recovery contents.
blocked_action: In the open folder review, choose Import Selected to Library and confirm all three new photos import and open correctly after the dialog closes. Preserve the existing TIFF and single-image passes and the user-approved distinction between direct image import and folder review, then resume KRMA-818 to verification. Do not delete quarantine/recovery contents as part of this review.
blocked_from_status: ready
---

## Objective

Keep sandbox authority for every external file or folder alive until its read, copy, or write finishes, then balance/release access on success, failure, and cancellation.

## Context

Image and folder panel URLs flow through `AppKitFileDialogAdapter` into package imports. `PortableLibrarySession.startImportURLs` admits them to a worker, and `PortablePackageTransaction.stage(fileAt:)` reads them after the UI callback returns. Removable-media preflight starts a resolved volume scope but calls the asynchronous import handoff before its defer stops that scope. Window drops read file URLs from `NSPasteboard` and follow the import path without explicit scope handling.

Direct `NSSavePanel` writes in `DeriveCoordinator` and `LookSaveCoordinator` have no visible scope release after saving. Other export paths do explicit start/stop calls. Apple’s App Sandbox guidance says panel URLs carry system-started security-scoped access that must be stopped when use finishes. The actual grant for a file URL dropped on the preview window needs validation in a sandboxed app.

## Scope

- Own selected-file, selected-folder, dropped-file, dropped-folder, removable-volume, and selected-output access for the full duration of file enumeration and package copying/writing.
- Release every successfully started or system-granted scope once on success, read/write errors, cancellation, and superseded operations. Avoid unmatched or duplicate starts/stops.
- Keep removable-media source access read-only; the package remains the import destination.
- Add deterministic coverage for access ownership/lifetime where it can be expressed without App Sandbox, and record sandboxed run results.

## Acceptance criteria

- [ ] Panel-selected files and recursive folder imports complete in the sandbox after the panel closes.
- [ ] Window file and folder drops work in the sandbox, or the UI reports a clear unsupported/access error.
- [ ] Removable-media fallback grants remain active until each selected source has been copied into the package.
- [ ] Direct Look saves and other user-selected output writes release panel access after completion.
- [ ] Every scope is balanced on success, error, cancellation, and supersession; repeated operations do not exhaust file access grants.
- [ ] A signed sandboxed app run records the panel, window-drop, folder-recursion, removable-media, and output-save cases.

## Verification

Run focused import/workflow tests, the deterministic project verification lane required by the implementation ticket, and the sandboxed manual cases above.


### Comment — codex @ 2026-10-05T14:31:08.581Z

Implemented balanced scope ownership for panel/drop imports, removable media, selected outputs, Look saves, LUT scans, and settings. Added deterministic tests and signed sandbox run notes in docs/KRMA-818-SANDBOX-RUN.md. Verification passed: focused ExportCoordinatorTests (21), fast lane (1,534), serial lane (490), final signed app-store-build verify, and diff check. Commit cfb81be8. Signed runs passed panel multi-file import, folder recursion, and read-only removable-media import; an earlier signed build exported a TIFF. Final-build output save and Finder file/folder drops remain unverified because CUA could not find a Kromora window. One generated generated removable sample test import remains in the Library.


### Comment — codex @ 2026-10-19T21:54:12.483Z

Human review update, 2026-10-19: asked the user to export a photo as TIFF to a Desktop folder and open the exported file in Preview. The user responded "seems too", understood in context as confirmation that export finished and the TIFF opened correctly. Record the output-save/open case as passed by human report for the current running app. This is not an independent signing/build revision check or a fresh pass of Finder drops. Remaining live cases: single-image and folder drops from Finder onto the main preview; identify and clean up the previously generated test-only generated removable sample if it is still present.



### Comment — codex @ 2026-10-19T21:57:55.847Z

Human review update, 2026-10-19: the user dragged a single image from Finder onto the main preview and reports it imported directly. A Finder folder drop opened the import review dialog shown in the screenshot evidence: selected folder, 3 of 4 selected, 1 of 4 already in library, three new thumbnails selected and the duplicate marked In library. The user explicitly likes this distinction. Preserve direct single-image import and folder selection/duplicate review; do not homogenize these interactions as a supposed fix. Record single-image drop/import and folder drop/enumeration/review as passed by human observation. Completion of the three selected folder imports is still pending; the screenshot alone does not establish that the worker can read and copy their originals after review closes. Read-only package search found the old test-only generated removable sample only under Recovery/Quarantine/[asset id omitted]/Original/generated removable sample, with no matching original under Assets. It is not an active-asset original requiring deletion in this review. No recovery contents or library files were altered or deleted. The previously recorded TIFF export/open pass remains valid.


### Comment — codex @ 2026-10-19T21:58:22.319Z

Human follow-up, 2026-10-19: after showing the Finder folder review with three new photos selected, the user confirmed "It finished". Record successful folder-drop import completion by human report, in addition to the already recorded direct single-image drop/import and TIFF export/open passes. No separate per-photo opening check for all three folder items or exact running build/signing revision is claimed. The live file-access cases requested by the original Human blocker have now been observed, and the old generated generated removable sample is present only in Recovery/Quarantine rather than as an Assets original; leave recovery contents intact. Resume to verification with these bounded results. Preserve the user-approved behavior: a single image imports directly, while a folder opens selection/duplicate review.

## Agent log

- 2026-10-19T22:15:24.422Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Panel-selected files and recursive folder imports complete in the sandbox after the panel closes. (pass) — The signed sandbox run recorded multi-file panel import and recursive nested-folder import completing after the panel closed.
- [x] Window file and folder drops work in the sandbox, or the UI reports a clear unsupported/access error. (pass) — The 2026-10-19 human report says a single Finder image imported directly; a folder drop opened the selection and duplicate review, and the selected three-item import finished. The running Kromora app is ad-hoc signed with App Sandbox and user-selected read/write entitlements. The report does not pin the exact source revision or claim separate per-photo opening.
- [x] Removable-media fallback grants remain active until each selected source has been copied into the package. (pass) — The signed run imported a selected removable-media source, matched source and package SHA-256 values, and kept the source volume read-only. Deterministic tests cover grant transfer from scan preflight into the import request and retention through worker completion.
- [x] Direct Look saves and other user-selected output writes release panel access after completion. (pass) — Look and derived-Look save paths release access with defer. The scoped export test asserts the grant remains active through the write and releases afterward; the human report also confirms TIFF export and opening in Preview.
- [x] Every scope is balanced on success, error, cancellation, and supersession; repeated operations do not exhaust file access grants. (pass) — The shared scope owner releases once, including when explicitly released more than once. Import ownership releases on scheduler terminal outcomes or failed handoff; save paths use defer. Tests cover failed starts, queued-import cancellation, scan cancellation, successful import, and scoped output completion.
- [x] A signed sandboxed app run records the panel, window-drop, folder-recursion, removable-media, and output-save cases. (pass) — Coverage is recorded across the signed sandbox run and the 2026-10-19 human follow-up on the running App Sandbox app. The follow-up does not identify the exact source revision; the earlier output run predated the final exclusive-create writer.
Checks run:
- swift test --filter SecurityScopedResourceAccessTests|LibraryMediaWorkflowCoordinatorTests|PortableLibrarySessionTests|ExportCoordinatorTests|KromoraSettingsTests — exit 0; 90 tests passed.
- scripts/ci-tests.sh fast — exit 0; all 1,941 required parallel tests passed.
- scripts/ci-tests.sh serial — exit 0; 739 tests, 1 skipped, 0 failures.
- git show --check cfb81be8 — exit 0.
- Reviewed scope ownership in Sources/KromoraKit/Models/SecurityScopedResourceAccess.swift, Sources/KromoraKit/Models/PortableLibrarySession.swift, Sources/KromoraKit/ViewModels/LibraryMediaWorkflowCoordinator.swift, Sources/KromoraKit/ViewModels/ExportCoordinator.swift, Sources/KromoraKit/ViewModels/DeriveCoordinator.swift, and Sources/KromoraKit/ViewModels/LookSaveCoordinator.swift, plus related tests.
- Inspected the running Kromora app signature and entitlements: ad-hoc signed, App Sandbox enabled, and user-selected read/write enabled.
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: local session omitted
Summary: Counterpoint verification passed. Focused scope tests and fast/serial lanes passed with no findings; sandbox evidence is bounded by the signed run and the 2026-10-19 human follow-up.

Screenshot evidence omitted from this public ticket record because it contains personal photo-library content.
