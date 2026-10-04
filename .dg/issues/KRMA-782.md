---
id: KRMA-782
title: Add the Photos library usage description to the app Info.plist
type: task
status: ready
priority: high
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - privacy
  - packaging
created: 2026-10-03T19:24:04.202Z
updated: 2026-10-03T19:25:41.451Z
blockers: []
order: a0
board: product
---

## Objective

Make the packaged app declare why it accesses the Photos library, so a sandboxed build can request Photos authorization and App Store review does not reject the binary for a missing purpose string.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstream 3). `Sources/KromoraKit/Models/PhotosDelivery.swift` calls `PHPhotoLibrary.requestAuthorization(for: .readWrite)` and `performChanges` (it both imports from and delivers exports to Photos). The bundle metadata lives in `Sources/Kromora/Info.plist`, which `scripts/build-macos-app.sh` copies into the app. It currently has no `NSPhotoLibraryUsageDescription`. `scripts/verify-library-package-metadata.sh` already parses `Info.plist` with a small Python block and is run from CI.

## Scope

- Add `NSPhotoLibraryUsageDescription` to `Sources/Kromora/Info.plist` with a short, specific, user-facing sentence that covers both uses: choosing photos to import into a Kromora library, and saving exported images back to Photos.
- Add `NSPhotoLibraryAddUsageDescription` only if `PhotosDelivery.swift` or other code uses add-only authorization (`.addOnly`). If every request is `.readWrite`, do not add it.
- Extend `scripts/verify-library-package-metadata.sh` to fail when `NSPhotoLibraryUsageDescription` is missing or empty.
- Do not add any other permission strings in this ticket.

## Acceptance criteria

- [ ] `Sources/Kromora/Info.plist` contains a non-empty `NSPhotoLibraryUsageDescription` that names both import and export-to-Photos uses and does not claim anything Kromora does not do.
- [ ] `plutil -lint Sources/Kromora/Info.plist` passes.
- [ ] `scripts/verify-library-package-metadata.sh` passes with the key present and fails (verify once by temporarily removing it, then restore) when it is absent or blank.
- [ ] `scripts/build-macos-app.sh` still succeeds and `/usr/bin/plutil -extract NSPhotoLibraryUsageDescription raw .build/Kromora.app/Contents/Info.plist` prints the string.

## Verification

- Run `plutil -lint`, `scripts/verify-library-package-metadata.sh`, then `scripts/build-macos-app.sh` and the plutil extract above.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
