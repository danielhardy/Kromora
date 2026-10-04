---
id: KRMA-789
title: Delete the DMG release script and prune direct-distribution docs
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
  - distribution
  - cleanup
  - docs
created: 2026-10-03T19:24:17.998Z
updated: 2026-10-03T19:25:45.398Z
depends_on:
  - KRMA-788
blockers: []
order: zq
board: product
---

## Objective

Remove the DMG/Developer ID/notarization release path and the documentation that describes direct downloads and the updater.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstream 5). `scripts/release-dmg.sh` (231 lines) builds, signs with Developer ID, notarizes, staples, and packages a DMG. `docs/PACKAGING.md` (141 lines) documents the updater, "Sandboxed updater validation", and "Signed DMG releases". `scripts/README.md` lists `release-dmg.sh` as an active script. The lower-level `scripts/build-macos-app.sh` stays for now (a later ticket replaces it with the Xcode build); it is not direct-distribution specific.

## Scope

- `git rm scripts/release-dmg.sh` and remove its row from `scripts/README.md`.
- In `docs/PACKAGING.md` delete the updater paragraphs, the whole "Sandboxed updater validation" section, the paragraph about `KROMORA_DIRECT_DISTRIBUTION`, and the whole "Signed DMG releases" section. Keep the Icon and Signing and entitlements material that still applies to `build-macos-app.sh` and the sandbox. Add one short paragraph stating that Kromora is distributed only through the Mac App Store and TestFlight, and that direct-download distribution was retired (full rewrite happens in a later docs ticket).
- Remove DMG, notarization, and updater mentions from `README.md`, `docs/PRODUCT_SCOPE.md`, and `docs/TESTING.md` if present (`grep -rniE "dmg|notariz|updater|developer id" README.md docs scripts CLAUDE.md`); leave historical records under `.dg/` and `.context/` alone.

## Acceptance criteria

- [ ] `scripts/release-dmg.sh` is gone and `grep -rniE "release-dmg|\.dmg|notarytool|stapler|updater" README.md docs scripts CLAUDE.md AGENTS.md .github` returns nothing (docs may say "direct-download distribution was retired").
- [ ] `docs/PACKAGING.md` still accurately describes `scripts/build-macos-app.sh`, icon verification, and entitlements.
- [ ] `swift build` still succeeds and no workflow in `.github/workflows` references a deleted script.

## Verification

- Run the grep above and `swift build`; read the remaining `docs/PACKAGING.md` once for accuracy.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
