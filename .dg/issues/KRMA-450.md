---
id: KRMA-450
title: Add signed notarized DMG release packaging for distribution
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: scripts/release-dmg.sh produces Kromora-<version>.dmg with a properly structured Kromora.app
      result: pass
      notes: Ran KROMORA_SKIP_NOTARIZE=1 scripts/release-dmg.sh end-to-end; produced .build/releases/Kromora-<version>.dmg, mounted and verified executable/Info.plist/icon/resource bundle/entitlements.
    - criterion: Distribution builds sign with Developer ID Application + hardened runtime; Team ID/bundle ID from env not hardcoded
      result: pass
      notes: release-dmg.sh validates the identity string against 'Developer ID Application:' via security find-identity, adds --options runtime --timestamp when identity != '-', and KROMORA_BUNDLE_IDENTIFIER overrides CFBundleIdentifier without any hardcoded LUTzy identifiers.
    - criterion: Full path notarizes and staples both app and DMG when credentials configured
      result: pass
      notes: "Code path present (notarytool submit --wait, stapler staple, stapler validate for both app and DMG). Not exercised live: no Developer ID/notary credentials available in this environment, consistent with the implementer's disclosure."
    - criterion: Skip-notarization env flag builds/signs app+DMG locally without contacting Apple, documented as non-ship
      result: pass
      notes: Verified live run with KROMORA_SKIP_NOTARIZE=1; prints explicit non-ship WARNING; docs/PACKAGING.md documents this.
    - criterion: docs/PACKAGING.md documents prerequisites, usage, outputs, relation to build-macos-app.sh
      result: pass
    - criterion: Script fails closed on missing identity/profile, missing icon/plist, or failed codesign/notarize
      result: pass
      notes: "Verified: invalid version and missing KROMORA_CODESIGN_IDENTITY both exit 1 with no artifact written; cleanup() trap on EXIT/INT/TERM removes release_dmg unless success=1, and set -euo pipefail ensures any failed step (codesign/notarize/hdiutil) triggers it."
    - criterion: CI/verify helper can still validate ad-hoc/local .app builds
      result: pass
      notes: scripts/build-macos-app.sh native (default) mode is unchanged in behavior; universal mode is opt-in via KROMORA_BUILD_ARCHS. Verified native app build still signs/verifies correctly.
  checks_run:
    - zsh -n scripts/release-dmg.sh
    - zsh -n scripts/build-macos-app.sh
    - git diff --check on the commit
    - KROMORA_SKIP_NOTARIZE=1 scripts/release-dmg.sh 0.0.1-verify (full universal build, sign, DMG create, mount, verify, cleanup)
    - lipo -archs on the built executable confirmed arm64+x86_64 universal binary
    - scripts/release-dmg.sh with invalid version argument (fail-closed, no artifact)
    - scripts/release-dmg.sh with no KROMORA_CODESIGN_IDENTITY in distribution mode (fail-closed, no artifact)
    - git status --porcelain confirmed clean working tree aside from unrelated .dg bookkeeping
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-19T00:42:07.866Z
  session: 01MU7NUHCJBIME68GD
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - packaging
  - release
  - distribution
created: 2026-09-18T22:38:53.961Z
updated: 2026-09-19T00:42:07.868Z
order: a0
board: product
---

## Objective

Ship a reproducible script that builds a universal Kromora `.app`, signs it with Developer ID + hardened runtime, notarizes and staples it, packages a signed/notarized/stapled `.dmg`, and documents the exact env vars and local-skip path — so distribution and (later) in-app updates have a real artifact to consume.

## Context

### Current Kromora packaging

- `scripts/build-macos-app.sh` stages a SwiftPM release product into `.build/Kromora.app` with entitlements and icon, and can ad-hoc or identity-sign.
- `scripts/verify-app-icon.sh` and `scripts/verify-app-signature.sh` check structure/signature.
- `docs/PACKAGING.md` describes the disposable `.app` and points at Xcode Archive → Distribute for real distribution. There is **no** notarized DMG path and **no** create-dmg flow.

