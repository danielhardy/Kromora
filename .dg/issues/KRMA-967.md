---
id: KRMA-967
title: Bound remaining unbounded Task.yield() polling loops in tests
type: task
status: backlog
priority: medium
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - tests
  - verification
created: 2026-10-13T16:43:29.825Z
updated: 2026-10-13T16:43:35.627Z
blockers: []
parent: KRMA-928
order: zzzv
board: product
---

## Objective

Bound remaining unbounded Task.yield() polling loops in tests

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — claude @ 2026-10-13T16:43:35.626Z

Remaining unbounded 'while ... Task.yield()' waits: DeriveCoordinatorTests:335; OpenImageDialogTests:125; AnalysisDebugPanelTests:83; PortableLibrarySessionTests:351,849,932,984; PhotosImportBatchCoordinatorTests:148; EditPersistenceIntegrationTests:409; MaskingPanelTests:66,98,125; AutoEnhancementCoordinatorTests:527. Replace with bounded waitUntil using TestSynchronizationError.timedOut (see RetouchWorkflowCoordinatorTests).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
