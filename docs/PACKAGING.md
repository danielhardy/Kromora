# App packaging and distribution

This guide is the current reference for building, signing, archiving, and submitting Kromora. Test lanes are in [`TESTING.md`](TESTING.md).

## Distribution model

Kromora's macOS app is distributed through the Mac App Store. Prerelease builds go to testers through TestFlight before App Store submission. Developers can build and run the source from this repository with SwiftPM; the source build is for development, while the Xcode project produces the sandboxed production app. The package has no third-party dependencies.

Direct-download distribution was retired.

## Layout

- [`Kromora/`](../Kromora/) is the app folder, a file-system synchronized group of [`Kromora.xcodeproj`](../Kromora.xcodeproj). It holds the thin production SwiftUI entry point, `Assets.xcassets`, `Kromora.icon`, `Info.plist`, and `Kromora.entitlements`. `project.pbxproj` does not list its files, and excludes `Info.plist` and the entitlements from the target's resources. Add nothing else to it; anything placed there is bundled.
- [`Kromora.xcodeproj`](../Kromora.xcodeproj) sits at the repository root with its shared `Kromora` scheme. Always pass `-project Kromora.xcodeproj` to `xcodebuild`, because `Package.swift` is beside it.
- [`Config/`](../Config/) holds the Debug, Release, and base build settings, outside the synchronized folder so they are never bundled.
- [`scripts/fixtures/`](../scripts/fixtures/) holds the smoke test's input image.
- [`Sources/Kromora/`](../Sources/Kromora/) contains the thin SwiftPM development launcher. Application functionality lives in the `KromoraKit` package target.

The packaged Release app is built at `.build/xcode/Build/Products/Release/Kromora.app`. Archive mode writes `.build/xcode/Kromora.xcarchive` for Xcode Organizer.

## Local verification

Run the production project build and its packaging checks with:

```sh
scripts/app-store-build.sh verify
```

Use Xcode 27 or newer with the macOS 27 SDK. This builds the Release, arm64 app with a macOS 26 (Tahoe) minimum. Local verification can use an ad-hoc signature; set `DEVELOPMENT_TEAM` in the environment to use Xcode automatic development signing.

[`scripts/verify-xcode-app.sh`](../scripts/verify-xcode-app.sh) checks the built app's bundle identity and required Info.plist values, including the bundle identifier, name, executable, marketing version and build number (each must equal the `Base.xcconfig` value), Photography category, encryption flag, macOS 26 minimum, principal class, high-resolution flag, and the Photos usage string (which must equal the `Base.xcconfig` value). It opens the packaged resource bundle and checks every bundled Look listed by its manifest, then calls the signature and icon verifiers. [`scripts/verify-app-signature.sh`](../scripts/verify-app-signature.sh) validates the code signature and exact sandbox entitlement set (the allowlist lives in [`check-sandbox-entitlements.py`](../scripts/check-sandbox-entitlements.py), shared with `verify-library-package-metadata.sh`); [`scripts/verify-app-icon.sh`](../scripts/verify-app-icon.sh) validates the packaged app icon and required assets.

## Signing and capabilities

The production app uses the App Sandbox and Hardened Runtime. Both are enabled in [`Base.xcconfig`](../Config/Base.xcconfig); [`Release.xcconfig`](../Config/Release.xcconfig) prevents Xcode from injecting extra base entitlements, so the explicit set in [`Kromora.entitlements`](../Kromora/Kromora.entitlements) is the Release capability contract:

| Entitlement | Why Kromora needs it |
| --- | --- |
| `com.apple.security.app-sandbox` | Runs the Mac App Store app inside the required App Sandbox. |
| `com.apple.security.files.user-selected.read-write` | Reads imports and writes exports or Look files chosen through system file panels. |
| `com.apple.security.files.removable-media.read-only` | Discovers and reads supported images from mounted camera cards; imports are copied into the library. |
| `com.apple.security.files.bookmarks.app-scope` | Retains access to user-selected external files and folders across launches. |
| `com.apple.security.assets.pictures.read-write` | Stores the default library package, exports, and app-owned Looks under Pictures. |
| `com.apple.security.personal-information.photos-library` | Lets PhotoKit authorize, fetch, and transfer originals for Photos import and save exports to Photos; without it the sandbox denies PhotoKit. |

This is the complete set. Kromora makes no app-owned network requests, so it does not request the network-client entitlement. Photos import and saving to Photos use PhotoKit with the existing `NSPhotoLibraryUsageDescription`, generated from `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` in [`Base.xcconfig`](../Config/Base.xcconfig). Standard open/save panels and sandbox grants do not need file or folder usage-description strings. The current privacy and permission analysis is in [`APP_STORE_SANDBOX_AUDIT.md`](APP_STORE_SANDBOX_AUDIT.md).

Required-reason API declarations in a privacy manifest are not a current signing or packaging prerequisite for Kromora's native macOS-only target. See the sandbox audit for the current platform scope and rationale; revisit the manifest requirements if target platforms or SDK requirements change. App Store Connect privacy answers are a separate submission task; see [`APP_STORE_SUBMISSION.md`](APP_STORE_SUBMISSION.md).

## Versioning

Identity and versions live only in [`Base.xcconfig`](../Config/Base.xcconfig) build settings, which generate the built `Info.plist`. The checked-in [`Info.plist`](../Kromora/Info.plist) carries only keys with no build-setting form: `UTExportedTypeDeclarations`, `KromoraGitCommit` (substituted from `KROMORA_GIT_COMMIT`), and `NSHighResolutionCapable` (Xcode 27 has no `INFOPLIST_KEY_` setting that emits it). Do not re-add identity or version keys to the plist.

[`Base.xcconfig`](../Config/Base.xcconfig) defines `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`; the current values are `0.1` and `1`. Bump `MARKETING_VERSION` for a new user-facing release. Increment `CURRENT_PROJECT_VERSION` for every uploaded build, including successive TestFlight builds, and do not reuse an uploaded build number.

## Release procedure

Before archiving, the release owner needs Apple Developer Program membership and account access, an App Store Connect app record, the App ID `com.last8.kromora.photo`, and an App Store distribution certificate and provisioning profile. Xcode account access and signing assets must be configured for the team. Do not put credentials, private keys, or team identifiers in this repository.

1. Set the release version and build number in `Base.xcconfig`, then run the required checks in [`TESTING.md`](TESTING.md).
2. In Xcode, open [`Kromora.xcodeproj`](../Kromora.xcodeproj), select the shared `Kromora` scheme, choose **Product > Archive**, and let the archive finish. For a command-line archive, set `DEVELOPMENT_TEAM` in the shell and run `scripts/app-store-build.sh archive`; it creates `.build/xcode/Kromora.xcarchive` for Organizer.
3. In Organizer, validate the archive and choose **Distribute App > App Store Connect > Upload**. Xcode performs the upload interactively; there is no automated upload step in this repository.
4. Wait for App Store Connect to process the build, make it available to internal TestFlight testers, and test that build before selecting it for App Review. Complete the listing, privacy, and review information in App Store Connect using [`APP_STORE_SUBMISSION.md`](APP_STORE_SUBMISSION.md) as the preparation checklist.

## CI

The `xcode-app` job in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) runs `scripts/app-store-build.sh` on pushes to `main` and manual workflow dispatches. It builds and verifies the Xcode Release app on the `xcode-27` runner and checks that the build did not modify tracked source files. CI verifies the packaged app structure; it does not create a release archive or upload a build.
