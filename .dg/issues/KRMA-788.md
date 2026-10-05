---
id: KRMA-788
title: Remove the KROMORA_DIRECT_DISTRIBUTION build flag from Package.swift
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: grep -rn KROMORA_DIRECT_DISTRIBUTION Package.swift Sources Tests returns nothing
      result: pass
    - criterion: Each target still declares .swiftLanguageMode(.v6); PackageSettingsTests passes
      result: pass
      notes: Diff shows all three targets with [.swiftLanguageMode(.v6)]; PackageSettingsTests ran within the fast lane.
    - criterion: swift build and swift build -c release succeed; scripts/ci-tests.sh fast passes
      result: pass
      notes: 1522 tests, exit 0
  checks_run:
    - grep KROMORA_DIRECT_DISTRIBUTION
    - swift build
    - swift build -c release
    - scripts/ci-tests.sh fast
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-04T20:15:27.683Z
  session: 01MUU9AXACHJ589AYQ
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - distribution
  - cleanup
created: 2026-10-03T19:24:16.687Z
updated: 2026-10-04T20:15:27.687Z
depends_on:
  - KRMA-787
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-04T20:11:20.781Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
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


### Comment — codex @ 2026-10-04T20:11:17.247Z

Removed the environment-driven distribution setting; all three targets now declare only Swift 6 language mode. The flag search is clean. The debug build, release build, and fast CI lane passed, including 1,522 tests. Commit: 76735a73.

## Agent log

- 2026-10-04T20:15:27.683Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] grep -rn KROMORA_DIRECT_DISTRIBUTION Package.swift Sources Tests returns nothing (pass)
- [x] Each target still declares .swiftLanguageMode(.v6); PackageSettingsTests passes (pass) — Diff shows all three targets with [.swiftLanguageMode(.v6)]; PackageSettingsTests ran within the fast lane.
- [x] swift build and swift build -c release succeed; scripts/ci-tests.sh fast passes (pass) — 1522 tests, exit 0
Checks run:
- grep KROMORA_DIRECT_DISTRIBUTION
- swift build
- swift build -c release
- scripts/ci-tests.sh fast
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUU9AXACHJ589AYQ
Summary: Verified: KROMORA_DIRECT_DISTRIBUTION removed from Package.swift; all targets declare only .swiftLanguageMode(.v6); builds and fast lane pass.
