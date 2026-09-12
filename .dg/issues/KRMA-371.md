---
id: KRMA-371
title: Delete an image and its settings from the library
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-12T15:11:08.902Z
  session: 01MTYI60MWXD0ACGXI
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - library
created: 2026-09-12T03:48:32.679Z
updated: 2026-09-12T15:26:37.376Z
order: a0
board: product
commits:
  - f500869
---

## Objective

Allow the user to remove one or more images directly from the Library screen, along with their Kromora edit/settings state and derived library data.

## Context

The Library currently supports selection and culling but does not provide a deletion workflow. Deletion must keep the collection, persisted edit records, culling state, thumbnails/previews, and analysis/mask caches consistent across the current session and relaunch. It must also distinguish Kromora-owned managed copies from images referenced from a user source folder so an in-app library action cannot silently delete an external original.

## Acceptance criteria

- [ ] The Library screen exposes a clearly labeled Delete/Remove action for the focused image and selected images, with an appropriate keyboard/menu route if supported by the existing interaction model.
- [ ] A destructive confirmation identifies the image or image count and offers a cancel path that leaves the library unchanged.
- [ ] Confirmed deletion removes the item from the visible collection, selection, focus, culling state, and persisted edit/settings records.
- [ ] Kromora-owned managed originals and their derived library artifacts are removed through a recoverable macOS Trash path where practical; referenced originals outside the managed library are not deleted without an explicit product decision and user confirmation.
- [ ] Deleted items and their settings do not reappear after refresh or relaunch, and unrelated images/settings remain intact.
- [ ] Partial failures leave a consistent collection and surface an actionable error rather than silently losing state.
- [ ] Regression coverage exercises single-item deletion, multi-selection deletion, cancellation, persistence cleanup, selection reconciliation, managed versus referenced sources, and failure handling.

### Comment — codex @ 2026-09-12T15:26:37.375Z

Reconciled implementation and regression tests into f500869. Verification: swift test --filter LibraryDeletionTests (5/5), swift test --filter PhotoAnalysisCacheTests (4/4), dg validate, and git diff --check passed.

## Agent log

- 2026-09-12T15:11:08.902Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTYI60MWXD0ACGXI
Summary: Implemented confirmed single and multi-photo Library deletion with selection reconciliation, edit/analysis/mask/preview cleanup, managed-copy Trash handling, referenced-original protection, tombstone persistence, keyboard/menu routes, and failure reporting.
