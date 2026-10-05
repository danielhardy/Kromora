---
id: KRMA-796
title: Wire Info.plist, App Sandbox, hardened runtime, and entitlements into the Xcode target
type: task
status: done
priority: high
verification_agent: claude
human_review_required: false
verification_model: sonnet
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Unsigned Release build Info.plist contains required keys
      result: pass
      notes: Built with -target Kromora; DocumentTypes, UTExportedTypeDeclarations, photo usage string, category, ITSAppUsesNonExemptEncryption=false, LSMinimumSystemVersion 26.0, bundle id all present.
    - criterion: Ad-hoc signed Release embeds exact entitlements and codesign verify passes
      result: pass
      notes: Five entitlements match App/Kromora.entitlements; flags adhoc,runtime; verify --deep --strict OK.
    - criterion: build-macos-app.sh, verify-library-package-metadata.sh, ci-tests.sh fast pass
      result: pass
      notes: All exit 0; 1522 tests.
    - criterion: Handoff comment lists merged keys and retained plist keys
      result: pass
  checks_run:
    - xcodebuild unsigned Release + plutil -p
    - xcodebuild ad-hoc signed Release + codesign -d --entitlements / --verify --deep --strict
    - scripts/build-macos-app.sh
    - scripts/verify-library-package-metadata.sh
    - scripts/ci-tests.sh fast
    - git diff --check
  findings:
    - "Minor: copyright string matches LICENSE holders (Tim; Daniel Hardy). Scheme name 'Kromora' is ambiguous between project and package; xcodebuild -scheme Kromora picks the package scheme, so use -target or the project scheme explicitly."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-04T19:39:16.180Z
  session: 01MUU7UEWEXGVD26J0
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
updated: 2026-10-04T19:39:16.185Z
depends_on:
  - KRMA-795
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-04T19:30:21.873Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
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


### Comment — codex @ 2026-10-04T19:30:21.307Z

Implemented and committed as 752a93b5.

The Xcode target now merges App/Info.plist, signs with App/Kromora.entitlements, enables App Sandbox and hardened runtime, and generates the App Store display name, photography category, copyright, and non-exempt-encryption metadata. Release disables Xcode base-entitlement injection so the embedded capability set matches the explicit entitlement file exactly.

Final merged Info.plist keys: BuildMachineOSBuild, CFBundleDevelopmentRegion, CFBundleDisplayName, CFBundleDocumentTypes, CFBundleExecutable, CFBundleIdentifier, CFBundleInfoDictionaryVersion, CFBundleName, CFBundlePackageType, CFBundleShortVersionString, CFBundleSupportedPlatforms, CFBundleVersion, DTCompiler, DTPlatformBuild, DTPlatformName, DTPlatformVersion, DTSDKBuild, DTSDKName, DTXcode, DTXcodeBuild, ITSAppUsesNonExemptEncryption, LSApplicationCategoryType, LSMinimumSystemVersion, NSHighResolutionCapable, NSHumanReadableCopyright, NSPhotoLibraryUsageDescription, NSPrincipalClass, UTExportedTypeDeclarations.

App/Info.plist intentionally retains CFBundleDocumentTypes, CFBundleExecutable, CFBundleIdentifier, CFBundleInfoDictionaryVersion, CFBundleName, CFBundlePackageType, CFBundleShortVersionString, CFBundleVersion, LSMinimumSystemVersion, NSHighResolutionCapable, NSPhotoLibraryUsageDescription, NSPrincipalClass, and UTExportedTypeDeclarations. The standard identity/version fields remain because the SwiftPM bundle script copies this plist directly. The script supplies the icon keys itself. Xcode supplies CFBundleDisplayName; the SwiftPM bundle name remains Kromora. KromoraGitCommit is absent from Xcode builds; the About view gracefully shows the version without a commit identifier.

The CryptoKit scan found SHA-256 hashing for identities, checksums, fingerprints, and cache keys; it found no CommonCrypto or SecKey use and no AES-GCM, ChaChaPoly, SymmetricKey, HMAC, seal, or open encryption operations. Content-addressing hashes are not encryption, supporting ITSAppUsesNonExemptEncryption=false.

Verification passed: unsigned Release build and required merged-plist values; ad-hoc-signed Release with the exact five entitlements, hardened-runtime signature flag, and codesign --verify --deep --strict; scripts/build-macos-app.sh; scripts/verify-library-package-metadata.sh; scripts/ci-tests.sh fast (1,522 tests); git diff --check.

## Agent log

- 2026-10-04T19:39:16.180Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Unsigned Release build Info.plist contains required keys (pass) — Built with -target Kromora; DocumentTypes, UTExportedTypeDeclarations, photo usage string, category, ITSAppUsesNonExemptEncryption=false, LSMinimumSystemVersion 26.0, bundle id all present.
- [x] Ad-hoc signed Release embeds exact entitlements and codesign verify passes (pass) — Five entitlements match App/Kromora.entitlements; flags adhoc,runtime; verify --deep --strict OK.
- [x] build-macos-app.sh, verify-library-package-metadata.sh, ci-tests.sh fast pass (pass) — All exit 0; 1522 tests.
- [x] Handoff comment lists merged keys and retained plist keys (pass)
Checks run:
- xcodebuild unsigned Release + plutil -p
- xcodebuild ad-hoc signed Release + codesign -d --entitlements / --verify --deep --strict
- scripts/build-macos-app.sh
- scripts/verify-library-package-metadata.sh
- scripts/ci-tests.sh fast
- git diff --check
Findings:
- Minor: copyright string matches LICENSE holders (Tim; Daniel Hardy). Scheme name 'Kromora' is ambiguous between project and package; xcodebuild -scheme Kromora picks the package scheme, so use -target or the project scheme explicitly.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUU7UEWEXGVD26J0
Summary: Verified: Xcode target merges Info.plist, exact entitlements, sandbox + hardened runtime; all checks pass.
