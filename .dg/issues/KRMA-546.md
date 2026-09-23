---
id: KRMA-546
title: Implement updater re-verification, sandbox gating, and PACKAGING.md docs for KRMA-533
type: task
status: blocked
priority: high
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - security
  - distribution
created: 2026-09-23T01:34:35.820Z
updated: 2026-09-23T03:15:13.220Z
order: n
board: product
blocked_reason: "The required signed, sandboxed release install test cannot run in this environment: no Developer ID signing identity, matching provisioning profile, or notary credential is available, so hdiutil and /Applications replacement behavior remain unverified."
blocked_action: Provide/configure the Developer ID Application identity, matching sandbox provisioning profile, and notary profile; then run the PACKAGING.md sandbox test and record the per-stage outcome.
blocked_from_status: claimed
---

## Objective

KRMA-533 was moved through review → verification without any implementation
commit. `git log` shows no commit touching `UpdateInstaller.swift`,
`docs/PACKAGING.md`, or updater tests since d03d5d9 (KRMA-451/-450 era); the
implementation claim (codex session 01MUD8VGM17IRFJXPK) transitioned the issue
straight to `review` with no code change and no completion comment recorded
in `.project/events.jsonl`. None of KRMA-533's scope items are done. This
ticket carries the real implementation work forward.

## Evidence checked during KRMA-533 verification

- `Sources/KromoraKit/Presentation/UpdateInstaller.swift`: `install(_:)` still
  calls `verify(newApp, against: identity)` once, while the app is mounted
  read-only on the DMG, then calls `swap(newApp:into:)`, which `copyItem`s the
  verified app into a staged sibling and renames it into place — the staged
  copy itself is never re-verified after the copy and before the atomic
  rename that replaces the running app.
- No test in `Tests/KromoraKitTests/` exercises re-verification of the staged
  copy or a failure path before rename (only `UpdateTests.swift` mocks
  `install` at a higher level).
- `KromoraUpdateInstaller.canInstallInPlace` only checks that the running
  bundle has a readable code signature; it does not reflect any sandboxed
  in-place-install outcome, and there is no fallback wiring gating it off.
- `docs/PACKAGING.md` documents the pre-copy verification and the network
  entitlement, but has no section on the `-noverify` `hdiutil attach` flag
  rationale (verification is done via `SecStaticCode`, not by hdiutil) or on
  the outcome of a manual signed, sandboxed direct-distribution install test.

## Scope (unchanged from KRMA-533)

- Re-run `verify(newApp)` against the staged copy in `swap(newApp:into:)`
  after `copyItem` and before the rename that replaces `currentApp`; treat a
  failure there as `InstallError.signatureRejected` and clean up the staged
  copy without touching `currentApp`.
- Add a regression test proving a staged copy that fails verification is
  rejected before the rename (i.e. `currentApp` is left untouched).
- Perform (and record) a manual check using a signed, sandboxed
  `KROMORA_DIRECT_DISTRIBUTION=1` release build: does `hdiutil attach` via
  `Process`, DMG validation, staging, and the in-place `/Applications` swap
  actually work under App Sandbox? Record reproducible steps and the
  pass/fail outcome.
- If in-place install cannot work under the sandbox, gate
  `canInstallInPlace` on the real outcome and fall back to opening the
  release page; if a separate unsandboxed direct-distribution entitlement
  policy is the approved product decision instead, implement and document
  that.
