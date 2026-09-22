---
id: KRMA-521
title: Replace root objectWillChange fan-in with Observation
type: task
status: ready
priority: high
agent: pi
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - performance
  - observation
created: 2026-09-21T20:33:02.623Z
updated: 2026-09-22T01:10:16.806Z
depends_on:
  - KRMA-520
estimate: 13
order: y
board: product
---

## Objective

Reduce whole-window invalidation by migrating high-frequency state to Observation and removing AppViewModel's root objectWillChange forwarding fan-in.

## Context and evidence

AppViewModel forwards objectWillChange from settings, library, collection, import, export, derive, look-save, and editor-document children. Each notification creates a main-actor Task that sends a later root notification, which has incorrect will-change timing and causes every observing view to reevaluate for thumbnail arrivals, metadata, scan ticks, and progress. ImageCollection.Item is already a high-frequency ObservableObject. LUTLibrary projections also recompute/filter/sort on access.

macOS 14 is the deployment floor. Mixed ObservableObject/@Observable migration is acceptable, but @Observable types must not be wrapped in @StateObject.

## Scope

- Migrate high-frequency models incrementally, beginning with ImageCollection/items, PhotosImportCoordinator, ExportCoordinator, and CanvasInteractionState.
- Update views to read observed properties directly and remove each corresponding root forwarding subscription.
- Delete the forwarding loop when all child consumers are migrated.
- Memoize LUT projections against a library revision.
- Instrument body evaluation for ContentView, inspector, and grid, and compare navigation/slider p95 before and after.

## Acceptance criteria

- [ ] No Task is created per child change notification.
- [ ] Thumbnail streaming and import/export progress do not reevaluate unrelated inspector or toolbar views.
- [ ] ContentView, inspector, and grid body evaluation counts demonstrate localized invalidation.
- [ ] Navigation and slider p95 are not regressed on the same host.
- [ ] Mixed migration has correct lifetime/ownership semantics and no @StateObject misuse for @Observable types.
- [ ] Fast, serial, and Observation-focused tests pass.

## Dependencies and coordination

Best after CQ-05 so legacy publishers are not carried forward. Coordinate explicitly with KRMA-512–515 and serialize changes to ContentView/ImageCollection with other UI work.

## Likely files and checks

AppViewModel initialization/forwarding, ImageCollection.swift, child coordinators, CanvasInteractionState, LUTLibrary, ContentView and relevant inspector/grid views, and body-count/performance tests.
