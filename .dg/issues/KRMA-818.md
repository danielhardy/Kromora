---
id: KRMA-818
title: Balance sandbox access lifetimes for panel-selected and dropped URLs
type: task
status: review
priority: high
human_review_required: false
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - appstore
created: 2026-10-04T16:06:19.487Z
updated: 2026-10-05T14:31:08.842Z
blockers:
  - id: evt_muvcl1ka_1z9ujn
    type: human
    reason: Final signed UI checks are incomplete because CUA could not access a Kromora window for the final output save or Finder drops.
    action: On the signed Release build, save a TIFF into an external folder and verify it; drag one image and one folder from Finder onto the preview and confirm each import or a clear access error; remove the test-only removable.png from Library using Delete to Trash.
    created_at: 2026-10-05T14:31:08.842Z
order: yh
board: product
blocked_reason: Final signed UI checks are incomplete because CUA could not access a Kromora window for the final output save or Finder drops.
blocked_action: On the signed Release build, save a TIFF into an external folder and verify it; drag one image and one folder from Finder onto the preview and confirm each import or a clear access error; remove the test-only removable.png from Library using Delete to Trash.
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

Implemented balanced scope ownership for panel/drop imports, removable media, selected outputs, Look saves, LUT scans, and settings. Added deterministic tests and signed sandbox run notes in docs/KRMA-818-SANDBOX-RUN.md. Verification passed: focused ExportCoordinatorTests (21), fast lane (1,534), serial lane (490), final signed app-store-build verify, and diff check. Commit cfb81be8. Signed runs passed panel multi-file import, folder recursion, and read-only removable-media import; an earlier signed build exported a TIFF. Final-build output save and Finder file/folder drops remain unverified because CUA could not find a Kromora window. One generated removable.png test import remains in the Library.