- Document the `-noverify` choice (hdiutil skips DMG-level verification
  because the app inside is independently verified via `SecStaticCode`
  against the running app's Developer ID/Team ID/bundle ID) and the sandbox
  manual-test outcome in `docs/PACKAGING.md`.
- Keep release notes rendered as plain text; do not broaden remote content
  rendering.

## Acceptance criteria

- [ ] `swap(newApp:into:)` re-verifies the staged copy after copy and before
      the atomic rename; a regression test proves rejection and no mutation
      of `currentApp` on failure.
- [ ] Manual signed sandboxed release-build outcome (pass or fail, with
      reproducible steps) is recorded in `docs/PACKAGING.md`.
- [ ] Unsupported in-place install is not advertised; `canInstallInPlace`
      reflects the actual supported outcome and any fallback is user-safe
      and actionable.
- [ ] `docs/PACKAGING.md` documents the `-noverify` rationale.
- [ ] Updater security invariants remain intact; `swift test` passes for the
      affected lanes.

## Dependencies and coordination

Blocks KRMA-533 (parent). Independent otherwise; keep scoped to the updater/
distribution work described above.


### Comment — codex @ 2026-09-23T02:48:24.891Z

Implemented staged-copy signature re-verification before replacement, regression coverage proving a rejection leaves the installed app untouched, and PACKAGING.md guidance for -noverify and sandbox validation. In-place install is disabled pending signed sandboxed end-to-end validation; focused direct-distribution updater tests pass (6/6). Full direct-distribution suite was stopped after unrelated failures in AppViewModelTests, DevelopInspectorTests, CopyPasteTests, and KeyMonitorTests. Commit: f1c5a96.


### Comment — codex @ 2026-09-23T03:15:13.220Z

KRMA-546 credential setup checklist for the signed, sandboxed manual test

These are team-owned Apple Developer credentials. An Account Holder (or a team member with the required Certificates, Identifiers & Profiles access) should create/configure them on the Mac that will run the release test. Keep the certificate private key and notarization secret in Keychain; do not attach or paste secrets into this ticket.

1. **Developer ID Application signing identity**
   - Sign in to the team's Apple Developer account and open **Certificates, Identifiers & Profiles → Certificates → + → Software → Developer ID**.
   - Create a CSR in Keychain Access on the test Mac, upload it, download the generated `.cer`, and double-click it to install it in that Mac's login keychain. Choose **Developer ID Application** (the app signing identity); Developer ID Installer is for `.pkg` installers and is not what this DMG workflow uses.
   - Confirm the identity/private key is available: `security find-identity -v -p codesigning`. Record the exact `Developer ID Application: … (TEAMID)` identity for `KROMORA_CODESIGN_IDENTITY`.
   - Apple instructions: https://developer.apple.com/help/account/certificates/create-developer-id-certificates

2. **Matching macOS Developer ID provisioning profile**
   - In **Certificates, Identifiers & Profiles → Profiles → +**, create a **Developer ID** distribution profile (not Mac App Store or development).
   - Select the explicit App ID matching this app's bundle ID, `com.kromora.photo`, and the Developer ID Application certificate from step 1. Ensure the app's configured entitlements/capabilities are compatible with the profile; download the generated `.provisionprofile` to the test Mac.
   - Set `KROMORA_PROVISIONING_PROFILE` to the absolute path of that downloaded file. The release script embeds it in the app as `Contents/embedded.provisionprofile`; verify it is present in the built app before testing.
   - Apple guide: https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/ . Apple notes macOS Developer ID profiles are for distribution and are embedded at `MyApp.app/Contents/embedded.provisionprofile`: https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles

3. **Notarization credential profile**
   - Use the team's Apple Account and Team ID. For Apple ID authentication, create an app-specific password in the Apple Account settings, then store it in the macOS Keychain through `notarytool` (the command prompts for the password):
     `xcrun notarytool store-credentials "kromora-notary" --apple-id "APPLE_ID" --team-id "TEAMID"`
   - Alternatively, use an App Store Connect API key if that is the team's established notarization method. Do not put the app-specific password/API private key in source control or this ticket.
   - Set `KROMORA_NOTARY_PROFILE=kromora-notary`. Apple notarization credential instructions: https://developer.apple.com/documentation/security/customizing-the-notarization-workflow

4. **Run and record the blocked acceptance check**
   - From the repository root, run the documented signed direct-distribution release command, substituting the version to test:
     `KROMORA_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" KROMORA_PROVISIONING_PROFILE="/absolute/path/Kromora.provisionprofile" KROMORA_NOTARY_PROFILE="kromora-notary" scripts/release-dmg.sh 1.2.3`
   - Use the generated signed, notarized DMG for the sandbox test steps in `docs/PACKAGING.md`. Record macOS version, app version/build and pass/fail for process launch, DMG attach/validation, staging/re-verification, and replacement in `/Applications`. Keep the release-page fallback enabled unless the complete test passes reproducibly.

Apple's certificate/profile steps require access to the team's Apple Developer account. Once the identity, profile, and notary Keychain profile are configured on the test machine, the remaining setup and verification steps are documented in `docs/PACKAGING.md`.
