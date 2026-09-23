# Packaging and product identity

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
signature and expected entitlements. Local and CI structural builds may use an ad-hoc signature;
distribution builds must provide the configured signing identity and provisioning profile through
the build environment. App Sandbox remains enabled, with user-selected file access, removable-media
read access, and app-scope bookmarks as declared in
[`Sources/Kromora/Kromora.entitlements`](../Sources/Kromora/Kromora.entitlements).

The zero-dependency updater contacts only
`https://api.github.com/repos/danielhardy/Kromora/releases/latest` and the HTTPS URL of the
selected release DMG. The network client entitlement is required for those outbound requests in a
sandboxed app; no server-side update service or telemetry endpoint is used. Automatic checks run at
most once every 24 hours and stay quiet for network failures. Manual checks report failures and can
open the release page.

Before an in-place install, the updater mounts the DMG read-only and verifies the embedded
`Kromora.app` against the running app's Developer ID Team ID and bundle identifier with strict
nested code-signature validation. After copying the app to a sibling staging directory, it repeats
that verification on the staged copy before moving the running app, so a failed copy is discarded
without changing the installed app. Unsigned development builds cannot replace themselves.

The updater passes `-noverify` to `hdiutil attach` to skip hdiutil's DMG-level verification. The
installer independently verifies the app inside the image with `SecStaticCode`, requiring Apple
Developer ID signing and matching the running app's Team ID and bundle identifier, with strict
nested-code validation. The DMG container itself is not treated as the trust boundary.

### Sandboxed updater validation

In-place installation is currently disabled for all builds: signature presence does not establish
that App Sandbox permits launching `hdiutil`, staging files, and replacing an app under
`/Applications`. Until the signed release-build test below passes, the update sheet opens the
release page so the user can install the update manually. No signed sandboxed result is recorded
yet: this checkout has no Developer ID signing identity (`security find-identity -v -p codesigning`
reported zero valid identities), provisioning profile, or notary credential, so a valid manual
test could not be run here.

To complete the test on a machine with the distribution credentials listed below:

1. Build a signed, sandboxed, direct-distribution release using the `release-dmg.sh` command below.
2. Copy the resulting DMG to a separate location and mount it read-only with `hdiutil attach`.
3. Launch the signed app from the mounted image, confirm the update feed finds a release, and
   trigger install. Observe whether the app can start its `hdiutil attach` child process, mount and
   validate the downloaded DMG, copy and re-verify the staged app, and replace its copy in
   `/Applications`.
4. Record the macOS version, exact build identity/version, and each stage's pass/fail result here.
   If all stages pass, enable `canInstallInPlace` only after this result is reproducible; if any
   stage fails, retain the release-page fallback and record the failing sandbox operation.

The GitHub updater is compiled only for direct-download releases. `release-dmg.sh` sets
`KROMORA_DIRECT_DISTRIBUTION=1` before invoking the app build; ordinary SwiftPM/Xcode builds omit
that flag and therefore omit the updater, its menu/settings UI, and its DMG installer entirely.
App Store archives should continue to use Xcode's App Store Connect distribution workflow.

For a distributable build, use Xcode 26 or newer with the macOS 26 SDK. The package still deploys to
macOS 14; SDK availability guards are required for newer APIs.

## Signed DMG releases

[`scripts/release-dmg.sh`](../scripts/release-dmg.sh) composes the app bundler into a reproducible
arm64 + x86_64 release. It sets the requested version in `CFBundleShortVersionString`, derives
`CFBundleVersion` from the git commit count unless overridden, signs with Developer ID Application
and hardened runtime, creates `Kromora-<version>.dmg`, and prints the exact asset path when complete.
The DMG contains `Kromora.app` and an `Applications` shortcut. The bundle identifier remains the
project value (`com.kromora.photo`) unless `KROMORA_BUNDLE_IDENTIFIER` is explicitly set.

Prerequisites:

- macOS with SwiftPM, Xcode command-line tools (`xcrun actool`, `notarytool`, `stapler`), `codesign`,
  `hdiutil`, and `lipo`.
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

For local updater/artifact dry-runs, use `KROMORA_SKIP_NOTARIZE=1`. This skips all Apple notary
round-trips, defaults to an ad-hoc signature when no identity is supplied, and still signs and
verifies both the app and DMG:

```sh
KROMORA_SKIP_NOTARIZE=1 scripts/release-dmg.sh 1.2.3
```

That output is explicitly non-ship: it has no notarization ticket or stapled ticket. The normal
`scripts/build-macos-app.sh` remains the lower-level disposable `.build/Kromora.app` workflow for
local/CI structural checks; `release-dmg.sh` adds versioning, universal builds, DMG packaging, and
distribution validation around it. `create-dmg` is not required because the supported fallback uses
the macOS built-in `hdiutil` path.
