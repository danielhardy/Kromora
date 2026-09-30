---
id: KRMA-728
title: "Last-known frames: eliminate flashes and make warm presentation instant"
type: feature
status: ready
priority: urgent
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - architecture
  - performance
  - reliability
  - preview
  - thumbnails
created: 2026-09-30T13:19:17.755Z
updated: 2026-09-30T17:24:21.433Z
depends_on:
  - KRMA-729
  - KRMA-730
  - KRMA-731
  - KRMA-732
  - KRMA-733
  - KRMA-734
blockers: []
estimate: 40
order: zh
board: product
context:
  files:
    - Sources/KromoraKit/Models/PreviewDiskCache.swift
    - Sources/KromoraKit/Models/PortablePackageMaintenance.swift
    - Sources/KromoraKit/Models/ImageCollection.swift
    - Sources/KromoraKit/ViewModels/PreviewPresentationCoordinator.swift
    - Sources/KromoraKit/ViewModels/PreviewAdmissionCoordinator.swift
    - Sources/KromoraKit/ViewModels/EditedThumbnailCoordinator.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
  docs:
    - .context/last-known-frame-plan.md
    - docs/APP_ARCHITECTURE.md
    - docs/ENGINEERING_GUIDE.md
    - docs/STORAGE_POLICY.md
    - docs/TESTING.md
  issues:
    - KRMA-729
    - KRMA-730
    - KRMA-731
    - KRMA-732
    - KRMA-733
    - KRMA-734
  commands:
    - dg context KRMA-728
    - dg validate
---

## Objective

Deliver the reviewed last-known-frame architecture so Edit, Library, and filmstrip paint the
selected photo from trustworthy persisted pixels immediately, refine at most once, and remain safe
under cache loss or corruption.

## Context

The executable design is `.context/last-known-frame-plan.md`. It replaces the current exact-key
preview disk cache rather than adding another preview layer, reuses package content hashes for Look
identity, wires the existing packed thumbnail store into runtime, persists final cell geometry, and
adds bounded launch hydration.

This epic is complete only when its children are verified. Implement children in dependency order;
do not implement production code directly under the epic.

## Non-negotiable product invariants

- A newly selected asset never displays the prior asset.
- A warm surface shows one same-asset candidate and at most one refinement.
- Cached pixels skip rendering only after exact current inputs are resolved.
- Provisional pixels are inert for histogram, scopes, comparison, tools, publication state, and
  cache writes.
- Grid/filmstrip geometry is final before raster arrival.
- Derived-frame deletion/corruption only costs work; it never affects edit/package truth.
- No Core Image object leaves `RenderEngine`, no Swift 6 escape hatch is introduced, and no older
  macOS/Intel fallback is added.

## Acceptance criteria

- [ ] KRMA-729 prevents cross-asset frames and establishes presentation sessions/telemetry.
- [ ] KRMA-730 supplies deterministic content-addressed Look identity and delta-aware scans.
- [ ] KRMA-731 replaces `PreviewDiskCache` with one atomic latest preview per asset.
- [ ] KRMA-732 persists runtime thumbnail frames and transactionally stable cell geometry.
- [ ] KRMA-733 adds bounded, disposable launch hints and visible-window hydration.
- [ ] KRMA-734 passes the full fault/performance qualification and updates durable documentation.
- [ ] The performance and reliability budgets in the plan have recorded release evidence.

## Implementation notes

Dependency graph:

```text
KRMA-729 ----\
              -> KRMA-731 -> KRMA-732 -> KRMA-733 -> KRMA-734
KRMA-730 ----/                 ^                       ^
       \----------------------/-----------------------/
```

KRMA-728 depends on every child so the epic cannot complete early.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
