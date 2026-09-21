---
id: KRMA-504
title: Share should export all selected thumbnail-strip photos
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Sharing a multi-selection exports all selected photos.
      result: pass
      notes: The Edit toolbar now uses a selection-aware Share route; selections larger than one call exportSelectedDialog, which snapshots collection.selectedItems and runs the existing batch exporter.
    - criterion: The batch Share flow asks for a destination location only, not an output file name.
      result: pass
      notes: Multi-selection Share reaches ExportCoordinator.batchExportDialog, whose NSOpenPanel chooses a folder and never presents NSSavePanel.
    - criterion: Output names are generated from the selected photos and collisions remain safe.
      result: pass
      notes: The existing selected-item batch pipeline remains responsible for source-based naming and unique destination reservation.
    - criterion: Progress, cancellation, and individual export failures behave as they do for other batch exports.
      result: pass
      notes: Share reuses performBatchExport without changing its progress, cancellation, or per-item failure handling.
    - criterion: Single-photo Share remains functional.
      result: pass
      notes: Zero or one selected item keeps the existing exportDialog save-panel route.
    - criterion: Focused export/share tests and dg validate pass.
      result: pass
      notes: Focused tests, full swift test, and dg validate all passed.
  checks_run:
    - swift test --filter AppViewModelTests.testShareUsesSinglePhotoFlowUntilThereIsARealMultiSelection|MenuCommandTests.testViewMenuRoutesRelocatedEditorActionsAndKeepsComparisonToolbarStable|ExportCoordinatorTests.testSelectedExportContainsExactlyTheLibrarySelectionAndUsesOriginals|ExportCoordinatorTests.testBatchExportSkipsAndCountsFailuresWithoutAborting|ExportCoordinatorTests.testBatchExportWritesEveryImage (5 passed)
    - swift test (1570 passed, 55 skipped, 0 failures)
    - dg validate (OK; existing unknown-model warnings only)
    - git diff --check (clean)
  findings: []
  fixes: []
  verification_commits:
    - ad194d4
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-21T04:30:13.663Z
  session: 01MUAQNRZBDNHKK460
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - export
  - share
  - selection
created: 2026-09-21T02:40:11.574Z
updated: 2026-09-21T04:30:13.665Z
order: a0
board: product
commits:
  - ad194d4
---

## Objective

Make Share export every photo selected in the thumbnail strip, not only the active photo.

## Context

Selecting multiple photos in the Edit thumbnail strip and choosing Share currently exports only one photo. Batch Share should use the existing selected-item export path and ask for a destination location once, rather than asking the user to provide a file name.

## Requirements

1. When more than one thumbnail is selected, Share exports every selected photo in the current selection.
2. Present a directory/location chooser for batch Share; do not present a single-file name prompt.
3. Reuse the existing batch export pipeline, including saved edits, output naming, collision handling, progress, cancellation, and per-item failure reporting.
4. Preserve single-photo Share behavior unless it already uses the same location-based flow.
5. Add regression coverage for selection count, destination-dialog mode, output count, and mixed per-item success/failure.

## Acceptance criteria

- [ ] Sharing a multi-selection exports all selected photos.
- [ ] The batch Share flow asks for a destination location only, not an output file name.
- [ ] Output names are generated from the selected photos and collisions remain safe.
- [ ] Progress, cancellation, and individual export failures behave as they do for other batch exports.
- [ ] Single-photo Share remains functional.
- [ ] Focused export/share tests and dg validate pass.

## Implementation notes

Trace the Share toolbar action and its selection source separately from the existing File-menu batch export command. Ensure the active thumbnail is not accidentally substituted for the full selected set.

## Agent log

- 2026-09-21T04:30:13.663Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Sharing a multi-selection exports all selected photos. (pass) — The Edit toolbar now uses a selection-aware Share route; selections larger than one call exportSelectedDialog, which snapshots collection.selectedItems and runs the existing batch exporter.
- [x] The batch Share flow asks for a destination location only, not an output file name. (pass) — Multi-selection Share reaches ExportCoordinator.batchExportDialog, whose NSOpenPanel chooses a folder and never presents NSSavePanel.
- [x] Output names are generated from the selected photos and collisions remain safe. (pass) — The existing selected-item batch pipeline remains responsible for source-based naming and unique destination reservation.
- [x] Progress, cancellation, and individual export failures behave as they do for other batch exports. (pass) — Share reuses performBatchExport without changing its progress, cancellation, or per-item failure handling.
- [x] Single-photo Share remains functional. (pass) — Zero or one selected item keeps the existing exportDialog save-panel route.
- [x] Focused export/share tests and dg validate pass. (pass) — Focused tests, full swift test, and dg validate all passed.
Checks run:
- swift test --filter AppViewModelTests.testShareUsesSinglePhotoFlowUntilThereIsARealMultiSelection|MenuCommandTests.testViewMenuRoutesRelocatedEditorActionsAndKeepsComparisonToolbarStable|ExportCoordinatorTests.testSelectedExportContainsExactlyTheLibrarySelectionAndUsesOriginals|ExportCoordinatorTests.testBatchExportSkipsAndCountsFailuresWithoutAborting|ExportCoordinatorTests.testBatchExportWritesEveryImage (5 passed)
- swift test (1570 passed, 55 skipped, 0 failures)
- dg validate (OK; existing unknown-model warnings only)
- git diff --check (clean)
Findings:
- None
Fixes:
- None
Verification commits:
- ad194d4
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MUAQNRZBDNHKK460
Summary: Share now routes multi-selection through the existing selected-item batch exporter while preserving single-photo export.
