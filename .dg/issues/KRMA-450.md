---
id: KRMA-450
title: Add signed notarized DMG release packaging for distribution
type: task
status: ready
priority: high
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - packaging
  - release
  - distribution
created: 2026-09-18T22:38:53.961Z
updated: 2026-09-18T22:40:12.406Z
order: n
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
