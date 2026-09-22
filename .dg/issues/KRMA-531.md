---
id: KRMA-531
title: Simplify EditDocumentStore into a package-backed bounded cache
type: task
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - simplification
  - persistence
created: 2026-09-21T20:33:11.210Z
updated: 2026-09-22T13:27:15.266Z
depends_on:
  - KRMA-520
estimate: 8
order: zzv
board: product
---

## Objective

Replace the in-memory SwiftData projection and legacy path machinery in EditDocumentStore with a bounded package-backed EditDocument cache while preserving persistence coordination and error semantics.

## Context and evidence

In package mode SwiftData is only an in-memory projection; package sidecars are the source of truth. EditDocumentStore still carries ModelContainer setup, a try! container creation, path/bookmark relinking, legacy identity bridging, and standalone-store rebuild logic. It is about 867 lines and most of that serves the legacy mode removed by CQ-05.

## Scope

- After CQ-05, implement a plain bounded cache keyed by PortablePhotoAssetID in front of PortableLibraryPackage edit revisions.
- Preserve EditPersistenceCoordinator status, retry, coalescing, flush, and shutdown behavior.
- Preserve corrupt revision, write failure, flush-on-terminate, and relaunch round-trip semantics.
- Remove EditRecord and SwiftData dependencies only after confirming no remaining consumer.
- Remove canonicalPackageURL/legacy bridge/rebuild paths that no longer have callers.
- Replace try! with explicit failure handling everywhere touched.

## Acceptance criteria

- [ ] Persistence integration tests pass for corrupt revision, write failure, retries/coalescing, flush on terminate, and relaunch round-trip.
- [ ] The package sidecar remains the source of truth; cache eviction cannot lose unsaved edits.
- [ ] No try! remains in Sources.
- [ ] SwiftData/EditRecord dependencies are removed if unused, with no accidental target/resource changes.
- [ ] Fast, serial, and package persistence tests pass.

## Dependencies and coordination

Depends on CQ-05. CQ-20 should update engineering/storage documentation after this architecture is landed. Coordinate with EditorDocumentCoordinator and CQ-14 so document ownership is not duplicated.

## Likely files and checks

EditDocumentStore.swift, EditRecord.swift, EditPersistenceCoordinator, PortableLibraryPackage edit revisions, AppViewModel/editor lifecycle, persistence fixtures/tests, and package documentation.
