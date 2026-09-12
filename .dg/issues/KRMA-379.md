---
id: KRMA-379
title: Extract Photos import orchestration from ContentView
type: task
status: backlog
priority: high
labels:
  - architecture
  - import
  - ui
created: 2026-09-12T15:24:44.929Z
updated: 2026-09-12T15:24:45.557Z
order: zv
board: product
---

## Objective

Move the Apple Photos import workflow out of SwiftUI view code so ContentView only presents the picker, forwards user intent, and renders import state.

## Context

ContentView currently owns the import task, item iteration, cancellation, Photos provider transfer, PHAsset filename lookup, payload hashing, error handling, progress callbacks, and ImageCollection payload construction.

Relevant code:
- Sources/KromoraKit/Views/ContentView.swift:105-182
- Sources/KromoraKit/ViewModels/AppViewModel.swift:2172-2257
- Sources/KromoraKit/Models/ImageCollection.swift:939-1230

This makes the main window view responsible for asynchronous application workflow and makes the flow difficult to exercise without PhotosUI objects.

## Acceptance criteria

- [ ] ContentView contains no Photos import loop, hashing, PHAsset lookup, or per-item error/progress orchestration.
- [ ] Introduce a dedicated import controller/service/coordinator with an injectable Photos provider or transfer abstraction.
- [ ] The controller emits or updates value-based progress and failure state suitable for SwiftUI observation.
- [ ] Cancellation remains responsive between items and does not discard successfully imported items.
- [ ] Original filename preservation and one-time content-digest behavior remain unchanged.
- [ ] ImageCollection remains responsible for admitting durable imported payloads, while the import controller owns provider interaction.
- [ ] ContentView only presents PhotosPicker and connects its selection/cancel actions to the import boundary.
- [ ] Add focused tests for successful multi-item import, partial provider failure, cancellation, filename fallback, and digest propagation.
- [ ] Existing Photos import, durability, and performance tests remain passing; run dg validate and git diff --check.

## Out of scope

- Changing the managed library location or PhotoAsset identity rules.
- Changing the user-visible Photos import UX.
- Replacing ImageCollection's durable import APIs.
