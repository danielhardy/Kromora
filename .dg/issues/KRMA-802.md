---
id: KRMA-802
title: "Retire scripts/build-macos-app.sh: package and smoke CI use the Xcode-built app"
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
  - ci
  - packaging
  - cleanup
created: 2026-10-03T19:24:39.247Z
updated: 2026-10-03T19:25:52.722Z
depends_on:
  - KRMA-801
blockers: []
order: zzzv
board: product
---

## Objective

Leave one packaging path. The Xcode project builds the app everywhere (local, CI, release), and the hand-rolled SwiftPM bundler script is deleted.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md: "thin packaging layer", not a second build architecture). `scripts/build-macos-app.sh` bundles the SwiftPM `Kromora` executable by hand and is used by CI jobs `package` and `smoke`, `docs/PACKAGING.md`, `scripts/README.md`, and `Tests/KromoraKitTests/KromoraAboutTests.swift` (it reads the script text at line ~74), plus error messages in `scripts/verify-app-icon.sh`, `verify-app-signature.sh`, and `smoke-macos-app.sh`. `swift run` remains the developer runtime and is unaffected. Hosted-runner behavior to preserve: `scripts/smoke-macos-app.sh` exits 2 when there is no WindowServer session and CI treats that as a deferred pass.

## Scope

- Point the `package` and `smoke` jobs at the Xcode-built app: run `scripts/app-store-build.sh`, then the verify scripts against `.build/xcode/Build/Products/Release/Kromora.app`, and the smoke script against the same path.
- Delete `scripts/build-macos-app.sh`; update the error messages in the verify/smoke scripts to say `run scripts/app-store-build.sh first`; update default app paths in those scripts to the Xcode output path.
- Update `KromoraAboutTests` so it asserts what it was protecting (About-view content and icon use) against the Xcode project/launcher instead of the deleted script; keep the intent of every assertion or remove an assertion only with a reason in the commit message.
- Update `docs/PACKAGING.md`, `scripts/README.md`, and `CLAUDE.md` references to the removed script.
- If `Kromora.icon`-related `actool` logic existed only in the deleted script, confirm the Xcode build covers it (the icon ticket already verified this).

## Acceptance criteria

- [ ] `scripts/build-macos-app.sh` is deleted and `grep -rn "build-macos-app" . --exclude-dir=.git --exclude-dir=.build --exclude-dir=.dg --exclude-dir=.context` returns nothing.
- [ ] `scripts/app-store-build.sh` followed by `scripts/verify-app-icon.sh`, `scripts/verify-app-signature.sh`, `scripts/verify-xcode-app.sh`, and `scripts/smoke-macos-app.sh` (exit 0 or the documented exit 2) all work against the Xcode-built app.
- [ ] `.github/workflows/ci.yml` parses and no job references a deleted script.
- [ ] `scripts/ci-tests.sh fast` and `scripts/ci-tests.sh serial` pass.

## Verification

- Run the chain above locally plus both CI lanes; validate the workflow YAML.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
