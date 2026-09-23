---
id: KRMA-553
title: EditPackageFixture leaks temp library packages without cleanup
type: task
status: backlog
priority: low
creation_provenance:
  runner: pi
  model: unknown
  actor: pi
labels:
  - verification
created: 2026-09-23T12:39:30.292Z
updated: 2026-09-23T12:39:30.292Z
parent: KRMA-549
order: z
board: product
---

## Objective

Give EditPackageFixture (Tests/KromoraKitTests/Fixtures.swift, introduced by KRMA-549) a deterministic cleanup path so package-backed edit-store tests do not accumulate orphaned `KromoraEditFixture-*.kromoralibrary` directories in the system temp dir.

## Context

KRMA-549 counterpoint verification finding (non-blocking): every `EditPackageFixture()` creates a uniquely-named package under `FileManager.default.temporaryDirectory` and acquires a writer lease, but nothing ever removes it. `TempDirectoryTestCase` cleans only its own `tempDirectory`. Dozens of tests across LUT/Comparison/Crop/EditPersistence/Masking/LibraryDeletion suites instantiate fixtures, so repeated runs leak packages (each with a stale lease file) into tmp.

## Acceptance criteria

- [ ] Fixture packages are created under the owning test case's temp directory (or tracked for removal in tearDown).
- [ ] A full run of the KRMA-549 suite set leaves no `KromoraEditFixture-*` residue in the system temp dir.
- [ ] No product behavior, public API, or schema changes.

## Implementation notes

<!-- Approach, constraints, links -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
