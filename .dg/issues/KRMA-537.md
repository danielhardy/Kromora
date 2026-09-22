---
id: KRMA-537
title: Fix MediaVolumeImportTests managed-library source preservation
type: task
status: claimed
priority: high
agent: codex
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - fast-lane
  - regression
  - import
created: 2026-09-22T17:35:54.949Z
updated: 2026-09-22T17:38:03.958Z
estimate: 3
order: zr
board: product
claim:
  actor: codex
  session: 01MUCYJCJ9KFFHCETD
  claimed_at: 2026-09-22T17:38:03.957Z
  expires_at: 2026-09-22T18:38:03.957Z
  model: gpt-5.6-luna
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
