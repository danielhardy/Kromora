---
id: KRMA-803
title: Add a structural test that the Xcode project stays a thin packaging layer
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: New test passes and runs in the fast lane
      result: pass
      notes: 5 tests pass; scripts/ci-tests.sh fast exits 0 (lane skips only serial/optional filters, so the new suite is included).
    - criterion: Temporary violation makes the test fail; reverted
      result: pass
      notes: Extra App/Extra.swift failed the App-files test; duplicated Sources build entry in project.pbxproj failed the Sources-phase test. Both reverted; tree clean.
    - criterion: No concurrency escape hatches; warning-gate passes
      result: pass
      notes: warning-gate exits 0; test file has no opt-outs.
  checks_run:
    - swift test --filter XcodeProjectInvariantTests
    - temporary violation checks (App/ extra swift file; pbxproj extra Sources entry)
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh warning-gate
  findings:
    - "Non-blocking: objectBody regex stops at the first '};' so nested-brace objects could be truncated; works for the current pbxproj objects used."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-05T02:20:15.436Z
  session: 01MUUM9IPTHHU892JQ
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
updated: 2026-10-05T02:20:15.439Z
depends_on:
  - KRMA-802
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-05T02:14:11.576Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
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


### Comment — codex @ 2026-10-05T02:14:07.642Z

Added structural Xcode packaging tests for the Sources phase, KromoraKit-only package dependency, launcher line limits, App/Xcode Swift-file boundaries, and macOS 26 arm64 xcconfig settings. Focused suite, scripts/ci-tests.sh fast, and scripts/ci-tests.sh warning-gate passed; a temporary extra App Swift file correctly failed the invariant and was removed. Commit: 60e0331e.

## Agent log

- 2026-10-05T02:20:15.436Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] New test passes and runs in the fast lane (pass) — 5 tests pass; scripts/ci-tests.sh fast exits 0 (lane skips only serial/optional filters, so the new suite is included).
- [x] Temporary violation makes the test fail; reverted (pass) — Extra App/Extra.swift failed the App-files test; duplicated Sources build entry in project.pbxproj failed the Sources-phase test. Both reverted; tree clean.
- [x] No concurrency escape hatches; warning-gate passes (pass) — warning-gate exits 0; test file has no opt-outs.
Checks run:
- swift test --filter XcodeProjectInvariantTests
- temporary violation checks (App/ extra swift file; pbxproj extra Sources entry)
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh warning-gate
Findings:
- Non-blocking: objectBody regex stops at the first '};' so nested-brace objects could be truncated; works for the current pbxproj objects used.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUUM9IPTHHU892JQ
Summary: Verified: invariant tests pass, violations detected, fast lane and warning gate green.