### Upstream reference (idea source only — adapt, do not copy branding)

LUTzy `scripts/release-dmg.sh` (commit `e2cef20` / PR #36 on `tsvb/lutzy`):

- Universal `swift build -c release --arch arm64 --arch x86_64`
- Wrap executable + Info.plist + icon into `LUTzy.app`
- Developer ID sign with hardened runtime
- Notarize + staple the app
- `create-dmg` → sign/notarize/staple the DMG
- `LUTZY_SKIP_NOTARIZE=1` for local updater dry-runs without notary round-trips

View with: `git show upstream/main:scripts/release-dmg.sh`

### Product constraints

- Keep macOS 14 deployment target in `Package.swift`; newer SDKs for building are fine (Xcode 26+ per CLAUDE.md).
- Zero third-party *code* dependencies; Homebrew `create-dmg` as a **host tool** for the release script is acceptable if documented (same posture as upstream), or implement an equivalent `hdiutil`-only path if you can keep it reliable.
- Do not commit secrets, notary credentials, or signing identities. Use env vars / keychain profiles only.
- App Sandbox + existing entitlements in `Sources/Kromora/Kromora.entitlements` must remain correct on the distributed bundle.
- Output should be deterministic enough that KRMA-451 (auto-update) can locate a `.dmg` asset on a GitHub Release by extension.

## Acceptance criteria

- [ ] A documented script (e.g. `scripts/release-dmg.sh`) produces `Kromora-<version>.dmg` containing a properly structured `Kromora.app` (executable, Info.plist, icon, resource bundle, entitlements-backed signature).
- [ ] Distribution builds sign with Developer ID Application + hardened runtime; Team ID / bundle ID come from the project / env, not hard-coded LUTzy values.
- [ ] Full path notarizes and staples **both** the app and the DMG when credentials are configured.
- [ ] A skip-notarization env flag builds/signs the app+DMG for local testing without contacting Apple (explicitly documented as non-ship).
- [ ] `docs/PACKAGING.md` (and optionally `scripts/README.md`) documents prerequisites (`create-dmg` or hdiutil alternative, notarytool profile, identity env vars), usage, outputs, and how this relates to `build-macos-app.sh`.
- [ ] Script fails closed on missing identity/profile (unless skip mode), missing icon/plist, or failed codesign/notarize steps — no partial “success” artifacts left looking shippable without stapling when stapling was required.
- [ ] CI or a verify helper can still validate ad-hoc/local `.app` builds; this ticket does not require CI to notarize.

## Out of scope

- In-app update UI / installer swap (KRMA-451; depends on this artifact shape).
- Changing App Sandbox policy or adding network entitlements beyond what notarized distribution already needs.
- Sparkle or any third-party updater framework.

## Implementation notes

1. Prefer extending or composing with `scripts/build-macos-app.sh` rather than forking a second unrelated bundler — shared staging reduces drift (resource bundle path, entitlements, icon).
2. Version argument should drive `CFBundleShortVersionString` / DMG name; build number can derive from git rev-list or an env override.
3. Universal binary: match whatever Kromora already supports; if Rosetta/x86_64 is intentionally dropped, document that explicitly instead of silently producing arm64-only.
4. Keep LUTzy attribution out of product strings; this is packaging borrowed as process, not branding.
5. After landing, a human still publishes the DMG to GitHub Releases — script should print the exact asset path.

## Verification

- Dry-run with skip-notarize on a Developer ID machine (or document blockage if identity unavailable in the agent environment).
- `codesign --verify --deep --strict` on the app; `spctl`/stapler checks when notarizing.
- Update `docs/PACKAGING.md`; `git diff --check`.
- Do not claim notarization passed unless notarytool actually succeeded in that environment.

### Comment — cursor @ 2026-09-18T22:40:12.406Z

Provenance: adapt LUTzy `scripts/release-dmg.sh` (PR #36 / e2cef20). Compose with existing `scripts/build-macos-app.sh` where possible. This ticket is the prerequisite artifact for KRMA-451 auto-update.

### Comment — codex @ 2026-09-18T23:39:49.159Z

Implemented in commit 234e29f. Added scripts/release-dmg.sh with universal arm64+x86_64 builds, version/build-number overrides, Developer ID + hardened-runtime signing, App Sandbox provisioning-profile checks, app and DMG notarization/stapling, hdiutil packaging, final mounted-DMG verification, and explicit KROMORA_SKIP_NOTARIZE=1 local dry-run behavior. Composed with build-macos-app.sh and corrected the SwiftPM resource-bundle verifier path. Updated packaging docs and scripts README. Checks passed: zsh -n, git diff --check, dg validate, SwiftPM dual-architecture release build, icon/resource verification, strict app signature/entitlement verification, universal lipo inspection, local signed DMG creation/mount/verification, and strict DMG signature verification. Apple notarization was not claimed or run because Developer ID/notary credentials were unavailable in this environment.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-19T00:42:07.866Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] scripts/release-dmg.sh produces Kromora-<version>.dmg with a properly structured Kromora.app (pass) — Ran KROMORA_SKIP_NOTARIZE=1 scripts/release-dmg.sh end-to-end; produced .build/releases/Kromora-<version>.dmg, mounted and verified executable/Info.plist/icon/resource bundle/entitlements.
- [x] Distribution builds sign with Developer ID Application + hardened runtime; Team ID/bundle ID from env not hardcoded (pass) — release-dmg.sh validates the identity string against 'Developer ID Application:' via security find-identity, adds --options runtime --timestamp when identity != '-', and KROMORA_BUNDLE_IDENTIFIER overrides CFBundleIdentifier without any hardcoded LUTzy identifiers.
- [x] Full path notarizes and staples both app and DMG when credentials configured (pass) — Code path present (notarytool submit --wait, stapler staple, stapler validate for both app and DMG). Not exercised live: no Developer ID/notary credentials available in this environment, consistent with the implementer's disclosure.
- [x] Skip-notarization env flag builds/signs app+DMG locally without contacting Apple, documented as non-ship (pass) — Verified live run with KROMORA_SKIP_NOTARIZE=1; prints explicit non-ship WARNING; docs/PACKAGING.md documents this.
- [x] docs/PACKAGING.md documents prerequisites, usage, outputs, relation to build-macos-app.sh (pass)
- [x] Script fails closed on missing identity/profile, missing icon/plist, or failed codesign/notarize (pass) — Verified: invalid version and missing KROMORA_CODESIGN_IDENTITY both exit 1 with no artifact written; cleanup() trap on EXIT/INT/TERM removes release_dmg unless success=1, and set -euo pipefail ensures any failed step (codesign/notarize/hdiutil) triggers it.
- [x] CI/verify helper can still validate ad-hoc/local .app builds (pass) — scripts/build-macos-app.sh native (default) mode is unchanged in behavior; universal mode is opt-in via KROMORA_BUILD_ARCHS. Verified native app build still signs/verifies correctly.
Checks run:
- zsh -n scripts/release-dmg.sh
- zsh -n scripts/build-macos-app.sh
- git diff --check on the commit
- KROMORA_SKIP_NOTARIZE=1 scripts/release-dmg.sh 0.0.1-verify (full universal build, sign, DMG create, mount, verify, cleanup)
- lipo -archs on the built executable confirmed arm64+x86_64 universal binary
- scripts/release-dmg.sh with invalid version argument (fail-closed, no artifact)
- scripts/release-dmg.sh with no KROMORA_CODESIGN_IDENTITY in distribution mode (fail-closed, no artifact)
- git status --porcelain confirmed clean working tree aside from unrelated .dg bookkeeping
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MU7NUHCJBIME68GD
Summary: Verified: release-dmg.sh builds, signs, and packages a universal signed DMG end-to-end (live skip-notarize run passed: universal arm64+x86_64 binary, hardened-runtime signing, DMG mount/verify, fail-closed on invalid version and missing identity). Notarize/staple code paths reviewed but not exercised (no Developer ID/notary credentials in this environment, as disclosed by the implementer). No blocking findings; no fixes needed.
