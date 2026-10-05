---
id: KRMA-802
title: "Retire scripts/build-macos-app.sh: package and smoke CI use the Xcode-built app"
type: task
status: done
priority: medium
verification_agent: claude
human_review_required: false
verification_model: sonnet
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: build-macos-app.sh deleted and no references remain
      result: pass
    - criterion: app-store-build.sh then verify-app-icon, verify-app-signature, verify-xcode-app, smoke all work against Xcode app
      result: pass
      notes: all exit 0
    - criterion: ci.yml parses and references no deleted script
      result: pass
    - criterion: ci-tests fast and serial pass
      result: pass
      notes: fast 1522 tests, serial 490 tests, 0 failures
  checks_run:
    - grep build-macos-app
    - ruby YAML parse of ci.yml
    - scripts/app-store-build.sh
    - verify-app-icon/signature/xcode-app
    - smoke-macos-app.sh
    - ci-tests.sh fast
    - ci-tests.sh serial
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-05T02:04:23.081Z
  session: 01MUULO7SZEZD5BGD3
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
updated: 2026-10-05T02:04:23.085Z
depends_on:
  - KRMA-801
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-05T01:57:34.888Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
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


### Comment — codex @ 2026-10-05T01:57:34.423Z

Implemented the Xcode-only packaging path and removed the SwiftPM app bundler. CI, verifier defaults, About assertions, and packaging docs now target the Xcode-built app. Verified Release build, icon/signature/Xcode bundle checks, smoke export, workflow YAML, no legacy builder references, and CI lanes: fast 1,522 tests and serial 490 tests passed. Commit: dfcffbff.

## Agent log

- 2026-10-05T02:04:23.081Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] build-macos-app.sh deleted and no references remain (pass)
- [x] app-store-build.sh then verify-app-icon, verify-app-signature, verify-xcode-app, smoke all work against Xcode app (pass) — all exit 0
- [x] ci.yml parses and references no deleted script (pass)
- [x] ci-tests fast and serial pass (pass) — fast 1522 tests, serial 490 tests, 0 failures
Checks run:
- grep build-macos-app
- ruby YAML parse of ci.yml
- scripts/app-store-build.sh
- verify-app-icon/signature/xcode-app
- smoke-macos-app.sh
- ci-tests.sh fast
- ci-tests.sh serial
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUULO7SZEZD5BGD3
