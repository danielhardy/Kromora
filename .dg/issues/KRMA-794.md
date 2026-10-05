---
id: KRMA-794
title: "Create Xcode/Kromora.xcodeproj: app target linking the local KromoraKit package"
type: task
status: done
priority: high
verification_agent: claude
human_review_required: false
verification_model: sonnet
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: xcodebuild -list lists target and scheme Kromora
      result: pass
      notes: Target Kromora; schemes include "Kromora (Kromora project)". Plain -scheme Kromora is ambiguous with the SwiftPM executable scheme.
    - criterion: Debug build succeeds and produces Kromora.app
      result: pass
      notes: BUILD SUCCEEDED using the qualified project scheme.
    - criterion: Only App/KromoraApp.swift compiled; links KromoraKit only
      result: pass
      notes: pbxproj has one Sources entry and one KromoraKit product dependency; launcher identical to Sources/Kromora/KromoraApp.swift.
    - criterion: swift build / PackageSettingsTests / ci-tests fast pass; no generated artifacts
      result: pass
      notes: swift build and PackageSettingsTests (5) re-run and pass; git status shows no Package.resolved or DerivedData. Did not re-run the full fast lane (implementer reported 1,522 passing; SwiftPM sources unchanged).
    - criterion: .gitignore covers xcuserdata and build output
      result: pass
  checks_run:
    - xcodebuild -list
    - xcodebuild Debug build
    - swift build
    - swift test --filter PackageSettingsTests
    - pbxproj inspection
    - diff launchers
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-04T19:01:08.267Z
  session: 01MUU6RIOR6ZYO674Q
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - xcode
  - packaging
created: 2026-10-03T19:24:26.236Z
updated: 2026-10-04T19:01:08.271Z
depends_on:
  - KRMA-793
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-04T19:00:09.380Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Create the production Xcode project: one macOS app target named `Kromora` that links only the `KromoraKit` library product of the root Swift package, and compiles a tiny `App/KromoraApp.swift` launcher.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstream 1). SwiftPM stays the source of truth for application code, so the Xcode project must contain no implementation sources. The launcher is intentionally a duplicate of `Sources/Kromora/KromoraApp.swift` (two tiny launchers beat a shared `@main` file with target-membership tricks). `KromoraKit` is declared in `Package.swift` as `.library(name: "KromoraKit", targets: ["KromoraKit"])`; the `Kromora` executable product must NOT be linked. Requires Xcode 27 (the CI image `xcode-27` and the local toolchain); target macOS 26.0, arm64 only. A `.pbxproj` is easiest to produce by scripting it carefully or by running `xed`/Xcode if a GUI is available; without a GUI, write the project by hand, then validate it with `xcodebuild -list`. Do not use third-party generators (zero-dependency project rule applies to tooling that lands in the repo).

## Scope

- Create `Xcode/Kromora.xcodeproj` with a single macOS application target `Kromora`, a local package reference to the repository root (`..`), and a package product dependency on `KromoraKit` only.
- Create `App/KromoraApp.swift` with the same tiny launcher as `Sources/Kromora/KromoraApp.swift` (adaptor + `KromoraScene`), and compile only that file in the target.
- Create a shared scheme `Kromora` (stored under `xcshareddata/xcschemes`) so `xcodebuild -scheme Kromora` works headless.
- Build settings in this ticket: product name `Kromora`, deployment target 26.0, `ARCHS = arm64`, `SWIFT_VERSION = 6.0` (the one Swift setting the launcher needs; do not copy any other compiler flag from `Package.swift`), `CODE_SIGNING_ALLOWED = NO` for the headless build. Entitlements, Info.plist, icon, and signing are separate tickets.

## Acceptance criteria

- [ ] `xcodebuild -list -project Xcode/Kromora.xcodeproj` lists target and scheme `Kromora`.
- [ ] `xcodebuild -project Xcode/Kromora.xcodeproj -scheme Kromora -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build` succeeds and produces `Kromora.app` (note the DerivedData path in the handoff comment).
- [ ] The only Swift file compiled by the target is `App/KromoraApp.swift`; the project links `KromoraKit` and does not reference the SwiftPM `Kromora` executable.
- [ ] `swift build`, `swift test --filter PackageSettingsTests`, and `scripts/ci-tests.sh fast` still pass (SwiftPM is unaffected; `git status` shows no generated `Package.resolved` or DerivedData in the repository).
- [ ] `.gitignore` covers `xcuserdata` and Xcode build output.

## Verification

- Run `xcodebuild -list` and the Debug build command above; inspect the `.pbxproj` for source membership.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.


### Comment — codex @ 2026-10-04T19:00:06.588Z

Implemented and committed as 3d347ff8. Added the shared Xcode app project and duplicate launcher; the app target links only KromoraKit and compiles only App/KromoraApp.swift. Verification passed: xcodebuild -list, the app build, swift build, swift test --filter PackageSettingsTests (5 tests), and scripts/ci-tests.sh fast (1,522 tests). The app build used scheme "Kromora (Kromora project)" and produced /Users/dhardy/Library/Developer/Xcode/DerivedData/Kromora-esnxukvllplfjhaesjtzeejjokol/Build/Products/Debug/Kromora.app. In this checkout, plain -scheme Kromora resolves to the package executable scheme because it shares the name; the project app scheme is the qualified one. No Package.resolved or DerivedData was generated in the repository. Existing .gitignore already covers xcuserdata and Xcode build output.

## Agent log

- 2026-10-04T19:01:08.267Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] xcodebuild -list lists target and scheme Kromora (pass) — Target Kromora; schemes include "Kromora (Kromora project)". Plain -scheme Kromora is ambiguous with the SwiftPM executable scheme.
- [x] Debug build succeeds and produces Kromora.app (pass) — BUILD SUCCEEDED using the qualified project scheme.
- [x] Only App/KromoraApp.swift compiled; links KromoraKit only (pass) — pbxproj has one Sources entry and one KromoraKit product dependency; launcher identical to Sources/Kromora/KromoraApp.swift.
- [x] swift build / PackageSettingsTests / ci-tests fast pass; no generated artifacts (pass) — swift build and PackageSettingsTests (5) re-run and pass; git status shows no Package.resolved or DerivedData. Did not re-run the full fast lane (implementer reported 1,522 passing; SwiftPM sources unchanged).
- [x] .gitignore covers xcuserdata and build output (pass)
Checks run:
- xcodebuild -list
- xcodebuild Debug build
- swift build
- swift test --filter PackageSettingsTests
- pbxproj inspection
- diff launchers
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUU6RIOR6ZYO674Q
Summary: Verified: Xcode project links only KromoraKit, compiles only App/KromoraApp.swift, builds.
