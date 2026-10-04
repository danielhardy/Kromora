---
id: KRMA-797
title: Wire the app icon and asset catalog into the Xcode target
type: task
status: ready
priority: medium
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
  - branding
created: 2026-10-03T19:24:30.809Z
updated: 2026-10-03T19:25:49.950Z
depends_on:
  - KRMA-796
blockers: []
order: zzx
board: product
---

## Objective

Make the Xcode-built app show the Kromora Icon Composer icon, matching what `scripts/build-macos-app.sh` produces today.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstream 1). The product icon is authored in `Kromora.icon` at the repository root (Icon Composer, `icon.json` plus layers); `scripts/build-macos-app.sh` compiles it with `xcrun actool … --app-icon Kromora` and forces `CFBundleIconName = Kromora` and `CFBundleIconFile = Kromora.icns`. `scripts/verify-app-icon.sh` checks the manifest, `CFBundleIconName`, `CFBundleIconFile`, `Contents/Resources/Assets.car`, and the executable. `App/Assets.xcassets` has `AccentColor` and an `AppIcon.appiconset`. Xcode 26+ can compile an Icon Composer `.icon` file directly when it is added to the target and `ASSETCATALOG_COMPILER_APPICON_NAME = Kromora`.

## Scope

- Add `Kromora.icon` (referenced from the repository root, not copied) and `App/Assets.xcassets` to the target's resources; set `ASSETCATALOG_COMPILER_APPICON_NAME = Kromora` in `Base.xcconfig`. If the existing `AppIcon.appiconset` conflicts or duplicates the icon, remove it and say why.
- Make sure `Info.plist` ends up with `CFBundleIconName = Kromora`; set `CFBundleIconFile = Kromora.icns` only if `verify-app-icon.sh` needs it and the build produces that file.
- Adjust `scripts/verify-app-icon.sh` only as needed so it validates the Xcode-built app too (it already takes an app path argument), keeping it valid for the SwiftPM-built bundle until that script is retired.

## Acceptance criteria

- [ ] A Release build with `CODE_SIGNING_ALLOWED=NO` contains `Contents/Resources/Assets.car` with an icon named `Kromora`, and `scripts/verify-app-icon.sh <path to Xcode-built Kromora.app>` passes.
- [ ] `scripts/verify-app-icon.sh` with no argument (SwiftPM bundle) still passes.
- [ ] `xcodebuild` emits no actool warnings about missing icon sizes or unassigned children.

## Verification

- Build, then run `scripts/verify-app-icon.sh` on both bundles; inspect the xcodebuild log for actool warnings.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
