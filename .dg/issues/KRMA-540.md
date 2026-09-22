---
id: KRMA-540
title: Fix OpenImageDialogTests URL import population and selection
type: task
status: ready
priority: high
agent: codex
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - fast-lane
  - regression
  - open-image
created: 2026-09-22T17:35:56.384Z
updated: 2026-09-22T17:36:27.041Z
estimate: 3
order: zu
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
