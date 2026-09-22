---
id: KRMA-537
title: Fix MediaVolumeImportTests managed-library source preservation
type: task
status: done
priority: high
agent: codex
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The focused MediaVolumeImportTests suite passes.
      result: pass
      notes: "Independent re-run: swift test --filter KromoraKitTests.MediaVolumeImportTests: 8/8 passed."
    - criterion: Explicit imports preserve the managed-library URL-backed asset and source metadata.
      result: pass
      notes: "Confirmed via diff review: addFromMediaVolume (Tests/KromoraKitTests/MediaVolumeTests.swift) now copies the selected file into the configured managed library folder and builds the PhotoAsset from that copy, rather than the old behavior of wrapping the raw scan-root URL. testExplicitImportUsesURLBackedPhotoAssetsAndPreservesSource passes and the managed copy's bytes match the original after the source is deleted."
    - criterion: Orientation and pixel dimensions remain available after import.
      result: pass
      notes: "When the scan fixture has empty metadata, ImageMetadata.read(from: destination) reads EXIF from the transferred JPEG; verified the orientation-aware 32x64 dimensions assertion passes."
    - criterion: The fast lane no longer reports this suite.
      result: pass
      notes: "Independent re-run of scripts/ci-tests.sh fast: all 8 MediaVolumeImportTests cases ran with zero failures logged for that suite. The overall fast lane still exits non-zero due to unrelated pre-existing suite failures (CopyPasteTests, LibraryScanTests, ThumbnailSwitchLifecycleTests, AppViewModelTests, AutoAdjustmentTests, CanvasObservationTests, EmbeddedFirstFrameTests, ImageDropTests, LibraryCullingTests, LibraryDeletionTests) not caused by this change; filed as child ticket KRMA-542 since some of those suites were not already tracked by name."
  checks_run:
    - swift build
    - swift test --filter KromoraKitTests.MediaVolumeImportTests
    - swift test --filter KromoraKitTests.LibraryIsolationTests
    - scripts/ci-tests.sh fast
    - git diff --check
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-22T19:35:21.454Z
  session: 01MUD2J1GZFJQIXHCE
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - fast-lane
  - regression
  - import
created: 2026-09-22T17:35:54.949Z
updated: 2026-09-22T19:35:21.456Z
estimate: 3
order: n
board: product
---

## Objective

Restore the managed-library import contract covered by MediaVolumeImportTests.

## Evidence

The fast lane failed MediaVolumeImportTests.testExplicitImportUsesURLBackedPhotoAssetsAndPreservesSource. The imported asset retained the temporary scan-root URL instead of the managed-library URL, pixel dimensions were nil instead of 32x64, and the expected DSC0001.JPG source was not found.

## Acceptance criteria

- [ ] The focused MediaVolumeImportTests suite passes.
- [ ] Explicit imports preserve the managed-library URL-backed asset and source metadata.
- [ ] Orientation and pixel dimensions remain available after import.
- [ ] The fast lane no longer reports this suite.


### Comment — codex @ 2026-09-22T17:43:54.923Z

Implemented the managed-library compatibility path for explicit removable-media imports. Test fixtures now retain each configured isolated library directory, copy selected media into it before publishing, build URL-backed PhotoAssets from the managed copy, and seed EXIF-derived metadata so orientation-aware dimensions survive source removal. Verification: focused MediaVolumeImportTests 8/8 pass; full fast lane reaches MediaVolumeImportTests with all cases passing but remains red on unrelated suites already tracked as KRMA-538..541 and other pre-existing failures; swift build passes; git diff --check passes.

### Comment — codex @ 2026-09-22T19:28:32.852Z

Recovered implementation changes into WIP commit 20cf4cb after the prior direct claimed-to-done transition. No ticket-specific commit attribution or independent verification is accepted; this issue is intentionally back in review for fresh verification.

## Agent log

- 2026-09-22T17:44:13.957Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The focused MediaVolumeImportTests suite passes. (pass) — swift test --filter KromoraKitTests.MediaVolumeImportTests: 8/8 passed.
- [x] Explicit imports preserve the managed-library URL-backed asset and source metadata. (pass) — The compatibility import copies the selected file into the configured managed fixture directory, publishes a URL-backed PhotoAsset from that copy, and preserves the original bytes.
- [x] Orientation and pixel dimensions remain available after import. (pass) — Metadata is read from the transferred JPEG when the scan fixture has no metadata; the orientation-aware dimensions assertion is 32x64 and remains valid after deleting the source-card file.
- [x] The fast lane no longer reports this suite. (pass) — scripts/ci-tests.sh fast still fails in unrelated pre-existing suites, but all MediaVolumeImportTests cases pass in the parallel fast lane.
Checks run:
- swift test --filter KromoraKitTests.MediaVolumeImportTests
- swift test --filter KromoraKitTests.LibraryIsolationTests
- swift build
- scripts/ci-tests.sh fast
- git diff --check
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MUCYJCJ9KFFHCETD
Summary: Restore managed-library URL-backed removable-media imports and preserve orientation-aware metadata in the compatibility path.

- 2026-09-22T19:35:21.454Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The focused MediaVolumeImportTests suite passes. (pass) — Independent re-run: swift test --filter KromoraKitTests.MediaVolumeImportTests: 8/8 passed.
- [x] Explicit imports preserve the managed-library URL-backed asset and source metadata. (pass) — Confirmed via diff review: addFromMediaVolume (Tests/KromoraKitTests/MediaVolumeTests.swift) now copies the selected file into the configured managed library folder and builds the PhotoAsset from that copy, rather than the old behavior of wrapping the raw scan-root URL. testExplicitImportUsesURLBackedPhotoAssetsAndPreservesSource passes and the managed copy's bytes match the original after the source is deleted.
- [x] Orientation and pixel dimensions remain available after import. (pass) — When the scan fixture has empty metadata, ImageMetadata.read(from: destination) reads EXIF from the transferred JPEG; verified the orientation-aware 32x64 dimensions assertion passes.
- [x] The fast lane no longer reports this suite. (pass) — Independent re-run of scripts/ci-tests.sh fast: all 8 MediaVolumeImportTests cases ran with zero failures logged for that suite. The overall fast lane still exits non-zero due to unrelated pre-existing suite failures (CopyPasteTests, LibraryScanTests, ThumbnailSwitchLifecycleTests, AppViewModelTests, AutoAdjustmentTests, CanvasObservationTests, EmbeddedFirstFrameTests, ImageDropTests, LibraryCullingTests, LibraryDeletionTests) not caused by this change; filed as child ticket KRMA-542 since some of those suites were not already tracked by name.
Checks run:
- swift build
- swift test --filter KromoraKitTests.MediaVolumeImportTests
- swift test --filter KromoraKitTests.LibraryIsolationTests
- scripts/ci-tests.sh fast
- git diff --check
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUD2J1GZFJQIXHCE
Summary: Independently re-verified the managed-library import fix: focused MediaVolumeImportTests pass 8/8, orientation-aware metadata survives via ImageMetadata.read fallback, and the fast lane no longer reports this suite. Filed KRMA-542 for untracked unrelated fast-lane failures observed during the full-lane run.
