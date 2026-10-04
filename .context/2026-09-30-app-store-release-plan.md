# Mac App Store release plan

**Date:** 2026-09-30  
**Status:** Proposal — no files changed yet

## Goal

Ship Kromora through the Mac App Store while preserving the existing SwiftPM development workflow.

Day-to-day development should continue to work exactly as it does today:

```bash
swift build
swift run
swift test
scripts/ci-tests.sh
```

The Mac App Store build should be a thin packaging layer around the existing codebase, not a second build architecture.

## Distribution model

Kromora will have one supported binary distribution channel:

- **Mac App Store** — normal production distribution
- **TestFlight** — prerelease/beta distribution
- **Source build** — developers can clone the repository and build with SwiftPM

Kromora will no longer maintain a separate DMG/direct-download distribution path.

That means removing or retiring:

- DMG generation
- direct-download releases
- Developer ID distribution workflow
- notarization/stapling workflow for direct distribution
- GitHub binary releases
- self-update/GitHub updater functionality
- direct-distribution-specific build flags and conditionals

If direct distribution becomes valuable in the future, it can be reintroduced deliberately. It should not be maintained speculatively.

## Architecture

Kromora should have one application implementation with two extremely small launch targets.

```text
                         KromoraKit
                    ┌─────────────────┐
                    │ Application code│
                    │ UI              │
                    │ Editing engine  │
                    │ Metal / Vision  │
                    │ Models          │
                    │ Resources       │
                    └────────┬────────┘
                             │
             ┌───────────────┴───────────────┐
             │                               │
       SwiftPM executable               Xcode app target
        development only              production packaging
             │                               │
        swift run                        App Store
        swift test                       TestFlight
        AI workflows                     signing
                                         sandbox
                                         entitlements
```

The core architectural rule is:

> **If it is application functionality, it belongs in `KromoraKit`.**

The Xcode project exists only to package `KromoraKit` as a production macOS application.

## Target repository layout

```text
Package.swift

Sources/
  Kromora/
    KromoraApp.swift              ← SwiftPM development launcher

  KromoraKit/
    ...application implementation...
    ...resources...

App/
  KromoraApp.swift                ← Xcode/App Store launcher
  Assets.xcassets
  Kromora.entitlements

Xcode/
  Kromora.xcodeproj

  Config/
    Base.xcconfig
    Debug.xcconfig
    Release.xcconfig

scripts/
  ci-tests.sh
  app-store-build.sh
```

The two `KromoraApp.swift` files should remain intentionally tiny.

Example:

```swift
import SwiftUI
import KromoraKit

@main
struct KromoraApp: App {
    var body: some Scene {
        KromoraScene()
    }
}
```

Duplicating a tiny launcher is preferable to sharing an `@main` source file across SwiftPM and Xcode and introducing target-membership/build-system complexity.

## Build-system ownership

### SwiftPM owns

SwiftPM remains the source of truth for:

- application implementation
- dependencies
- compiler/language configuration
- tests
- resources used by `KromoraKit`
- developer builds
- command-line builds
- AI-agent workflows

Normal development remains:

```bash
swift build
swift test
swift run Kromora
```

Application source files should not need to be manually added to the Xcode project.

### Xcode owns

Xcode owns only production application packaging:

- bundle identifier
- application icon
- asset catalog
- generated `Info.plist`
- usage-description strings
- App Sandbox
- entitlements
- signing
- provisioning
- archive creation
- App Store submission

The Xcode target should link the local Swift package and depend only on the `KromoraKit` library product.

It should **not** link the SwiftPM `Kromora` executable product.

## Workstream 0 — App Store compatibility audit

Before creating the shipping target, audit Kromora for assumptions that may behave differently inside an App Sandbox.

Review:

- filesystem access
- open/save panels
- drag-and-drop file URLs
- persistent file access
- security-scoped bookmarks
- Photos library access
- RAW image access
- export destinations
- LUT/resource locations
- cache/temp directories
- network access
- subprocess or shell execution
- dynamically loaded code
- embedded frameworks/binaries
- external helper processes, if any

The goal is to identify anything that currently works because `swift run` executes as an unrestricted developer process but may fail in the production sandbox.

`swift run` should explicitly be treated as a **development runtime**, not as proof that the App Store build behaves identically.

## Workstream 1 — Create the Xcode app target

Create:

```text
Xcode/Kromora.xcodeproj
```

with one macOS application target:

```text
Kromora
```

The target should:

1. Reference the local Swift package at the repository root.
2. Link only the `KromoraKit` library product.
3. Compile the tiny `App/KromoraApp.swift` launcher.
4. Compile `App/Assets.xcassets`.
5. Use `App/Kromora.entitlements`.
6. Generate its `Info.plist`.
7. Use automatic signing unless a concrete reason emerges not to.

The target should not duplicate application implementation files.

## Workstream 2 — App configuration

Use `.xcconfig` files for packaging-specific configuration.

Example:

```text
Xcode/Config/
  Base.xcconfig
  Debug.xcconfig
  Release.xcconfig
```

`Base.xcconfig` should own settings such as:

```text
PRODUCT_NAME = Kromora
PRODUCT_BUNDLE_IDENTIFIER = ...
MACOSX_DEPLOYMENT_TARGET = 26.0

GENERATE_INFOPLIST_FILE = YES

MARKETING_VERSION = 1.0
CURRENT_PROJECT_VERSION = 1
```

App Store metadata that can be represented through build settings should also live here where practical.

Examples include:

```text
INFOPLIST_KEY_CFBundleDisplayName = Kromora
INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.photography
INFOPLIST_KEY_NSPhotoLibraryUsageDescription = ...
```

