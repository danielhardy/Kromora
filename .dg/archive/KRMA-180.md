---
id: KRMA-180
title: Reduce duplication between addFromURLs and addFromMediaVolume
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: addFromURLs and addFromMediaVolume share one URL-backed import implementation
      result: pass
      notes: ImageCollection.addFromMediaVolume establishes the volume security scope and delegates to addFromURLs; no duplicate import loop remains.
    - criterion: URL-backed durability and media-volume behavior remain covered
      result: pass
      notes: MediaVolumeImportTests.testExplicitImportUsesURLBackedPhotoAssetsAndPreservesSource passed.
  checks_run:
    - swift test --filter OpenImageDialogTests|MediaVolumeImportTests (9 passed, 0 failed)
    - git diff --check (clean)
    - dg validate (OK)
    - swift test (752 executed, 34 skipped, 15 unrelated timing/lifecycle failures)
  findings: []
  fixes: []
  verification_commits:
    - ffcecca373d98b9dba17888a61994f31fd475515
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-04T14:46:57.243Z
  session: 01MTN2CZ6RUXWUNZ6E
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-04T13:38:03.144Z
updated: 2026-09-10T12:53:45.129Z
depends_on:
  - KRMA-178
order: d8xeorl8
board: product
commits:
  - ffcecca373d98b9dba17888a61994f31fd475515
---

## Objective

Reduce duplication between addFromURLs and addFromMediaVolume

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-04T14:46:57.248Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] addFromURLs and addFromMediaVolume share one URL-backed import implementation (pass) — ImageCollection.addFromMediaVolume establishes the volume security scope and delegates to addFromURLs; no duplicate import loop remains.
- [x] URL-backed durability and media-volume behavior remain covered (pass) — MediaVolumeImportTests.testExplicitImportUsesURLBackedPhotoAssetsAndPreservesSource passed.
Checks run:
- swift test --filter OpenImageDialogTests|MediaVolumeImportTests (9 passed, 0 failed)
- git diff --check (clean)
- dg validate (OK)
- swift test (752 executed, 34 skipped, 15 unrelated timing/lifecycle failures)
Findings:
- None
Fixes:
- None
Verification commits:
- ffcecca373d98b9dba17888a61994f31fd475515
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTN2CZ6RUXWUNZ6E
Summary: Verified that addFromMediaVolume now delegates all URL-backed import work to addFromURLs, leaving one shared implementation for validation, durable-library copying, identity/deduplication, metadata, and thumbnail setup.
