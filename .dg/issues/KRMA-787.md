---
id: KRMA-787
title: Delete the updater implementation files and their tests
type: task
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Listed files no longer exist; grep for UpdateCoordinator|UpdateInstaller|UpdateSheet|ReleaseFeed|api.github.com|hdiutil in Sources Tests returns nothing
      result: pass
      notes: Also no AppVersion or KROMORA_DIRECT_DISTRIBUTION references remain.
    - criterion: grep Process() in Sources returns nothing
      result: pass
    - criterion: swift build succeeds and ci-tests fast and serial pass
      result: pass
      notes: fast 1521 tests, serial 490 tests, 0 failures.
  checks_run:
    - grep acceptance scans
    - swift build
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-04T17:37:02.992Z
  session: 01MUU3JWT1IJPPZ61X
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - distribution
  - cleanup
created: 2026-10-03T19:24:15.375Z
updated: 2026-10-04T17:37:02.996Z
depends_on:
  - KRMA-786
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-04T17:30:25.076Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Delete the now-unreferenced GitHub updater implementation, its DMG installer, and its tests.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstream 5). After the previous ticket nothing references these files. They are compiled only under `KROMORA_DIRECT_DISTRIBUTION` (check the first line of each). Files: `Sources/KromoraKit/ViewModels/UpdateCoordinator.swift`, `Sources/KromoraKit/Presentation/UpdateInstaller.swift` (the only `Process()` user in the app, runs `hdiutil`), `Sources/KromoraKit/Views/UpdateSheet.swift`, `Sources/KromoraKit/Models/ReleaseFeed.swift`, `Sources/KromoraKit/Models/AppVersion.swift`, `Tests/KromoraKitTests/UpdateTests.swift`. Before deleting `AppVersion.swift`, confirm with grep that nothing outside the updater uses `AppVersion` (the About view reads the bundle directly); if something does, keep only what is used and explain in the commit message.

## Scope

- Delete the files above (`git rm`).
- Remove any leftover references: string literals pointing to the GitHub releases API, doc comments referencing the updater, and fixtures used only by `UpdateTests`.
- Do not touch `Package.swift` or scripts (separate tickets).

## Acceptance criteria

- [ ] The listed files no longer exist, and `grep -rniE "UpdateCoordinator|UpdateInstaller|UpdateSheet|ReleaseFeed|api\.github\.com|hdiutil" Sources Tests` returns nothing.
- [ ] `grep -rn "Process()" Sources` returns nothing.
- [ ] `swift build` succeeds and `scripts/ci-tests.sh fast` and `scripts/ci-tests.sh serial` pass.

## Verification

- Run the greps above plus `swift build`, `scripts/ci-tests.sh fast`, and `scripts/ci-tests.sh serial`.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.


### Comment — codex @ 2026-10-04T17:30:21.877Z

Deleted the six unreferenced updater implementation and test files; AppVersion had no uses outside the updater. Verification passed: source/test grep scans found no updater, GitHub API, hdiutil, or Process() references; swift build; scripts/ci-tests.sh fast (1,521 tests); scripts/ci-tests.sh serial (490 tests); git diff --check. Commit: cc0a42ec.

## Agent log

- 2026-10-04T17:37:02.992Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Listed files no longer exist; grep for UpdateCoordinator|UpdateInstaller|UpdateSheet|ReleaseFeed|api.github.com|hdiutil in Sources Tests returns nothing (pass) — Also no AppVersion or KROMORA_DIRECT_DISTRIBUTION references remain.
- [x] grep Process() in Sources returns nothing (pass)
- [x] swift build succeeds and ci-tests fast and serial pass (pass) — fast 1521 tests, serial 490 tests, 0 failures.
Checks run:
- grep acceptance scans
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
Pickup session: 01MUU3JWT1IJPPZ61X
Summary: Verified: updater files deleted, no leftover references, build and fast/serial lanes pass.
