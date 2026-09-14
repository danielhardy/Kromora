---
id: KRMA-422
title: Fix selected export membership and original-source selection
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Selected export snapshots the selected asset IDs at operation start and exports no unselected assets.
      result: pass
      notes: AppViewModel.selectedBatchExportRequest builds value-only BatchItems from collection.selectedItems at call time; ExportCoordinator.performBatchExport copies that list into `operationItems` before any async suspension (ExportCoordinator.swift:451), so later selection changes cannot alter membership.
    - criterion: Each selected output is sourced from the original source path/data, not a stale edited preview or another asset.
      result: pass
      notes: ExportCoordinator.sourceAccess(for:) resolves ImageSource directly from item.url (with bookmark resolution) or item.data — never from a cached preview surface.
    - criterion: Selection changes during an in-flight export cannot alter the operation membership.
      result: pass
      notes: Verified directly by testSelectedExportSnapshotsMembershipBeforeSelectionChangesInFlight, which changes the live selection mid-export (gated encode) and asserts the exported set is unaffected. Passed standalone x3 in this run.
    - criterion: Per-item failures remain isolated and do not silently change the selected set.
      result: pass
      notes: The export loop's do/catch increments `failed` and continues over `operationItems` without mutating the snapshot; existing testBatchExportSkipsAndCountsFailuresWithoutAborting and testBatchHEIFEncoderFailureIsIsolatedToTheItem continue to pass.
    - criterion: The regression test asserts the exact exported IDs and source identity with diagnostics on mismatch.
      result: pass
      notes: testSelectedExportContainsExactlyTheLibrarySelectionAndUsesOriginals compares exact PhotoAssetID sets and source URLs, with a per-request diagnostics string attached to every assertion message.
    - criterion: Focused export tests and the full serial/fast lanes pass.
      result: pass
      notes: ExportCoordinatorTests 19/19; named regression run standalone x5 (0 failures); scripts/ci-tests.sh serial 375/375; scripts/ci-tests.sh fast 999/999; dg validate --json ok (only pre-existing unrelated warnings); git diff --check clean.
  checks_run:
    - swift build
    - swift test --filter ExportCoordinatorTests (19/19)
    - swift test --filter ExportCoordinatorTests/testSelectedExportContainsExactlyTheLibrarySelectionAndUsesOriginals (x5, all pass)
    - scripts/ci-tests.sh serial (375/375)
    - scripts/ci-tests.sh fast (999/999)
    - dg validate --json
    - git diff --check
  findings:
    - "process-hygiene: working tree contains substantial uncommitted source changes implementing KRMA-421's comparison-baseline fencing (AppViewModel.swift, ImageCollection.swift, ComparisonModeTests.swift, FakeRenderEngine.swift), even though KRMA-421 was completed to done claiming no code changes were needed. Filed as backlog child KRMA-427 (non-blocking to this issue; tests pass with the tree as-is)."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-13T16:51:37.226Z
  session: 01MU01RSHYT3KXCI17
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - testing
  - export
created: 2026-09-13T15:50:09.668Z
updated: 2026-09-13T16:51:37.227Z
order: a0
board: product
---

## Objective

Correct selected export coordination so an export contains exactly the current library selection and uses the intended original source bytes.

## Evidence

The full serial run on 2026-09-13 failed:
- ExportCoordinatorTests/testSelectedExportContainsExactlyTheLibrarySelectionAndUsesOriginals
- The failure was an XCTAssertTrue at Tests/KromoraKitTests/ExportCoordinatorTests.swift:457.

## Acceptance criteria

- Selected export snapshots the selected asset IDs at operation start and exports no unselected assets.
- Each selected output is sourced from the original source path/data, not a stale edited preview or another asset.
- Selection changes during an in-flight export cannot alter the operation membership.
- Per-item failures remain isolated and do not silently change the selected set.
- The regression test asserts the exact exported IDs and source identity with diagnostics on mismatch.
- Focused export tests and the full serial/fast lanes pass.

## Verification

Run the named test repeatedly, the complete ExportCoordinator suite, and the full serial and fast CI lanes.


### Comment — codex @ 2026-09-13T16:47:28.905Z

Implemented in commit 6696187. Export batches now explicitly snapshot their value-only work list before async rendering; source-folder first-open persistence uses the same identity policy as selected export. Expanded regression coverage asserts exact selected asset IDs, original source paths, per-request diagnostics, and immunity to selection changes during an in-flight export. Verification: named regression 5/5; ExportCoordinatorTests 19/19; scripts/ci-tests.sh serial 375/375; scripts/ci-tests.sh fast 999/999; dg validate --json OK; git diff --check passed.

## Agent log

- 2026-09-13T16:51:37.226Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Selected export snapshots the selected asset IDs at operation start and exports no unselected assets. (pass) — AppViewModel.selectedBatchExportRequest builds value-only BatchItems from collection.selectedItems at call time; ExportCoordinator.performBatchExport copies that list into `operationItems` before any async suspension (ExportCoordinator.swift:451), so later selection changes cannot alter membership.
- [x] Each selected output is sourced from the original source path/data, not a stale edited preview or another asset. (pass) — ExportCoordinator.sourceAccess(for:) resolves ImageSource directly from item.url (with bookmark resolution) or item.data — never from a cached preview surface.
- [x] Selection changes during an in-flight export cannot alter the operation membership. (pass) — Verified directly by testSelectedExportSnapshotsMembershipBeforeSelectionChangesInFlight, which changes the live selection mid-export (gated encode) and asserts the exported set is unaffected. Passed standalone x3 in this run.
- [x] Per-item failures remain isolated and do not silently change the selected set. (pass) — The export loop's do/catch increments `failed` and continues over `operationItems` without mutating the snapshot; existing testBatchExportSkipsAndCountsFailuresWithoutAborting and testBatchHEIFEncoderFailureIsIsolatedToTheItem continue to pass.
- [x] The regression test asserts the exact exported IDs and source identity with diagnostics on mismatch. (pass) — testSelectedExportContainsExactlyTheLibrarySelectionAndUsesOriginals compares exact PhotoAssetID sets and source URLs, with a per-request diagnostics string attached to every assertion message.
- [x] Focused export tests and the full serial/fast lanes pass. (pass) — ExportCoordinatorTests 19/19; named regression run standalone x5 (0 failures); scripts/ci-tests.sh serial 375/375; scripts/ci-tests.sh fast 999/999; dg validate --json ok (only pre-existing unrelated warnings); git diff --check clean.
Checks run:
- swift build
- swift test --filter ExportCoordinatorTests (19/19)
- swift test --filter ExportCoordinatorTests/testSelectedExportContainsExactlyTheLibrarySelectionAndUsesOriginals (x5, all pass)
- scripts/ci-tests.sh serial (375/375)
- scripts/ci-tests.sh fast (999/999)
- dg validate --json
- git diff --check
Findings:
- process-hygiene: working tree contains substantial uncommitted source changes implementing KRMA-421's comparison-baseline fencing (AppViewModel.swift, ImageCollection.swift, ComparisonModeTests.swift, FakeRenderEngine.swift), even though KRMA-421 was completed to done claiming no code changes were needed. Filed as backlog child KRMA-427 (non-blocking to this issue; tests pass with the tree as-is).
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MU01RSHYT3KXCI17
