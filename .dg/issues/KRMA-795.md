---
id: KRMA-795
title: Add Base/Debug/Release xcconfig files and attach them to the Xcode project
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
created: 2026-10-03T19:24:27.772Z
updated: 2026-10-03T19:25:48.823Z
depends_on:
  - KRMA-794
blockers: []
order: zzq
board: product
---

## Objective

Move packaging-specific build settings out of the `.pbxproj` and into `Xcode/Config/*.xcconfig` so they are reviewable text.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstream 2): "SwiftPM configuration = how Kromora compiles; Xcode configuration = how Kromora is packaged". Identity values to keep: bundle identifier `com.last8.kromora.photo` (from `App/Info.plist`), display name `Kromora`, minimum system version 26.0, version `0.1` build `1` (from `CFBundleShortVersionString`/`CFBundleVersion` today). Do not duplicate Swift compiler configuration beyond the single `SWIFT_VERSION = 6.0` the launcher needs.

## Scope

- Create `Xcode/Config/Base.xcconfig`, `Debug.xcconfig`, `Release.xcconfig` (the latter two `#include "Base.xcconfig"`).
- `Base.xcconfig` owns: `PRODUCT_NAME`, `PRODUCT_BUNDLE_IDENTIFIER`, `MACOSX_DEPLOYMENT_TARGET = 26.0`, `ARCHS = arm64`, `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, `SWIFT_VERSION = 6.0`, `GENERATE_INFOPLIST_FILE = YES`, and comments explaining each group.
- `Debug.xcconfig`/`Release.xcconfig` own only per-configuration differences (optimization, `DEBUG_INFORMATION_FORMAT`, `ENABLE_TESTABILITY`).
- Attach the xcconfig files as the project's base configurations and delete the corresponding settings from the `.pbxproj` (project and target level) so the xcconfig is the single source. Keep the `CODE_SIGNING_ALLOWED = NO` override out of the files (it is passed on the command line for headless builds).

## Acceptance criteria

- [ ] `xcodebuild -project Xcode/Kromora.xcodeproj -scheme Kromora -configuration Release -showBuildSettings` reports `PRODUCT_BUNDLE_IDENTIFIER = com.last8.kromora.photo`, `MACOSX_DEPLOYMENT_TARGET = 26.0`, `ARCHS = arm64`, `MARKETING_VERSION`, and `CURRENT_PROJECT_VERSION` values that come from `Base.xcconfig`.
- [ ] The `.pbxproj` no longer sets those keys directly (grep to confirm).
- [ ] The Debug and Release `xcodebuild … CODE_SIGNING_ALLOWED=NO build` commands both succeed.
- [ ] `scripts/ci-tests.sh fast` still passes.

## Verification

- Run `-showBuildSettings` for both configurations and both builds; grep the `.pbxproj`.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
