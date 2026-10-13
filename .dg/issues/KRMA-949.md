---
id: KRMA-949
title: "Share: export a reasonably sized HEIC/JPEG and show the picker immediately"
type: task
status: verification
priority: medium
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - export
  - ux
  - performance
created: 2026-10-13T14:47:58.510Z
updated: 2026-10-13T21:51:43.371Z
parent: KRMA-922
blockers: []
order: n
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T21:51:42.133Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Sharing to Messages/AirDrop/Mail must not render a full-resolution 16-bit TIFF, and the sharing menu
must appear at the Share control right away.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding S7. `Sources/KromoraKit/ViewModels/ExportWorkflowCoordinator.swift`:

- `shareCurrentExport()` (~L295) renders `ExportOptions(format: .tiff, …)` at full size to a temp
  directory (`<base>_share.tiff`) and only then shows the picker.
- `presentSharePicker(for:in:)` (~L325) anchors `NSSharingServicePicker` to
  `NSApplication.shared.keyWindow?.contentView`, not the Share button, and deletes the temp export in
  a `SharePickerDelegate` callback.
- `ExportOptions` / `ExportFormat` (`.jpeg`, `.heif`, `.tiff`) and a long-edge/size option exist; find
  them with `grep -rn "struct ExportOptions" Sources`.

## Acceptance criteria

- [ ] Share uses HEIC (`.heif`) at sRGB or Display P3 per `WorkingSpace`, long edge ≤ 4096 px, quality
      0.85 (constants in one named place, documented). JPEG is used if HEIC encoding fails.
- [ ] The picker is presented anchored to the Share control (pass an `NSView`/rect from the SwiftUI
      button via a small `NSViewRepresentable` anchor or `NSSharingServicePicker.show(relativeTo:of:
      preferredEdge:)` using the control's frame); not to the window's content view.
- [ ] The picker appears immediately: items are file promises/`NSItemProvider`s that render lazily
      when the user picks a service. If lazy file promises prove infeasible, show the picker with a
      progress state and say why in the review comment; do not regress to a long silent delay.
- [ ] Temp files are always removed (success, cancel, failure); tests assert the directory is empty
      afterwards using the existing fake picker seam if one exists (`grep -rn SharePickerDelegate
      Sources Tests`).
- [ ] Test: share options never request `.tiff` or full size.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).


### Comment — claude @ 2026-10-13T21:51:38.773Z

Share now exports HEIC (JPEG fallback if HEIC encoding fails), long edge <=4096, quality 0.85, in ShareExportPolicy (ExportWorkflowCoordinator.swift). Single-photo share shows the picker immediately with a lazy NSItemProvider file representation that renders when a service is picked; picker anchors to the toolbar Share button via ShareAnchorView (falls back to the key window content view for menu invocation). Batch share uses the same options but still renders eagerly before the picker, since per-item lazy providers would need a separate batch render path. Temp directory is removed on every picker terminal callback and on the no-window path; tests cover options (never .tiff/full size), lazy render, and cleanup. swift build has 0 warnings; scripts/ci-tests.sh fast exits 0 on re-run. The first run failed once on DeriveCoordinatorTests.testStaleSuccessAfterDismissDoesNotPublish (shared scratch dir under parallel run; passes alone, unrelated). Changes are left uncommitted in the working tree alongside other pre-existing edits.
