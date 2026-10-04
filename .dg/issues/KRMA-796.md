---
id: KRMA-796
title: Wire Info.plist, App Sandbox, hardened runtime, and entitlements into the Xcode target
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
  - sandbox
  - entitlements
created: 2026-10-03T19:24:29.294Z
updated: 2026-10-03T19:25:49.392Z
depends_on:
  - KRMA-795
blockers: []
order: zzv
board: product
---

## Objective

Make the Xcode-built app carry the same bundle metadata, document/UTI declarations, sandbox, and entitlements as the current SwiftPM bundle, plus the App Store metadata keys.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstreams 2 to 4). `App/Info.plist` holds keys that cannot be expressed as `INFOPLIST_KEY_*` build settings: `CFBundleDocumentTypes`, `UTExportedTypeDeclarations`, `NSPrincipalClass`, `LSMinimumSystemVersion`. Xcode merges a source plist with `GENERATE_INFOPLIST_FILE = YES` when `INFOPLIST_FILE` is set. `App/Kromora.entitlements` is the capability contract. The Photos usage string is already in `App/Info.plist` (earlier ticket). The old bundle script also injected `KromoraGitCommit` into the Info.plist; the About view may read it (`grep -rn KromoraGitCommit Sources`).

## Scope

- Set `INFOPLIST_FILE = App/Info.plist` (path relative to the project) and `CODE_SIGN_ENTITLEMENTS = App/Kromora.entitlements` in the xcconfig/target, `ENABLE_APP_SANDBOX = YES`, `ENABLE_HARDENED_RUNTIME = YES`.
- Remove from `App/Info.plist` keys that Xcode now generates or that the xcconfig owns (`CFBundleIdentifier`, `CFBundleName`, `CFBundleShortVersionString`, `CFBundleVersion`, `CFBundleExecutable`, `CFBundlePackageType`, `CFBundleInfoDictionaryVersion`, icon keys) so there is one source for each, but only after confirming the SwiftPM bundle script (`scripts/build-macos-app.sh`) still gets what it needs. If removing a key would break that script, keep the key and note it; the script is retired later.
- Add App Store metadata through `INFOPLIST_KEY_*` settings in `Base.xcconfig`: `INFOPLIST_KEY_CFBundleDisplayName = Kromora`, `INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.photography`, `INFOPLIST_KEY_NSHumanReadableCopyright` (use the copyright holder named in `LICENSE`), and export compliance `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` (Kromora uses no custom or non-exempt encryption; confirm by `grep -rn "CryptoKit\|CommonCrypto\|SecKey" Sources` and record what you found, noting hashing for content-addressing is not encryption).
- If `KromoraGitCommit` is used by the app, keep it available in the Xcode build with a Run Script phase that writes it into the built Info.plist, or document in the handoff comment that the About view degrades gracefully without it.

## Acceptance criteria

- [ ] After a Release build with `CODE_SIGNING_ALLOWED=NO`, the built `Info.plist` contains `CFBundleDocumentTypes`, `UTExportedTypeDeclarations`, `NSPhotoLibraryUsageDescription`, `LSApplicationCategoryType = public.app-category.photography`, `ITSAppUsesNonExemptEncryption = false`, `LSMinimumSystemVersion = 26.0`, `CFBundleIdentifier = com.last8.kromora.photo` (check with `plutil -p`).
- [ ] An ad-hoc-signed Release build (`CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES`) embeds the entitlements from `App/Kromora.entitlements` exactly (verify with `codesign -d --entitlements :-`) and `codesign --verify --deep --strict` passes.
- [ ] `scripts/build-macos-app.sh`, `scripts/verify-library-package-metadata.sh`, and `scripts/ci-tests.sh fast` still pass.
- [ ] The handoff comment lists the final merged Info.plist keys and anything intentionally left in `App/Info.plist`.

## Verification

- Build Release both ways; run `plutil -p` on the built Info.plist and `codesign -d --entitlements :-` on the signed build.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
