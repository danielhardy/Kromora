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

For a distributable build, use Xcode 26 or newer with the macOS 26 SDK, set the bundle identifier and
team in Signing & Capabilities, and archive through Product → Archive → Distribute App. The package
still deploys to macOS 14; SDK availability guards are required for newer APIs.
