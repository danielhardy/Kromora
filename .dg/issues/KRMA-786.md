---
id: KRMA-786
title: Remove updater call sites and KROMORA_DIRECT_DISTRIBUTION conditionals from app code
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
created: 2026-10-03T19:24:14.541Z
updated: 2026-10-03T19:25:43.703Z
blockers: []
order: y
board: product
---

## Objective

Remove every use of the GitHub updater from app, menu, settings, and view-model code, along with the `#if KROMORA_DIRECT_DISTRIBUTION` blocks that guard them, so the updater is unreachable and the app builds identically with or without the flag.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstream 5). Kromora ships only through the Mac App Store, TestFlight, and source builds; the self-updater is being removed. Conditional blocks are in: `Sources/Kromora/KromoraApp.swift` (checkAutomaticallyIfDue, KromoraCommands(updateCoordinator:), the root view's `.sheet` for `UpdateSheet`, `@ObservedObject updateCoordinator`), `Sources/KromoraKit/Views/MenuCommands.swift` ("Check for Updates…"), `Sources/KromoraKit/Models/KromoraSettings.swift` (`automaticUpdateChecks`, its `Key`), `Sources/KromoraKit/Views/KromoraSettingsView.swift` (the toggle), `Sources/KromoraKit/ViewModels/AppViewModel.swift` (`updateCoordinator` property, its init). Find any others with `grep -rn KROMORA_DIRECT_DISTRIBUTION Sources`. Source-scanning tests read `Sources/Kromora/KromoraApp.swift` (`Tests/KromoraKitTests/MenuCommandTests.swift`, `KromoraAboutTests.swift`; the latter asserts the `Button("Check for Updates…")` text exists) and settings tests may mention update checks; update them to match.

## Scope

- Delete each `#if KROMORA_DIRECT_DISTRIBUTION … #endif` block and keep only the non-updater branch (the `#else` content), simplifying code that existed only to thread the coordinator through (for example, `KromoraRootView` no longer needs its `init` or `@ObservedObject`).
- Remove the persisted-setting key `automaticUpdateChecks` from `KromoraSettings` and any reset/defaults logic.
- Do not delete the updater implementation files in this ticket (the next ticket does); they simply become uncompiled/unreferenced.
- Update affected tests so they still pass and assert nothing about updater UI.

## Acceptance criteria

- [ ] `grep -rn KROMORA_DIRECT_DISTRIBUTION Sources Tests` returns only matches inside the updater implementation files that are deleted by the next ticket (`UpdateCoordinator.swift`, `UpdateInstaller.swift`, `UpdateSheet.swift`, `ReleaseFeed.swift`, `AppVersion.swift`) and `UpdateTests.swift`.
- [ ] No menu item, settings toggle, sheet, or launch-time check refers to updates.
- [ ] `swift build` succeeds and `scripts/ci-tests.sh fast` passes.
- [ ] `scripts/ci-tests.sh serial` passes (menu/settings UI tests live there).

## Verification

- Run `swift build`, `scripts/ci-tests.sh fast`, and `scripts/ci-tests.sh serial`.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
