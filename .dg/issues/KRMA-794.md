---
id: KRMA-794
title: "Create Xcode/Kromora.xcodeproj: app target linking the local KromoraKit package"
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
  - xcode
  - packaging
created: 2026-10-03T19:24:26.236Z
updated: 2026-10-03T19:25:48.257Z
depends_on:
  - KRMA-793
blockers: []
order: zzh
board: product
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
