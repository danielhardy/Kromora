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

**Result: in-place install does not work under App Sandbox. This is permanent, not a missing
credential.** `canInstallInPlace` returns `false` unconditionally and must stay that way; the
update sheet always opens the release page for the user to install manually.

Tested 2026-09-23 on macOS (Team ID `FNB49PXFFU`, bundle identifier `com.last8.kromora.photo`)
with a real Developer ID Application identity, a matching Developer ID provisioning profile, and
a notarization credential all configured and working (confirmed by a full, real
`scripts/release-dmg.sh` run: signed, notarized, stapled, and verified end to end).

Test method: a minimal signed, sandboxed, entitled macOS app (same entitlements as
`Kromora.entitlements`, same Developer ID identity, embedded provisioning profile, installed at
`/Applications`, launched normally via `open` so App Sandbox is actually enforced) called the
production `KromoraUpdateInstaller.mount(_:)` against a real release DMG bundled in its own
Resources. Result, reproduced twice:

```
mountFailed("hdiutil: attach failed - Device not configured")
```

The same DMG mounts successfully with the identical `hdiutil attach` invocation run unsandboxed
from a normal Terminal session, isolating the cause to App Sandbox itself: `hdiutil attach`
requires opening a block device node, which Seatbelt denies to sandboxed processes. This is a
platform-level restriction with no matching entitlement to request — there is no sandbox
temporary-exception entitlement that grants disk-image attach. Apple's own guidance treats
disk-image mounting as outside what App Sandbox permits; this is consistent with why sandboxed
apps distributed via Developer ID direct-download conventionally rely on the user dragging the
`.app` from the mounted DMG rather than any self-updating in-place install.

Because the failure occurs at `hdiutil attach` — the very first step of `install(_:)`, before the
staged-copy verification or the `/Applications` writability check are ever reached — those two
questions (whether App Sandbox would separately permit writing into `/Applications`) are moot:
the update path cannot get far enough to test them, and no entitlement change can fix the
`hdiutil` restriction. Shipping behavior is and should remain: the update sheet always routes to
the release page, and the user drags the new `Kromora.app` from the mounted DMG onto the
`Applications` shortcut, same as first install.

If a future macOS release changes this restriction, or if the updater is redesigned to avoid
`hdiutil attach` entirely (for example, verifying and copying the app directly out of a
downloaded `.zip` instead of a `.dmg`, which needs no block device), re-run this test before
re-enabling `canInstallInPlace`.

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
project value (`com.last8.kromora.photo`) unless `KROMORA_BUNDLE_IDENTIFIER` is explicitly set.

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
