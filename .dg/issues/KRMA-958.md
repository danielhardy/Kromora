---
id: KRMA-958
title: Replace Task.detached { … }.value with @concurrent functions (Models and Views)
type: task
status: backlog
priority: low
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - nice-to-have
  - concurrency
  - cleanup
created: 2026-10-13T14:48:08.473Z
updated: 2026-10-13T14:48:36.964Z
parent: KRMA-922
depends_on:
  - KRMA-957
blockers: []
order: zzh
board: product
---

## Objective

Same as ticket KRMA-957, for `Sources/KromoraKit/Models/` and `Sources/KromoraKit/Views/`.

## Context

Review `.context/2026-10-13-release-readiness-review.md` "Nice to have: Task.detached". Sites: `Models/PortableLibrarySession.swift` ×6,
`Models/MediaVolume.swift` ×3, `Models/LUTLibrary.swift` ×3, `Models/RenderEngine.swift` ×2,
`Models/Thumbnails.swift`, `Models/OriginalThumbnailLoader.swift`, `Models/OriginalSettingsBundle.swift`,
`Models/LibraryMembershipMatcher.swift`, `Views/RemovableMediaSelectorView.swift`,
`Views/MaskDiscoveryOverlay.swift` (re-run `grep -rn "Task.detached" Sources/KromoraKit/Models
Sources/KromoraKit/Views` for the live list). Follow the mechanics described in ticket KRMA-957 (read it).
`RenderEngine` is an actor and the GPU/Core Image boundary: `CIImage`, `CIFilter` and `CIContext` must
stay inside it (see `docs/ENGINEERING_GUIDE.md`); the review notes the engine returns `CIImage` from
detached tasks (doc-drift ticket KRMA-965), so be careful there.

## Acceptance criteria

- [ ] No `Task.detached` under Models/ or Views/ except cases explicitly listed with a reason.
- [ ] `PortableLibrarySession` conversions keep the package-I/O scheduler as the way package writes are
      scheduled (do not replace `enqueuePackageIO` jobs).
- [ ] `RenderEngine` conversions keep every `CIImage`/`CIContext` use isolated to the actor.
- [ ] A structural test (modelled on `PackageSettingsTests`) fails if `Task.detached` is reintroduced in
      `Sources/KromoraKit` outside an allow-list of listed files.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).
- [ ] `scripts/ci-tests.sh serial` exits 0.
