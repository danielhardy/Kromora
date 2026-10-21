# App Store submission worksheet

Prepared from the current Kromora repository for a human submitter. Draft copy and answers marked
**confirm** should be checked against the exact signed release build. Values marked **Human to
provide** require an owner or account holder. App Store Connect privacy answers are based on app and
partner data practices; they are not inferred from, or conditional on, a privacy manifest ([Apple's
privacy guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/),
[privacy-manifest guidance](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)).

## App information

| Field | Prepared value |
| --- | --- |
| Name | **Kromora** ([generated display name](../Xcode/Config/Base.xcconfig#L21-L25); [bundle name](../App/Info.plist#L5-L13)). |
| Subtitle options | **A focused Mac photo workflow** (28 characters); **RAW editing, made local** (23 characters). Both are within Apple's 30-character limit ([App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)). The wording describes the local photo workflow in the [README](../README.md#L21-L25). |
| Primary category | **Photography** — recommended and already represented by the Xcode category setting `public.app-category.photography` ([Base.xcconfig](../Xcode/Config/Base.xcconfig#L21-L25)). **Confirm** the matching App Store Connect category before submission; Apple says the App Store Connect primary category should match Xcode ([App information reference](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)). |
| Secondary category | Optional; leave unset unless the submitter chooses a relevant second category (**confirm**). Apple permits primary and secondary categories ([Choosing a category](https://developer.apple.com/app-store/categories/)). |
| Bundle ID | `com.last8.kromora.photo` ([Info.plist](../App/Info.plist#L5-L13)). |
| Copyright | `Copyright © 2026 Tim; Copyright © 2026 Daniel Hardy` ([Xcode-generated copyright](../Xcode/Config/Base.xcconfig#L21-L26), consistent with the [license notices](../LICENSE#L1-L5)). **Confirm** the names and year for the release. |
| Support URL | **Human to provide** — public support page URL. |
| Privacy Policy URL | **Human to provide** — public policy URL. Apple requires a privacy-policy URL for App Store apps ([App Privacy reference](https://developer.apple.com/help/app-store-connect/reference/app-privacy/)). |

## App Privacy

**Proposed App Store Connect answer: Data Not Collected — confirm against the submitted build and all integrated code:**

> No, we do not collect data from this app.

The repository evidence supports this answer for the current macOS app:

- The sandbox audit found no production app-source calls to `URLSession` or other network APIs. Its
  only listed external links open in the user's browser ([sandbox audit, network inventory](APP_STORE_SANDBOX_AUDIT.md#L329-L334)).
- The audit found no embedded third-party framework or helper executable; `Package.swift` lists
  Apple frameworks, and the product README says there are no third-party runtime dependencies
  ([sandbox audit](APP_STORE_SANDBOX_AUDIT.md#L336-L341), [Package.swift](../Package.swift#L124-L147),
  [README](../README.md#L1-L14)).
- Kromora is a local, package-backed photo workflow: accepted imports are copied into the library
  package ([README](../README.md), [storage policy](STORAGE_POLICY.md)).
  Photos imports are user-selected through PhotosPicker, and Kromora then uses PhotoKit read/write
  authorization to retrieve the selected originals (including iCloud downloads), show Photos
  thumbnails, and optionally deliver exports and place albums ([sandbox audit, protected resources](APP_STORE_SANDBOX_AUDIT.md#L361-L363),
  [Info.plist usage description](../App/Info.plist#L25-L26)).
- Apple's answers cover collection by the app and its third-party partners across platforms. Apple
  says to select “No, we do not collect data from this app” when neither the app nor its partners
  collect data ([App Store Connect privacy guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)).

The privacy answer is separate from `PrivacyInfo.xcprivacy`: Apple's manifest documentation
describes collected-data types and required-reason APIs as distinct declarations, and its required-
reason list names iOS, iPadOS, tvOS, visionOS, and watchOS ([privacy-manifest guidance](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)).
The current package and Xcode target are macOS-only ([Package.swift](../Package.swift#L119-L147),
[project target](../Xcode/Kromora.xcodeproj/project.pbxproj#L155-L174)); the sandbox audit likewise
states that App Store Connect data-collection answers reflect actual practices independently of a
manifest ([sandbox audit](APP_STORE_SANDBOX_AUDIT.md#L375-L385)).

## Export compliance

**Proposed answer: No — the app does not use non-exempt encryption. Confirm against the archived
app and any release-only linked code.** Xcode generates
`ITSAppUsesNonExemptEncryption = NO` from [`Base.xcconfig`](../Xcode/Config/Base.xcconfig#L21-L26);
the source [`App/Info.plist`](../App/Info.plist) does not contain that generated key. A source scan
for CryptoKit, SHA-256, common encryption APIs, and encryption calls finds SHA-256 digest operations
used for identity, cache keys, and package integrity ([`PhotoAsset.swift`](../Sources/KromoraKit/Models/PhotoAsset.swift#L76-L85),
[`RenderCacheKey.swift`](../Sources/KromoraKit/Models/RenderCacheKey.swift#L152-L158),
[`OriginalSettingsBundle.swift`](../Sources/KromoraKit/Models/OriginalSettingsBundle.swift#L60-L70),
[`PortablePackageTransaction.swift`](../Sources/KromoraKit/Models/PortablePackageTransaction.swift#L1098-L1108));
it does not identify an encryption implementation. Apple says `NO` is appropriate when the app does
not use encryption or uses only exempt forms ([encryption export guidance](https://developer.apple.com/documentation/Security/complying-with-encryption-export-regulations)).

## Age-rating questionnaire

These are draft selections based on Kromora's documented still-photo editing scope and current
features. **Confirm each in App Store Connect against the final build and the actual sample content.**
Apple's current questionnaire covers content descriptors, in-app controls, and capabilities
([age-rating questionnaire](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/),
[age-rating categories](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)).

| Questionnaire area | Draft answer |
| --- | --- |
| Parental controls; age assurance | No / not present (**confirm**). The documented product has photo-library and editing workflows, with no age gate or parental-control feature ([README](../README.md)). |
| User-generated content; messaging and chat; social media; advertising | No public or shared user-content capability, messaging/chat, social media, or advertising (**confirm**). Edits and exports are local photo-workflow outputs; the README documents no cloud catalog or shared library ([README](../README.md#L21-L25), [README limits](../README.md#L75-L84)). |
| Unrestricted web access | No (**confirm**). The audit lists only explicit About-page links handed to the system browser and no app-initiated network requests ([sandbox audit](APP_STORE_SANDBOX_AUDIT.md#L329-L334)). |
| Profanity/crude humor; horror/fear; alcohol, tobacco, or drug use/references | None (**confirm** against bundled and submitted sample content); these are not product features in the documented still-photo workflow ([README](../README.md), [sample-photo manifest](../Sources/KromoraKit/Resources/SamplePhotos/manifest.json#L1-L20)). |
| Medical/treatment information; health/wellness topics | None (**confirm**); not part of the documented photo-editing workflow ([README](../README.md)). |
| Mature/suggestive themes; sexual content or nudity; graphic sexual content | None (**confirm** against bundled and submitted sample content); the sample-photo manifest lists the two bundled assets ([sample-photo manifest](../Sources/KromoraKit/Resources/SamplePhotos/manifest.json#L5-L19)). |
| Cartoon/fantasy violence; realistic violence; prolonged graphic violence; guns/weapons | None (**confirm** against bundled and submitted sample content); these are not product features in the documented still-photo workflow ([README](../README.md), [sample-photo manifest](../Sources/KromoraKit/Resources/SamplePhotos/manifest.json#L5-L19)). |
| Gambling; simulated gambling; contests; loot boxes | None (**confirm**); the documented product has no games, competitions, or chance-based activities ([README](../README.md)). |

Do not select “Made for Kids” on the basis of a low calculated rating; that is a separate App Store
category choice with additional guidelines ([Apple age-rating guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/)).

## App Review notes

**Suggested review note:**

> Kromora is a local Mac photo editor and does not require an account. On first launch, choose the
> bundled sample-photo option to populate a library, or import a JPEG or a RAW file from disk. Photos
> import is optional; use the file picker or bundled samples to review the core workflow without
> Photos authorization. If you do import from Photos, macOS asks Kromora for Photos access so it
> can fetch the original files of the photos you pick. Saving an export to Photos is also optional;
> disk export remains available. Open an imported photo to review its non-destructive editing
> workflow, then choose File > Export, pick the output settings, and choose a folder. In the Look
> control, choose a bundled Starter Look; no external LUT file is needed.

This path follows the welcome options and local Library → Edit → Export flow ([onboarding](ONBOARDING.md#L3-L18),
[README](../README.md)). The bundled starter photographs are listed as CC0 1.0
assets ([sample-photo manifest](../Sources/KromoraKit/Resources/SamplePhotos/manifest.json#L1-L20)).
PhotosPicker selects the items to import, but retrieving their originals goes through PhotoKit, so
the first Photos import (and any Photos delivery) prompts for Photos read/write access; both can be
skipped when testing the local workflow and disk export ([sandbox audit](APP_STORE_SANDBOX_AUDIT.md#L361-L363),
[App Store acceptance](APP_STORE_ACCEPTANCE.md#photos-authorization-and-delivery)).
The no-account note is an inference from this local workflow and the audit's finding that the app
has no app-initiated network requests; confirm the release build still has no sign-in dependency
([README](../README.md), [sandbox audit](APP_STORE_SANDBOX_AUDIT.md#L329-L334)).

### Entitlements in one line each

| Entitlement | Purpose |
| --- | --- |
| `com.apple.security.app-sandbox` | Runs the distributed app in the macOS App Sandbox ([entitlements](../App/Kromora.entitlements#L1-L6), [audit rationale](APP_STORE_SANDBOX_AUDIT.md#L401-L414)). |
| `com.apple.security.files.user-selected.read-write` | Reads and writes files or folders the user selects, including imports, exports, and Look files ([entitlements](../App/Kromora.entitlements#L5-L9), [audit rationale](APP_STORE_SANDBOX_AUDIT.md#L401-L414)). |
| `com.apple.security.files.removable-media.read-only` | Reads imported images from mounted camera cards without writing to the card ([entitlements](../App/Kromora.entitlements#L7-L11), [audit rationale](APP_STORE_SANDBOX_AUDIT.md#L401-L414)). |
| `com.apple.security.files.bookmarks.app-scope` | Retains access to user-selected external files and folders across launches ([entitlements](../App/Kromora.entitlements#L9-L13), [audit rationale](APP_STORE_SANDBOX_AUDIT.md#L401-L414)). |
| `com.apple.security.assets.pictures.read-write` | Stores the default library package, default exports, and app-owned Looks under Pictures ([entitlements](../App/Kromora.entitlements#L11-L16), [audit rationale](APP_STORE_SANDBOX_AUDIT.md#L401-L414)). |
| `com.apple.security.personal-information.photos-library` | Lets PhotoKit authorize, fetch originals for Photos import, and save exports to Photos in the sandbox ([entitlements](../App/Kromora.entitlements#L16-L18)). |

### RAW formats

Kromora develops **RAW files supported by the macOS/Core Image decoder**. Product documentation does
not publish a fixed camera-model or extension whitelist; coverage varies with the source and macOS
decoder capabilities, so use a known-supported review file and do not claim universal RAW support
([README](../README.md)). The extension list in
[`realworldtest/README.md`](../realworldtest/README.md#L1-L20) describes local test-fixture discovery,
not a complete product compatibility guarantee; those local camera files are not release screenshot
assets.

## Description and keywords draft

### Description — draft

Kromora is a native Mac photo editor for organizing a local photo library, developing RAW and
standard still images, and exporting finished photos. Import from files, folders, Photos, or
supported removable media; accepted originals are copied into a portable library package you own.
([README](../README.md))

Edit non-destructively with RAW controls, Light, Color, Effects, crop and rotation, local masks,
Heal and Clone retouch, and reusable `.cube` Looks. Compare edits, then export one photo or a batch
as TIFF, JPEG, PNG, or HEIF. Decoder and output options vary by source and macOS capabilities.
([README](../README.md))

### Keywords — draft

`raw,photo edit,library,develop,lut,looks,retouch,masks,batch export`

The draft is under Apple's 100-character total limit; keywords are comma-separated ([product-page
guidance](https://developer.apple.com/app-store/product-page/)).

## Screenshot plan

Mac screenshots are required. Prepare the set at one accepted 16:10 size: **1280 × 800, 1440 × 900,
2560 × 1600, or 2880 × 1800 pixels** ([Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)).
Use the two bundled sample photos, **Monterey Beach** and **Golden Hour**, which the manifest lists
under CC0 1.0 ([sample-photo manifest](../Sources/KromoraKit/Resources/SamplePhotos/manifest.json#L1-L20)).

1. Library grid populated with both sample photos.
2. Edit workspace with one sample photo and visible adjustment controls.
3. Before/after or comparison view using that same photo.
4. Look browser or inspector showing bundled Starter Looks applied to a sample photo; the 13
   bundled Looks are read-only original assets ([Looks guide](LOOKS.md#L6-L8), [starter library](LOOKS.md#L33-L66)).
5. Export setup or completed export using the same sample, with an available output format visible.

Use the bundled CC0 sample images in public-facing screenshots. Do not take screenshots from personal
RAWs in the ignored `realworldtest/` directory; its README defines that folder as local test input and
keeps those files out of commits ([realworldtest rules](../realworldtest/README.md#L1-L22)).

## Human-only steps

- Enroll or confirm the organization's Apple Developer Program membership and account access.
- Create/confirm the App ID and App Store Connect app record using bundle ID `com.last8.kromora.photo`
  ([Info.plist](../App/Info.plist#L5-L13)); complete the support and privacy URL fields above.
- Configure the distribution signing certificate and provisioning profile for the account. The
  release build uses the Xcode signing and entitlement process ([Packaging](PACKAGING.md#L17-L31)).
- Archive the Release scheme, validate and upload in Xcode Organizer, then wait for App Store Connect
  processing ([App Store acceptance A27](APP_STORE_ACCEPTANCE.md#testflight-and-app-store-release-path)).
- Create an internal TestFlight group, add authorized testers, and confirm the uploaded build installs
  ([App Store acceptance A27–A28](APP_STORE_ACCEPTANCE.md#testflight-and-app-store-release-path)).
- Enter the final metadata, privacy and age-rating answers, screenshot set, and encryption response in
  App Store Connect; submit the completed version for App Review ([Apple privacy guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/),
  [age-rating guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/)).
