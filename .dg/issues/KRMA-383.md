---
id: KRMA-383
title: Separate platform-facing library/settings models from domain models
type: task
status: backlog
priority: medium
labels:
  - architecture
  - models
  - macos
created: 2026-09-12T15:24:49.830Z
updated: 2026-09-12T15:24:50.411Z
order: zzh
board: product
---

## Objective

Clarify and enforce the boundary between platform-facing adapters and platform-independent domain/value types.

## Context

The Models directory currently contains both durable/domain concepts and UI/platform-facing observable objects. Examples include ImageCollection owning NSImage thumbnails and Combine publication, KromoraSettings importing AppKit, and MaskInteractionState importing SwiftUI.

Relevant code:
- Sources/KromoraKit/Models/ImageCollection.swift:1-3 and 80-200
- Sources/KromoraKit/Models/KromoraSettings.swift:1-3
- Sources/KromoraKit/Models/MaskInteractionState.swift:1-5
- Sources/KromoraKit/Models/PhotoAsset.swift and Sources/KromoraKit/Models/EditDocument.swift

## Acceptance criteria

- [ ] Classify current Models types as domain, application, or platform/presentation adapters and document the intended dependency direction.
- [ ] Move platform-specific responsibilities such as NSImage thumbnail publication, AppKit folder access, and SwiftUI interaction observation behind explicitly named adapters or presentation models.
- [ ] Keep PhotoAsset, EditDocument, adjustment values, selection values, render requests, and other durable value types free of unnecessary UI-framework dependencies.
- [ ] Preserve ImageCollection's current library behavior, thumbnail demand scheduling, selection semantics, and test seams.
- [ ] Preserve KromoraSettings bookmark/accessibility behavior and MaskInteractionState gesture behavior.
- [ ] Add package-level or source-level dependency checks so new domain files do not acquire AppKit/SwiftUI imports accidentally.
- [ ] Existing model, library, masking, settings, and render tests remain passing; run dg validate and git diff --check.

## Out of scope

- Removing Apple framework usage from the macOS application.
- Moving Core Image/Metal render-engine implementation out of its intentional resource boundary.
- Changing public APIs unless required to establish the documented separation.
