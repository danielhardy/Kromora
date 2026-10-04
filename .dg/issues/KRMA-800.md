---
id: KRMA-800
title: Add scripts/app-store-build.sh to verify and archive the production target
type: task
status: ready
priority: medium
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - release
  - scripts
created: 2026-10-03T19:24:36.425Z
updated: 2026-10-03T19:25:51.669Z
depends_on:
  - KRMA-799
blockers: []
order: zzzh
board: product
---

## Objective

Provide one release-oriented command that builds and verifies the production app, and optionally creates an archive for Xcode Organizer upload.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstream 7): early releases are archived and uploaded manually via Xcode (Product > Archive > Distribute App > App Store Connect); do not automate upload or submission. `Xcode/Kromora.xcodeproj`, scheme `Kromora`, and `scripts/verify-xcode-app.sh` exist. Style: zsh, `set -euo pipefail`, like `scripts/build-macos-app.sh`.

## Scope

- Create `scripts/app-store-build.sh` with two modes: default `verify` runs `xcodebuild -project Xcode/Kromora.xcodeproj -scheme Kromora -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode build` (ad-hoc signed unless `KROMORA_CODESIGN_IDENTITY` or `DEVELOPMENT_TEAM` is set, then Apple Development signing) followed by `scripts/verify-xcode-app.sh`; `archive` runs `xcodebuild archive -archivePath .build/xcode/Kromora.xcarchive` and prints the Organizer instructions. It must never upload.
- Make `verify-xcode-app.sh`'s default path match the DerivedData output (`.build/xcode/Build/Products/Release/Kromora.app`).
- Add the script to `scripts/README.md` and `.gitignore` check that `.build/` is already ignored.

## Acceptance criteria

- [ ] `scripts/app-store-build.sh` (verify mode) succeeds from a clean checkout and ends by printing the app path.
- [ ] `scripts/app-store-build.sh archive` creates `.build/xcode/Kromora.xcarchive` when signing is configured, and fails with a clear message when `DEVELOPMENT_TEAM` is not set (do not require a certificate for verify mode).
- [ ] The script contains no upload step (`grep -iE "altool|notarytool|upload" scripts/app-store-build.sh` returns nothing).
- [ ] `git status` is clean after a run (all output under `.build/`).

## Verification

- Run verify mode; run archive mode without a team to confirm the failure message.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
