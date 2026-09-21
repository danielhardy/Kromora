---
id: KRMA-383
title: Separate platform-facing library/settings models from domain models
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Classify Models types as domain/application/platform and document dependency direction
      result: pass
      notes: docs/MODEL_ARCHITECTURE.md adds the classification table and one-way dependency direction.
    - criterion: Move platform-specific responsibilities behind named adapters
      result: pass
      notes: NSImage thumbnails (PlatformThumbnailProvider), AppKit folder reveal (AppKitSettingsFolderAdapter), SwiftUI color observation (MaskInteractionPresentationBridge) each moved behind an explicit adapter.
    - criterion: Keep PhotoAsset/EditDocument/adjustment/selection/render-request values free of UI-framework deps
      result: pass
      notes: PhotoAsset.swift no longer imports ImageIO/UniformTypeIdentifiers; ModelDependencyTests asserts no AppKit/SwiftUI/Combine imports in the durable value files.
    - criterion: Preserve ImageCollection library/thumbnail/selection behavior and test seams
      result: pass
      notes: Renamed to ImageCollectionPresentationModel with a compatibility typealias ImageCollection; existing tests pass unchanged.
    - criterion: Preserve KromoraSettings bookmark behavior and MaskInteractionState gesture behavior
      result: pass
      notes: revealUserLookFolder moved to an extension with identical behavior; overlayColor became a computed bridge over a new @Published MaskOverlayColor, verified via MaskingWorkspaceTests including SwiftUI ColorPicker binding usage.
    - criterion: Add dependency checks so new domain files cannot silently acquire AppKit/SwiftUI
      result: pass
      notes: Tests/KromoraKitTests/ModelDependencyTests.swift enforces this at the source level (import scan + Models/ allowlist + named-owner check).
    - criterion: Existing tests remain passing; dg validate and git diff --check clean
      result: pass
      notes: swift test targeted subset, scripts/ci-tests.sh fast (371 tests) and serial lanes all pass; dg validate OK; git diff --check clean.
  checks_run:
    - swift build
    - swift test --filter ModelDependencyTests|PhotoAssetTests|MaskingWorkspaceTests|CoordinatorBoundaryTests
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - dg validate
    - git diff --check
  findings:
    - "Trivial: stray blank line left in Sources/KromoraKit/Models/PhotoAsset.swift before the closing brace, from moving discoveredFile/displayFileType out to the ImageIO adapter extension."
  fixes:
    - Removed the stray blank line in PhotoAsset.swift (no behavior change).
  verification_commits:
    - "6853276"
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-12T19:35:50.187Z
  session: 01MTYS841FH937MSQH
labels:
  - architecture
  - models
  - macos
created: 2026-09-12T15:24:49.830Z
updated: 2026-09-12T19:35:50.189Z
order: a0
board: product
commits:
  - "6853276"
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


### Comment — codex @ 2026-09-12T19:32:27.690Z

Implemented and committed as a29b4ee. Added model-boundary documentation and explicit platform/presentation owners; moved ImageIO PhotoAsset conveniences and Finder reveal behind adapters; removed UI-framework imports from durable values; preserved compatibility aliases and existing library/settings/masking behavior; added source-level dependency guardrails. Verification: swift test (1342 passed, 49 expected skips), dg validate OK, git diff --check clean.

## Agent log

- 2026-09-12T19:35:50.187Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Classify Models types as domain/application/platform and document dependency direction (pass) — docs/MODEL_ARCHITECTURE.md adds the classification table and one-way dependency direction.
- [x] Move platform-specific responsibilities behind named adapters (pass) — NSImage thumbnails (PlatformThumbnailProvider), AppKit folder reveal (AppKitSettingsFolderAdapter), SwiftUI color observation (MaskInteractionPresentationBridge) each moved behind an explicit adapter.
- [x] Keep PhotoAsset/EditDocument/adjustment/selection/render-request values free of UI-framework deps (pass) — PhotoAsset.swift no longer imports ImageIO/UniformTypeIdentifiers; ModelDependencyTests asserts no AppKit/SwiftUI/Combine imports in the durable value files.
- [x] Preserve ImageCollection library/thumbnail/selection behavior and test seams (pass) — Renamed to ImageCollectionPresentationModel with a compatibility typealias ImageCollection; existing tests pass unchanged.
- [x] Preserve KromoraSettings bookmark behavior and MaskInteractionState gesture behavior (pass) — revealUserLookFolder moved to an extension with identical behavior; overlayColor became a computed bridge over a new @Published MaskOverlayColor, verified via MaskingWorkspaceTests including SwiftUI ColorPicker binding usage.
- [x] Add dependency checks so new domain files cannot silently acquire AppKit/SwiftUI (pass) — Tests/KromoraKitTests/ModelDependencyTests.swift enforces this at the source level (import scan + Models/ allowlist + named-owner check).
- [x] Existing tests remain passing; dg validate and git diff --check clean (pass) — swift test targeted subset, scripts/ci-tests.sh fast (371 tests) and serial lanes all pass; dg validate OK; git diff --check clean.
Checks run:
- swift build
- swift test --filter ModelDependencyTests|PhotoAssetTests|MaskingWorkspaceTests|CoordinatorBoundaryTests
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh serial
- dg validate
- git diff --check
Findings:
- Trivial: stray blank line left in Sources/KromoraKit/Models/PhotoAsset.swift before the closing brace, from moving discoveredFile/displayFileType out to the ImageIO adapter extension.
Fixes:
- Removed the stray blank line in PhotoAsset.swift (no behavior change).
Verification commits:
- 6853276
Actor: claude
Resolved model: sonnet
Pickup session: 01MTYS841FH937MSQH
Summary: Verified: domain/platform model split is correctly scoped, tests/build/dg validate/git diff --check all pass; one cosmetic fix applied.
