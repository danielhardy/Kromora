---
id: KRMA-788
title: Remove the KROMORA_DIRECT_DISTRIBUTION build flag from Package.swift
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
  - distribution
  - cleanup
created: 2026-10-03T19:24:16.687Z
updated: 2026-10-03T19:25:44.847Z
depends_on:
  - KRMA-787
blockers: []
order: zh
board: product
---

## Objective

Remove the environment-driven `KROMORA_DIRECT_DISTRIBUTION` compile flag so there is a single build configuration.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstream 5). `Package.swift` defines `distributionSwiftSettings` from `ProcessInfo.processInfo.environment["KROMORA_DIRECT_DISTRIBUTION"]` and adds it to the `KromoraKit`, `Kromora`, and `KromoraKitTests` targets' `swiftSettings`. `Tests/KromoraKitTests/PackageSettingsTests.swift` asserts package settings (Swift 6 mode and no opt-outs) and may reference the setting. `scripts/release-dmg.sh` also sets the flag (deleted by a later ticket; do not edit it here).

## Scope

- Delete `distributionSwiftSettings` and its comment; each target's `swiftSettings` becomes just `[.swiftLanguageMode(.v6)]`.
- Keep the `import Foundation` if the starter-look validation still needs it (it does).
- Update `PackageSettingsTests` if it refers to the flag; keep its Swift 6/no-escape-hatch checks intact.

## Acceptance criteria

- [ ] `grep -rn KROMORA_DIRECT_DISTRIBUTION Package.swift Sources Tests` returns nothing.
- [ ] Each target still declares `.swiftLanguageMode(.v6)`; `PackageSettingsTests` passes.
- [ ] `swift build` and `swift build -c release` succeed; `scripts/ci-tests.sh fast` passes.

## Verification

- Run `swift build`, `swift build -c release`, and `scripts/ci-tests.sh fast`.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
