---
id: KRMA-945
title: Limit the `swift run` activation workaround to unbundled launches
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The workaround runs only when Bundle.main.bundleIdentifier == nil (unbundled swift run), behind a small named helper with a doc comment explaining why.
      result: pass
      notes: promoteUnbundledLaunchIfNeeded gates both activation calls through needsUnbundledActivation; the helper documents the unbundled launch rationale.
    - criterion: activate(ignoringOtherApps:) is replaced with NSApp.activate() everywhere in Sources/ (grep -rn ignoringOtherApps Sources is empty).
      result: pass
      notes: Source search returned no ignoringOtherApps matches in Sources/.
    - criterion: A unit test covers the helper predicate with an injected bundle identifier.
      result: pass
      notes: UnbundledActivationTests covers nil and a nonnil identifier; the fast lane passed.
    - criterion: applicationDidFinishLaunching still activates the app for both launch types.
      result: pass
      notes: applicationDidFinishLaunching calls NSApp.activate() unconditionally.
    - criterion: "swift build is warning-free and Swift 6 mode stays clean (no @unchecked Sendable, nonisolated(unsafe), @preconcurrency, or #available branches)."
      result: pass
      notes: swift build exited 0 without warnings; none of the prohibited constructs occur in Sources/.
    - criterion: scripts/ci-tests.sh fast exits 0.
      result: pass
      notes: The fast lane completed all 2010 required tests and exited 0.
  checks_run:
    - swift build — passed with no warnings
    - scripts/ci-tests.sh fast — passed; 2010 required tests, exit 0
    - rg source check for ignoringOtherApps — no matches in Sources/
    - git diff --check -- Sources/KromoraKit/Presentation/KromoraAppDelegate.swift — passed
    - Swift 6 escape-hatch and availability check in Sources/ — no matches
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-15T12:51:39.685Z
  session: 01MV9J9SVAK3KCGMB9
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - startup
created: 2026-10-13T14:47:54.782Z
updated: 2026-10-15T12:51:39.689Z
parent: KRMA-922
blockers: []
order: a0
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


### Comment — claude @ 2026-10-15T06:42:44.946Z

Implemented: KromoraAppDelegate.needsUnbundledActivation(bundleIdentifier:) predicate + promoteUnbundledLaunchIfNeeded() (runs setActivationPolicy/activate only when Bundle.main.bundleIdentifier == nil); applicationDidFinishLaunching still calls NSApp.activate() for both launch types and no longer sets the policy. No ignoringOtherApps remains in Sources (it remains only in opt-in benchmark tests under Tests/, outside the criterion). Added UnbundledActivationTests. swift build clean. ci-tests.sh fast: first run failed on EditPersistenceIntegrationTests.testLongGestureCheckpointsIntermediateSnapshotsBeforeMouseUp (timing flake; passes alone), second run exit 0. Not committed.

## Agent log

- 2026-10-15T12:51:39.685Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The workaround runs only when Bundle.main.bundleIdentifier == nil (unbundled swift run), behind a small named helper with a doc comment explaining why. (pass) — promoteUnbundledLaunchIfNeeded gates both activation calls through needsUnbundledActivation; the helper documents the unbundled launch rationale.
- [x] activate(ignoringOtherApps:) is replaced with NSApp.activate() everywhere in Sources/ (grep -rn ignoringOtherApps Sources is empty). (pass) — Source search returned no ignoringOtherApps matches in Sources/.
- [x] A unit test covers the helper predicate with an injected bundle identifier. (pass) — UnbundledActivationTests covers nil and a nonnil identifier; the fast lane passed.
- [x] applicationDidFinishLaunching still activates the app for both launch types. (pass) — applicationDidFinishLaunching calls NSApp.activate() unconditionally.
- [x] swift build is warning-free and Swift 6 mode stays clean (no @unchecked Sendable, nonisolated(unsafe), @preconcurrency, or #available branches). (pass) — swift build exited 0 without warnings; none of the prohibited constructs occur in Sources/.
- [x] scripts/ci-tests.sh fast exits 0. (pass) — The fast lane completed all 2010 required tests and exited 0.
Checks run:
- swift build — passed with no warnings
- scripts/ci-tests.sh fast — passed; 2010 required tests, exit 0
- rg source check for ignoringOtherApps — no matches in Sources/
- git diff --check -- Sources/KromoraKit/Presentation/KromoraAppDelegate.swift — passed
- Swift 6 escape-hatch and availability check in Sources/ — no matches
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV9J9SVAK3KCGMB9
Summary: Counterpoint verification passed: all acceptance criteria hold; swift build and the fast CI lane pass, and no verification fixes or blockers were needed.
