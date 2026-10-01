---
id: KRMA-728
title: "Last-known frames: eliminate flashes and make warm presentation instant"
type: feature
status: claimed
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
updated: 2026-10-01T23:13:58.746Z
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
claim:
  actor: codex
  session: 01MUQ5G6BGBB37I4KB
  claimed_at: 2026-10-01T23:12:33.532Z
  expires_at: 2026-10-02T00:12:33.532Z
  model: gpt-6-luna
  stage: implementation
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

- [x] KRMA-729 prevents cross-asset frames and establishes presentation sessions/telemetry.
- [x] KRMA-730 supplies deterministic content-addressed Look identity and delta-aware scans.
- [x] KRMA-731 replaces `PreviewDiskCache` with one atomic latest preview per asset.
- [x] KRMA-732 persists runtime thumbnail frames and transactionally stable cell geometry.
- [x] KRMA-733 adds bounded, disposable launch hints and visible-window hydration.
- [x] KRMA-734 passes the fault/performance qualification and updates durable documentation.
- [x] The performance and reliability budgets in the plan have recorded release evidence.

## Implementation notes

Dependency graph:

```text
KRMA-729 ----\
              -> KRMA-731 -> KRMA-732 -> KRMA-733 -> KRMA-734
KRMA-730 ----/                 ^                       ^
       \----------------------/-----------------------/
```

KRMA-728 depends on every child so the epic cannot complete early.

### Comment — claude @ 2026-10-01T22:35:36.640Z

Manual check by the owner on 2026-10-01 against 4bbc5c5f: ran the debug build (swift run), clicked through Library, Edit, and filmstrip selection, and nothing looked wrong. Debug builds run noticeably slower, so this is a functional smoke check and not timing evidence; release timings are the three captures in docs/TESTING.md. Screenshots were not captured.

### Comment — codex @ 2026-10-01T23:13:58.745Z

Epic handoff: KRMA-729 through KRMA-734 are verified done. The latest KRMA-734 report records passing fault, identity, rapid-navigation, cache-pressure, documentation, warning/build/test, Release benchmark, and drawable-count checks. Structural budgets pass; the first-pixel and grid wall-clock misses are recorded in docs/TESTING.md and tracked under ADR-LKF-001/KRMA-750. Updated this epic's acceptance checklist; no production work was added directly under the epic.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
