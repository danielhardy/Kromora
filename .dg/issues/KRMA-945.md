---
id: KRMA-945
title: Limit the `swift run` activation workaround to unbundled launches
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
  - should-fix
  - startup
parent: KRMA-922
created: 2026-10-13T14:47:54.782Z
updated: 2026-10-13T14:48:20.353Z
blockers: []
order: td9h1w6y
board: product
---

## Objective

The production (bundled, sandboxed) app should not call `setActivationPolicy(.regular)` /
`activate(ignoringOtherApps:)` or present a modal alert before `applicationDidFinishLaunching`.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding S4 (third bullet). `KromoraAppDelegate.init`
(`Sources/KromoraKit/Presentation/KromoraAppDelegate.swift` ~L15-21) unconditionally runs
`NSApplication.shared.setActivationPolicy(.regular)` and `NSApp.activate(ignoringOtherApps: true)`
because an unbundled `swift run` process otherwise starts as a background app and an `NSAlert` raised
from `AppViewModel.init` is invisible. In a bundled app `Info.plist` already makes it a regular app,
and `activate(ignoringOtherApps:)` is deprecated in favor of `activate()`.

## Acceptance criteria

- [ ] The workaround runs only when `Bundle.main.bundleIdentifier == nil` (unbundled `swift run`),
      behind a small named helper with a doc comment explaining why.
- [ ] `activate(ignoringOtherApps:)` is replaced with `NSApp.activate()` everywhere in
      `Sources/` (`grep -rn "ignoringOtherApps" Sources` is empty).
- [ ] A unit test covers the helper's predicate with an injected bundle identifier.
- [ ] `applicationDidFinishLaunching` still activates the app for both launch types.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).
