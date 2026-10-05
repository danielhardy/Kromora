# Packaging and product identity

Packaging is part of the MVP release bar in [`PRODUCT_SCOPE.md`](PRODUCT_SCOPE.md). This guide owns
the current bundle, signing, and entitlement procedure.

The distributable app is built by the `Kromora` target in
[`Xcode/Kromora.xcodeproj`](../Xcode/Kromora.xcodeproj), with
[`scripts/app-store-build.sh`](../scripts/app-store-build.sh) as the supported build and archive
entry point. The Release app is produced at
`.build/xcode/Build/Products/Release/Kromora.app`; Xcode compiles the icon, embeds the package
resources, and signs the app from the project configuration.

## Icon

The product icon is authored in `Kromora.icon`, composed into the app bundle by Xcode, and checked
by [`scripts/verify-app-icon.sh`](../scripts/verify-app-icon.sh). Keep the source icon's
safe area, corner treatment, and monochrome/colored variants consistent with the Kromora identity;
verify the packaged `CFBundleIconName`, resource presence, and rendered outputs after changes.

## Signing and entitlements

[`scripts/verify-app-signature.sh`](../scripts/verify-app-signature.sh) checks the Xcode-built
signature and exact App Sandbox entitlement set. Local and CI structural builds may use an ad-hoc
signature; distribution builds must provide the configured signing identity and provisioning
profile through the build environment. The five declared capabilities are app sandbox,
user-selected file read/write, read-only removable-media access, app-scope bookmarks, and Pictures
read/write, as declared in
[`App/Kromora.entitlements`](../App/Kromora.entitlements).

The Pictures entitlement covers the default library package, exports, and app-owned Looks under
Pictures. Removable-media read access supports mounted camera-card discovery and image imports;
imported files are copied into the library package. The app makes no direct network requests and
does not request the network client entitlement. Photos import and delivery use the system Photos
picker and PhotoKit authorization paths.

For a distributable build, use Xcode 27 or newer with the macOS 27 SDK. The package and app deploy
to macOS 26 (Tahoe); keep API usage compatible with that deployment floor.

Kromora is distributed only through the Mac App Store and TestFlight. Direct-download distribution
was retired; this guide describes the current Xcode app build.
