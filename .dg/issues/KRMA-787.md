---
id: KRMA-787
title: Delete the updater implementation files and their tests
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
  - distribution
  - cleanup
created: 2026-10-03T19:24:15.375Z
updated: 2026-10-03T19:25:44.251Z
depends_on:
  - KRMA-786
blockers: []
order: z
board: product
---

## Objective

Delete the now-unreferenced GitHub updater implementation, its DMG installer, and its tests.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstream 5). After the previous ticket nothing references these files. They are compiled only under `KROMORA_DIRECT_DISTRIBUTION` (check the first line of each). Files: `Sources/KromoraKit/ViewModels/UpdateCoordinator.swift`, `Sources/KromoraKit/Presentation/UpdateInstaller.swift` (the only `Process()` user in the app, runs `hdiutil`), `Sources/KromoraKit/Views/UpdateSheet.swift`, `Sources/KromoraKit/Models/ReleaseFeed.swift`, `Sources/KromoraKit/Models/AppVersion.swift`, `Tests/KromoraKitTests/UpdateTests.swift`. Before deleting `AppVersion.swift`, confirm with grep that nothing outside the updater uses `AppVersion` (the About view reads the bundle directly); if something does, keep only what is used and explain in the commit message.

## Scope

- Delete the files above (`git rm`).
- Remove any leftover references: string literals pointing to the GitHub releases API, doc comments referencing the updater, and fixtures used only by `UpdateTests`.
- Do not touch `Package.swift` or scripts (separate tickets).

## Acceptance criteria

- [ ] The listed files no longer exist, and `grep -rniE "UpdateCoordinator|UpdateInstaller|UpdateSheet|ReleaseFeed|api\.github\.com|hdiutil" Sources Tests` returns nothing.
- [ ] `grep -rn "Process()" Sources` returns nothing.
- [ ] `swift build` succeeds and `scripts/ci-tests.sh fast` and `scripts/ci-tests.sh serial` pass.

## Verification

- Run the greps above plus `swift build`, `scripts/ci-tests.sh fast`, and `scripts/ci-tests.sh serial`.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