Do not duplicate Swift compiler configuration in Xcode unless absolutely necessary.

Swift language mode and other shared compiler behavior should remain controlled by `Package.swift`.

The goal is:

```text
SwiftPM configuration = how Kromora compiles
Xcode configuration   = how Kromora is packaged
```

## Workstream 3 — Privacy and usage strings

Audit every protected API Kromora accesses and ensure the production app includes the required usage descriptions.

At minimum, the currently identified issue is:

- Photos usage description is missing.

Confirm whether Kromora needs usage strings for any other protected resources.

Do not add permissions that Kromora does not actually use.

### Privacy manifest platform scope

Apple's current [privacy manifest guidance](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
covers data-collection practices on all platforms, while required-reason API declarations apply
only to iOS, iPadOS, tvOS, visionOS, and watchOS. Kromora currently targets native
macOS 26 only (`Package.swift` declares `.macOS(.v26)` and the Xcode `Kromora` target supports
`macosx`). Its file-timestamp, `UserDefaults`, and system-uptime calls therefore do not require
required-reason entries or a `PrivacyInfo.xcprivacy` file for this target. Do not treat the
file-timestamp reason-code mismatch as a Mac App Store blocker, and do not move package or cache
data solely to fit a reason code. Revisit this if Kromora adds a covered platform, adopts an SDK
subject to a manifest requirement, or needs a manifest for another data-collection disclosure.

App Store Connect's app privacy answers are maintained separately from any privacy manifest and
must reflect Kromora's data practices, including those of any third-party partners. See [Apple's
App Store Connect privacy guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
and KRMA-807.

## Workstream 4 — Entitlements

Create:

```text
App/Kromora.entitlements
```

This file represents the production application's capability contract.

Enable only the capabilities Kromora requires.

Expected areas include:

- App Sandbox
- user-selected file access
- network access, if required
- Photos-related access, if entitlement-controlled
- any persistent file-access mechanism required by the application

The SwiftPM developer executable does not need to perfectly emulate the App Store entitlement environment.

Instead, production behavior should be validated using the actual Xcode app build.

## Workstream 5 — Remove direct distribution

Remove the direct distribution path rather than carrying two shipping architectures.

Delete or retire:

- GitHub updater implementation
- `KROMORA_DIRECT_DISTRIBUTION`
- updater UI
- update-check code
- download/install/relaunch code
- DMG generation scripts
- direct-release automation
- Developer ID-specific packaging logic
- notarization-specific scripts that exist only for DMG distribution

GitHub Releases may still be used for source releases/tags if useful, but they should not be treated as an end-user binary distribution mechanism.

This leaves:

```text
Users       → Mac App Store
Beta users  → TestFlight
Developers  → source + SwiftPM
```

## Workstream 6 — CI validation

Maintain two levels of validation.

### Level 1 — normal development

Run for normal development and pull requests:

```bash
swift build
swift test
scripts/ci-tests.sh
```

This remains the fast path for developers and AI agents.

### Level 2 — production app validation

Add an Xcode build check:

```bash
xcodebuild \
  -project Xcode/Kromora.xcodeproj \
  -scheme Kromora \
  -configuration Release \
  build
```

This should run on `main` and/or as part of release validation.

Its purpose is to catch problems such as:

- broken Xcode project references
- missing assets
- invalid entitlements
- generated `Info.plist` problems
- App Store target compilation failures
- differences between SwiftPM and Xcode builds

An archive validation step can be added later if useful.

## Workstream 7 — Release script

Provide one simple release-oriented command:

```bash
scripts/app-store-build.sh
```

Initially, it only needs to verify/build the production target.

For early releases, prefer creating the archive in Xcode and using:

```text
Product
→ Archive
→ Distribute App
→ App Store Connect
```

Do not automate upload/submission until releases are frequent enough for that automation to meaningfully reduce work.

The release process should favor simplicity and transparency over premature automation.

## Workstream 8 — Documentation for AI agents

Document the architecture explicitly so automated coding agents do not accidentally turn the Xcode project into a second source tree.

Add guidance similar to:

```text
## Build architecture

Kromora uses Swift Package Manager as its primary development build system.

Normal development:

    swift build
    swift test
    swift run Kromora

All application functionality belongs in KromoraKit.

Do not add implementation source files directly to the Xcode application target.

The Xcode project exists only to package KromoraKit as the signed,
sandboxed Mac App Store application.

The SwiftPM Kromora executable is a development launcher.

The Xcode Kromora target is the production launcher.

Before release, verify the production application with:

    xcodebuild \
      -project Xcode/Kromora.xcodeproj \
      -scheme Kromora \
      -configuration Release \
      build
```

This rule should be treated as an architectural invariant.

## Success criteria

The migration is complete when:

- `swift build` works unchanged.
- `swift test` works unchanged.
- `swift run Kromora` works unchanged.
- `scripts/ci-tests.sh` works unchanged.
- Xcode can build the production Kromora `.app`.
- Xcode can archive Kromora successfully.
- the production app launches correctly with App Sandbox enabled.
- importing/opening photos works.
- exporting files works.
- Photos integration works.
- persistent user-selected file access works where required.
- the application passes App Store validation.
- a build can be uploaded to App Store Connect/TestFlight.
- no production application logic exists only in the Xcode target.
- direct-distribution/updater infrastructure has been removed.

## Final architecture principle

Kromora should have:

**One codebase. One binary distribution channel. Two tiny launchers.**

SwiftPM is optimized for development.

Xcode is optimized for shipping.

`KromoraKit` is the application.

Everything else should remain as thin as possible.
