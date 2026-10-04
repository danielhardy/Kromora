---
id: KRMA-791
title: Move AppDelegate into KromoraKit as a public KromoraAppDelegate
type: task
status: ready
priority: high
verification_agent: claude
human_review_required: false
verification_model: sonnet
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - architecture
  - launcher
created: 2026-10-03T19:24:21.312Z
updated: 2026-10-03T19:25:46.536Z
depends_on:
  - KRMA-786
blockers: []
order: zx
board: product
---

## Objective

Move the application delegate (activation policy, window-tabbing, termination flush-and-confirm flow) out of the `Kromora` executable target into `KromoraKit`, so both launchers can share it.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, architecture rule: "If it is application functionality, it belongs in KromoraKit"). Today `Sources/Kromora/KromoraApp.swift` contains `AppDelegate` (about 110 lines: init creates `AppViewModel(includeBundledLooks: true)` and `KromoraWindowAppearanceController`, `applicationShouldTerminate` flush logic with the "Couldn’t save edits before quitting" alert, etc.). The planned Xcode launcher must not duplicate this. `CLAUDE.md` says only `ContentView` and `KromoraCommands` are `public` in KromoraKit; this ticket adds one more public type and must update that sentence. Swift 6 language mode rules apply (see CLAUDE.md): the class is `@MainActor`, no escape hatches.

## Scope

- Create `Sources/KromoraKit/Presentation/KromoraAppDelegate.swift` containing a `public final class KromoraAppDelegate: NSObject, NSApplicationDelegate` with the exact existing behavior, exposing `public let viewModel: AppViewModel` (`AppViewModel` and `KromoraSettings` are already `public`).
- Replace the `AppDelegate` class in `Sources/Kromora/KromoraApp.swift` with `@NSApplicationDelegateAdaptor(KromoraAppDelegate.self)`; the rest of the file stays unchanged in this ticket.
- Update `Tests/KromoraKitTests/MenuCommandTests.swift` and `KromoraAboutTests.swift` source-scanning checks that read `Sources/Kromora/KromoraApp.swift` so they still make their intended assertions against the new location.
- Update the "public" sentence in `CLAUDE.md` (Layout section) to include `KromoraAppDelegate`.

## Acceptance criteria

- [ ] `Sources/Kromora/KromoraApp.swift` no longer defines an `NSApplicationDelegate`.
- [ ] Termination behavior is unchanged: the existing tests covering termination flush (`ApplicationShellCoordinator` / `AppViewModel` tests) pass without weakening.
- [ ] `swift build`, `scripts/ci-tests.sh fast`, and `scripts/ci-tests.sh serial` pass; no new compiler diagnostics and no concurrency escape hatches.
- [ ] `swift run` still starts a window (manual check; note the result in the handoff comment).

## Verification

- Run `swift build`, both CI lanes, and launch `swift run` once.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
