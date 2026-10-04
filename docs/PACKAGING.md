# Packaging and product identity

Packaging is part of the MVP release bar in [`PRODUCT_SCOPE.md`](PRODUCT_SCOPE.md). This guide owns
the current bundle, signing, and entitlement procedure.

The distributable app is built by [`scripts/build-macos-app.sh`](../scripts/build-macos-app.sh).
The script stages the SwiftPM release product, asset catalog, entitlements, and icon into the
disposable `.build/Kromora.app` bundle. It does not modify tracked source assets.

## Icon

The product icon is authored in `Kromora.icon`, composed into the app bundle by the build script,
and checked by [`scripts/verify-app-icon.sh`](../scripts/verify-app-icon.sh). Keep the source icon's
safe area, corner treatment, and monochrome/colored variants consistent with the Kromora identity;
verify the packaged `CFBundleIconName`, resource presence, and rendered outputs after changes.

## Signing and entitlements

[`scripts/verify-app-signature.sh`](../scripts/verify-app-signature.sh) checks the packaged
signature and exact App Sandbox entitlement set. Local and CI structural builds may use an ad-hoc
signature; distribution builds must provide the configured signing identity and provisioning
profile through the build environment. The five declared capabilities are app sandbox,
user-selected file read/write, read-only removable-media access, app-scope bookmarks, and Pictures
read/write, as declared in
[`Sources/Kromora/Kromora.entitlements`](../Sources/Kromora/Kromora.entitlements).

The Pictures entitlement covers the default library package, exports, and app-owned Looks under
Pictures. Removable-media read access supports mounted camera-card discovery and image imports;
imported files are copied into the library package. The app makes no direct network requests and
does not request the network client entitlement. Photos import and delivery use the system Photos
picker and PhotoKit authorization paths.

For a distributable build, use Xcode 27 or newer with the macOS 27 SDK. The package and app deploy
to macOS 26 (Tahoe); keep API usage compatible with that deployment floor.

## Signed DMG releases

[`scripts/release-dmg.sh`](../scripts/release-dmg.sh) composes the app bundler into an Apple Silicon
arm64-only release. It sets the requested version in `CFBundleShortVersionString`, derives
`CFBundleVersion` from the git commit count unless overridden, signs with Developer ID Application
and hardened runtime, creates `Kromora-<version>.dmg`, and prints the exact asset path when complete.
The DMG contains `Kromora.app` and an `Applications` shortcut. The bundle identifier remains the
project value (`com.last8.kromora.photo`) unless `KROMORA_BUNDLE_IDENTIFIER` is explicitly set.

Prerequisites:

- Apple Silicon Mac with SwiftPM, Xcode command-line tools (`xcrun actool`, `notarytool`, `stapler`),
  `codesign`, and `hdiutil`.
- A Developer ID Application certificate installed in the login keychain. Set
  `KROMORA_CODESIGN_IDENTITY` to its exact identity (the script rejects non-Developer-ID identities
  for distribution), plus the matching App Sandbox provisioning profile in
  `KROMORA_PROVISIONING_PROFILE`.
- A stored notarytool credential profile, created for example with
  `xcrun notarytool store-credentials`. Set its name in `KROMORA_NOTARY_PROFILE`.

Distribution usage:

```sh
KROMORA_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
KROMORA_PROVISIONING_PROFILE="/absolute/path/Kromora.provisionprofile" \
KROMORA_NOTARY_PROFILE="kromora-notary" \
  scripts/release-dmg.sh 1.2.3
```

The script notarizes and staples the app before creating the DMG, then signs, notarizes, and staples
the DMG itself. It verifies the final mounted DMG, including the executable, plist, icon, resource
bundle, and expected entitlements. Any failed signing, notarization, stapling, or structure check
removes the incomplete release output.

For local artifact dry-runs, use `KROMORA_SKIP_NOTARIZE=1`. This skips all Apple notary
round-trips, defaults to an ad-hoc signature when no identity is supplied, and still signs and
verifies both the app and DMG:

```sh
KROMORA_SKIP_NOTARIZE=1 scripts/release-dmg.sh 1.2.3
```

That output is explicitly non-ship: it has no notarization ticket or stapled ticket. The normal
`scripts/build-macos-app.sh` remains the lower-level disposable `.build/Kromora.app` workflow for
local/CI structural checks; `release-dmg.sh` adds versioning, DMG packaging, and distribution
validation around it. Both package arm64 only. `create-dmg` is not required because the supported
fallback uses the macOS built-in `hdiutil` path.
