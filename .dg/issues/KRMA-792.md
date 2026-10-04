---
id: KRMA-792
title: Add a public KromoraScene and reduce the SwiftPM launcher to a tiny shim
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
created: 2026-10-03T19:24:22.895Z
updated: 2026-10-03T19:25:47.070Z
depends_on:
  - KRMA-791
blockers: []
order: zy
board: product
---

## Objective

Move the app's scenes (main window, About window, Settings, commands) into `KromoraKit` as a public `KromoraScene`, so each launcher is only a few lines.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, "Architecture" and "Target repository layout"). After the previous ticket, `Sources/Kromora/KromoraApp.swift` still defines `@main struct KromoraApp` with a `WindowGroup` (`.frame(minWidth: 800, minHeight: 500)`, `.defaultSize(1200x800)`), an About `Window`, `.commands { KromoraCommands(settings:) }`, a `Settings { … }` scene, and private helper views (`KromoraRootView`, `KromoraSettingsScene`). `@NSApplicationDelegateAdaptor` can only be declared on an `App`, not on a `Scene`, so the launcher keeps the adaptor and hands the delegate's view model to the scene:

```swift
@main struct KromoraApp: App {
    @NSApplicationDelegateAdaptor(KromoraAppDelegate.self) private var appDelegate
    var body: some Scene { KromoraScene(delegate: appDelegate) }
}
```

(Adjust the exact initializer if a cleaner public shape works, but the launcher must stay this small and must not need `AppViewModel` to be public.)

## Scope

- Add `public struct KromoraScene: Scene` in `Sources/KromoraKit/` taking the `KromoraAppDelegate` (or an opaque public handle it vends) and building exactly the scenes listed above, moving `KromoraRootView` and `KromoraSettingsScene` with it.
- Reduce `Sources/Kromora/KromoraApp.swift` to the imports, the adaptor, and `KromoraScene`; target at most 25 lines total.
- Add a structural test (alongside `PackageSettingsTests`) that fails if `Sources/Kromora/KromoraApp.swift` exceeds 30 lines or imports anything other than `SwiftUI` and `KromoraKit`; it should print a message pointing at the architecture rule.
- Update source-scanning tests that read the launcher to target the new locations; update the `CLAUDE.md` public-surface sentence and the Layout bullet for `Sources/Kromora/` (it should say: launcher only).

## Acceptance criteria

- [ ] `Sources/Kromora/KromoraApp.swift` is at most 25 lines and contains no scene, window, or delegate logic besides the adaptor and `KromoraScene`.
- [ ] The structural launcher-size test exists and passes.
- [ ] Behavior is unchanged: window sizes, About window, Settings, and menu commands behave the same (existing UI/menu tests pass unchanged except for path updates).
- [ ] `swift build`, `scripts/ci-tests.sh fast`, and `scripts/ci-tests.sh serial` pass; no concurrency escape hatches added.

## Verification

- Run `swift build`, both CI lanes, and launch `swift run`; open About and Settings once.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
