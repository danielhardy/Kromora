---
id: KRMA-792
title: Add a public KromoraScene and reduce the SwiftPM launcher to a tiny shim
type: task
status: done
priority: high
verification_agent: claude
human_review_required: false
verification_model: sonnet
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Launcher at most 25 lines, only adaptor and KromoraScene
      result: pass
      notes: 11 lines
    - criterion: Structural launcher-size test exists and passes
      result: pass
      notes: PackageSettingsTests.testLauncherRemainsAThinShim
    - criterion: Behavior unchanged (window sizes, About, Settings, commands)
      result: pass
      notes: Scene body is a verbatim move; source-scan tests retargeted
    - criterion: swift build, fast and serial lanes pass; no escape hatches
      result: pass
      notes: fast 1522 tests, serial 490 tests, 0 failures
  checks_run:
    - swift build
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-04T18:34:38.489Z
  session: 01MUU5JFF3736PLEKG
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - architecture
  - launcher
created: 2026-10-03T19:24:22.895Z
updated: 2026-10-04T18:34:38.493Z
depends_on:
  - KRMA-791
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-04T18:25:54.760Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
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


### Comment — codex @ 2026-10-04T18:25:54.303Z

Implemented KromoraScene in KromoraKit, reduced the launcher to 11 lines, updated source scans and the architecture guide, and added the launcher structure guard. Checks passed: swift build, fast lane (1522 tests), serial lane (490 tests), packaged app build, swift run, and About/Settings UI smoke check. Commit: 5aeb69ec.

## Agent log

- 2026-10-04T18:34:38.489Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Launcher at most 25 lines, only adaptor and KromoraScene (pass) — 11 lines
- [x] Structural launcher-size test exists and passes (pass) — PackageSettingsTests.testLauncherRemainsAThinShim
- [x] Behavior unchanged (window sizes, About, Settings, commands) (pass) — Scene body is a verbatim move; source-scan tests retargeted
- [x] swift build, fast and serial lanes pass; no escape hatches (pass) — fast 1522 tests, serial 490 tests, 0 failures
Checks run:
- swift build
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh serial
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUU5JFF3736PLEKG
