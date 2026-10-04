---
id: KRMA-801
title: Add an Xcode production-build CI job and verify the app it builds
type: task
status: ready
priority: high
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
  - xcode
created: 2026-10-03T19:24:37.744Z
updated: 2026-10-03T19:25:52.196Z
depends_on:
  - KRMA-800
blockers: []
order: zzzq
board: product
---

## Objective

Catch broken Xcode project references, missing assets, bad entitlements, Info.plist problems, and SwiftPM-versus-Xcode differences in CI.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstream 6). `.github/workflows/ci.yml` has jobs `format`, `tests-fast`, `tests-resource`, `package` (runs `scripts/build-macos-app.sh` plus the icon/signature verifiers), and `smoke` (runs `scripts/smoke-macos-app.sh`, tolerating exit code 2 meaning "no WindowServer session"). All jobs run on `xcode-27`. The plan says the Xcode build should run on `main` and as release validation, not on every pull request.

## Scope

- Add a job `xcode-app` to `.github/workflows/ci.yml`, triggered on pushes to `main` and `workflow_dispatch` (add the `workflow_dispatch` trigger), that runs `scripts/app-store-build.sh` (verify mode), then asserts the working tree is unchanged (same check as the `package` job).
- Keep the existing jobs untouched in this ticket. `scripts/ci-tests.sh` and `swift build`/`swift test` behavior must not change.
- Document the job in `docs/TESTING.md` (one short paragraph: what it checks and that it runs on `main`, not on PRs).

## Acceptance criteria

- [ ] The workflow file parses (`python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))"` or `actionlint` if installed) and defines the `xcode-app` job with the stated triggers.
- [ ] Running the job's exact commands locally (`scripts/app-store-build.sh` then `git status --porcelain`) passes.
- [ ] No existing job's steps changed.

## Verification

- Validate the YAML and run the job's commands locally. The hosted run itself happens after merge.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
