---
id: KRMA-805
title: Rewrite docs/PACKAGING.md and README distribution notes for App Store, TestFlight, and source
type: task
status: ready
priority: medium
verification_agent: claude
human_review_required: false
verification_model: sonnet
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - docs
  - packaging
created: 2026-10-03T19:24:44.001Z
updated: 2026-10-03T19:25:54.429Z
depends_on:
  - KRMA-804
  - KRMA-800
blockers: []
order: zzzz
board: product
---

## Objective

Make `docs/PACKAGING.md` the accurate single guide for how Kromora is built, signed, archived, and uploaded.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, "Distribution model", Workstreams 6 and 7). Earlier tickets pruned the DMG/updater sections and replaced the bundle script with the Xcode project (`Xcode/Kromora.xcodeproj`, `Xcode/Config/*.xcconfig`, `App/`), `scripts/app-store-build.sh`, and `scripts/verify-xcode-app.sh`. Read the current `docs/PACKAGING.md`, `README.md`, `scripts/README.md`, and `docs/TESTING.md` first. `CLAUDE.md` is canonical for agents; do not duplicate its architecture section, link to it.

## Scope

Rewrite `docs/PACKAGING.md` with sections: Distribution model (App Store, TestFlight, source); Layout (what lives in `App/`, `Xcode/`, `Sources/Kromora/`); Local verification (`scripts/app-store-build.sh`, what `verify-xcode-app.sh` checks); Signing and capabilities (the final entitlement set and why each is there, App Sandbox, hardened runtime, privacy manifest, usage strings); Versioning (`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Base.xcconfig`, when to bump); Release procedure (archive in Xcode, Distribute App, App Store Connect, TestFlight first; no automated upload); CI (`xcode-app` job). Update `README.md` and `scripts/README.md` so their build/distribution notes match. State the human prerequisites (Apple Developer Program membership, App ID `com.last8.kromora.photo`, App Store Connect record, distribution certificate and profile) without including any secrets or team IDs.

## Acceptance criteria

- [ ] `docs/PACKAGING.md` covers every section above; every script, file, and setting it names exists (check each).
- [ ] No mention of DMGs, notarization, Developer ID, or the updater except one sentence saying direct distribution was retired.
- [ ] `README.md` and `scripts/README.md` agree with it.
- [ ] No source or script changes.

## Verification

- Run `grep -rniE "dmg|notariz|developer id|updater" README.md docs/PACKAGING.md scripts/README.md` and check every referenced path exists.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
