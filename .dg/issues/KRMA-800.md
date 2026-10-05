---
id: KRMA-800
title: Add scripts/app-store-build.sh to verify and archive the production target
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: verify mode succeeds and prints app path
      result: pass
      notes: BUILD SUCCEEDED; verifier ends with app path (cosmetic scripts/.. segment)
    - criterion: archive fails clearly without DEVELOPMENT_TEAM
      result: pass
      notes: exit 1 with clear message; archive with a team not run (no certificate)
    - criterion: no upload step
      result: pass
      notes: grep returns nothing
    - criterion: git status clean after run
      result: pass
      notes: .build ignored
  checks_run:
    - scripts/app-store-build.sh verify
    - env -u DEVELOPMENT_TEAM scripts/app-store-build.sh archive
    - grep -iE altool|notarytool|upload
    - git check-ignore .build
    - git status
  findings:
    - "info: printed app path includes unnormalized scripts/.. segment; cosmetic only"
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-05T00:13:05.791Z
  session: 01MUUHX61QDYPLB063
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - release
  - scripts
created: 2026-10-03T19:24:36.425Z
updated: 2026-10-05T00:13:05.796Z
depends_on:
  - KRMA-799
blockers: []
order: w
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-05T00:00:15.358Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
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


### Comment — codex @ 2026-10-05T00:00:14.895Z

Implemented and committed as a00dc741. The new script supports default Release verify and Organizer archive; verify uses ad-hoc signing unless a signing identity or team is configured, while archive requires DEVELOPMENT_TEAM. The verifier now defaults to the matching DerivedData app path. Checks passed: verify build and app verification, archive without DEVELOPMENT_TEAM fails with the expected message, zsh syntax, ignored .build output, forbidden-command scan, and diff check. xcodebuild requires the project-qualified scheme name because the Swift package also exports a Kromora scheme.

## Agent log

- 2026-10-05T00:13:05.792Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] verify mode succeeds and prints app path (pass) — BUILD SUCCEEDED; verifier ends with app path (cosmetic scripts/.. segment)
- [x] archive fails clearly without DEVELOPMENT_TEAM (pass) — exit 1 with clear message; archive with a team not run (no certificate)
- [x] no upload step (pass) — grep returns nothing
- [x] git status clean after run (pass) — .build ignored
Checks run:
- scripts/app-store-build.sh verify
- env -u DEVELOPMENT_TEAM scripts/app-store-build.sh archive
- grep -iE altool|notarytool|upload
- git check-ignore .build
- git status
Findings:
- info: printed app path includes unnormalized scripts/.. segment; cosmetic only
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUUHX61QDYPLB063
