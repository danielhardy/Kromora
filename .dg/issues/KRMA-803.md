---
id: KRMA-803
title: Add a structural test that the Xcode project stays a thin packaging layer
type: task
status: ready
priority: medium
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - xcode
  - architecture
  - tests
created: 2026-10-03T19:24:40.808Z
updated: 2026-10-03T19:25:53.290Z
depends_on:
  - KRMA-802
blockers: []
order: zzzx
board: product
---

## Objective

Make the plan's architectural invariant ("no production application logic exists only in the Xcode target") fail loudly in the test suite.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstream 8, "treated as an architectural invariant"). `Tests/KromoraKitTests/PackageSettingsTests.swift` is the model: it reads project files from disk and asserts structural properties that are not observable at runtime. `Xcode/Kromora.xcodeproj/project.pbxproj` is a text plist; a simple string/regex scan is sufficient and avoids a parser dependency.

## Scope

Add `Tests/KromoraKitTests/XcodeProjectInvariantTests.swift` that asserts, by scanning `Xcode/Kromora.xcodeproj/project.pbxproj` and the filesystem:

- The only `.swift` source in the target's Sources build phase is `App/KromoraApp.swift`.
- The only Swift package product dependency is `KromoraKit` (no `Kromora` executable product).
- `Sources/Kromora/KromoraApp.swift` and `App/KromoraApp.swift` are each at most 30 lines.
- No `.swift` files exist under `App/` other than `KromoraApp.swift` and no `.swift` files exist under `Xcode/`.
- The xcconfig files exist and `Base.xcconfig` sets `MACOSX_DEPLOYMENT_TARGET = 26.0` and `ARCHS = arm64`.

Failure messages must name the invariant ("All application functionality belongs in KromoraKit") so an agent that trips it knows what to do. Follow the existing source-reading test style for locating the package root.

## Acceptance criteria

- [ ] The new test passes and runs in the `fast` lane (`scripts/ci-tests.sh fast`; if the lane filters by name, add it to the right list).
- [ ] Temporarily adding a Swift file to the Xcode target's Sources phase (or a second `.swift` file in `App/`) makes the test fail; revert afterwards.
- [ ] No concurrency escape hatches; warning gate (`scripts/ci-tests.sh warning-gate`) passes.

## Verification

- Run the test, perform the temporary-violation check once, and run `scripts/ci-tests.sh fast`.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
