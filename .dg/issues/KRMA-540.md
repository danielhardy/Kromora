---
id: KRMA-540
title: Fix OpenImageDialogTests URL import population and selection
type: task
status: done
priority: high
agent: codex
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The focused OpenImageDialogTests suite passes without timeout.
      result: pass
      notes: "swift test --filter OpenImageDialogTests: 3/3 passed, no timeout."
    - criterion: URL imports populate sorted URL-backed assets.
      result: pass
      notes: testOpenImagesAddsSortedURLBackedAssetsAndLoadsTheFirst passes; items sorted by display name and URL-backed.
    - criterion: Repeated URLs are deduplicated while single-file behavior remains intact.
      result: pass
      notes: testOpenImagesKeepsSingleFileBehaviorAndDeduplicatesRepeatedURLs passes; one asset for a repeated URL pair.
    - criterion: The first imported image is selected and loaded.
      result: pass
      notes: First sorted item opened via openPortableAsset; sourceImage/sourceName assertions pass.
    - criterion: The fast lane no longer reports this suite.
      result: pass
      notes: "Full scripts/ci-tests.sh fast run: all 3 OpenImageDialogTests cases pass cleanly; the lane's residual non-zero exit is from suites already tracked by KRMA-542 (AppViewModelTests, AutoAdjustmentTests, CanvasObservationTests, CopyPasteTests, DevelopInspectorTests, LibraryScanTests, ThumbnailSwitchLifecycleTests), unrelated to this change."
  checks_run:
    - swift build
    - swift test --filter OpenImageDialogTests (3/3 passed)
    - scripts/ci-tests.sh fast (full 1151-test deterministic-parallel lane; OpenImageDialogTests clean, remaining failures pre-existing and tracked by KRMA-542)
    - git diff --check
    - dg validate
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-22T19:44:59.813Z
  session: 01MUD2ZJ8GN22TVGVW
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - fast-lane
  - regression
  - open-image
created: 2026-09-22T17:35:56.384Z
updated: 2026-09-22T19:44:59.815Z
estimate: 3
order: y
board: product
---

## Objective

Restore open-image URL import population, ordering, deduplication, and initial selection.

## Evidence

The fast lane failed OpenImageDialogTests: the collection remained empty instead of containing first and later, repeated URLs produced zero assets instead of one, and the first selected image never arrived before timeout.

## Acceptance criteria

- [ ] The focused OpenImageDialogTests suite passes without timeout.
- [ ] URL imports populate sorted URL-backed assets.
- [ ] Repeated URLs are deduplicated while single-file behavior remains intact.
- [ ] The first imported image is selected and loaded.
- [ ] The fast lane no longer reports this suite.

### Comment — codex @ 2026-09-22T19:28:33.712Z

Recovered implementation changes into WIP commit 20cf4cb after the prior direct claimed-to-done transition. No ticket-specific commit attribution or independent verification is accepted; this issue is intentionally back in review for fresh verification.

## Agent log

- 2026-09-22T18:56:29.841Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The focused OpenImageDialogTests suite passes without timeout. (pass) — swift test --filter OpenImageDialogTests: 3/3 passed with no timeout.
- [x] URL imports populate sorted URL-backed assets. (pass) — openImages synchronously publishes the package-backed sorted browsing collection; focused assertions pass.
- [x] Repeated URLs are deduplicated while single-file behavior remains intact. (pass) — Repeated URL coverage passes with one URL-backed asset and the single image opens.
- [x] The first imported image is selected and loaded. (pass) — The first visible sorted collection item is selected and its source image loads.
- [x] The fast lane no longer reports this suite. (pass) — scripts/ci-tests.sh fast executed all three OpenImageDialogTests successfully; the lane still reports unrelated pre-existing failures already tracked by KRMA-537..541.
Checks run:
- swift test --filter OpenImageDialogTests
- swift test --filter 'OpenImageDialogTests|ImportedPhotoDurabilityTests|FileIntegrationBoundaryTests' (11/11 passed)
- scripts/ci-tests.sh fast (target OpenImageDialogTests pass; unrelated pre-existing failures remain)
- swift build
- git diff --check
- dg validate
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MUD1179DFS4T1WSK
Summary: Restored the Open Image dialog contract: URL imports publish synchronously into the sorted package-backed collection, repeated URLs deduplicate, dialog filename stems remain presentation-only, and the first visible asset is selected and loaded. Focused and adjacent import tests pass; the full fast lane runs OpenImageDialogTests successfully but retains unrelated pre-existing failures tracked by KRMA-537..541.

- 2026-09-22T19:44:59.813Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The focused OpenImageDialogTests suite passes without timeout. (pass) — swift test --filter OpenImageDialogTests: 3/3 passed, no timeout.
- [x] URL imports populate sorted URL-backed assets. (pass) — testOpenImagesAddsSortedURLBackedAssetsAndLoadsTheFirst passes; items sorted by display name and URL-backed.
- [x] Repeated URLs are deduplicated while single-file behavior remains intact. (pass) — testOpenImagesKeepsSingleFileBehaviorAndDeduplicatesRepeatedURLs passes; one asset for a repeated URL pair.
- [x] The first imported image is selected and loaded. (pass) — First sorted item opened via openPortableAsset; sourceImage/sourceName assertions pass.
- [x] The fast lane no longer reports this suite. (pass) — Full scripts/ci-tests.sh fast run: all 3 OpenImageDialogTests cases pass cleanly; the lane's residual non-zero exit is from suites already tracked by KRMA-542 (AppViewModelTests, AutoAdjustmentTests, CanvasObservationTests, CopyPasteTests, DevelopInspectorTests, LibraryScanTests, ThumbnailSwitchLifecycleTests), unrelated to this change.
Checks run:
- swift build
- swift test --filter OpenImageDialogTests (3/3 passed)
- scripts/ci-tests.sh fast (full 1151-test deterministic-parallel lane; OpenImageDialogTests clean, remaining failures pre-existing and tracked by KRMA-542)
- git diff --check
- dg validate
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUD2ZJ8GN22TVGVW
Summary: Independent verification confirms OpenImageDialogTests (URL import population, sort order, dedup, first-item selection) pass cleanly; full fast lane run shows no regressions attributable to this change, remaining failures are pre-existing and tracked by KRMA-542.
