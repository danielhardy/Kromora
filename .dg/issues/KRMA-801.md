---
id: KRMA-801
title: Add an Xcode production-build CI job and verify the app it builds
type: task
status: done
priority: high
verification_agent: claude
human_review_required: false
verification_model: sonnet
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Workflow parses and defines xcode-app job with stated triggers
      result: pass
      notes: Ruby YAML load OK; push to main, pull_request, workflow_dispatch; job gated on push||workflow_dispatch
    - criterion: Running scripts/app-store-build.sh then git status --porcelain passes locally
      result: pass
      notes: BUILD SUCCEEDED, all bundle/signature/icon verifiers passed, no non-.dg changes in tree
    - criterion: No existing job steps changed
      result: pass
      notes: Diff has no removed lines; only additions of workflow_dispatch trigger and xcode-app job
  checks_run:
    - ruby YAML parse of ci.yml
    - git diff f7bd5d8e~1..f7bd5d8e (no deletions)
    - scripts/app-store-build.sh (verify mode)
    - git status --porcelain --untracked-files=all
  findings: []
  fixes: []
  verification_commits:
    - f7bd5d8e
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-05T00:19:08.821Z
  session: 01MUUI4X9D6LMHFCM1
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - ci
  - xcode
created: 2026-10-03T19:24:37.744Z
updated: 2026-10-05T00:19:08.829Z
depends_on:
  - KRMA-800
blockers: []
order: z
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-05T00:18:06.061Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - f7bd5d8e
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


### Comment — codex @ 2026-10-05T00:17:57.202Z

Implemented the main push and manual-dispatch xcode-app CI job using scripts/app-store-build.sh, including a clean-worktree assertion; documented its scope in docs/TESTING.md. Ruby YAML parsing, git diff --check, and the local Xcode Release build plus app verifiers passed. Existing CI job steps are unchanged. Commit: f7bd5d8e.

## Agent log

- 2026-10-05T00:19:08.822Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Workflow parses and defines xcode-app job with stated triggers (pass) — Ruby YAML load OK; push to main, pull_request, workflow_dispatch; job gated on push||workflow_dispatch
- [x] Running scripts/app-store-build.sh then git status --porcelain passes locally (pass) — BUILD SUCCEEDED, all bundle/signature/icon verifiers passed, no non-.dg changes in tree
- [x] No existing job steps changed (pass) — Diff has no removed lines; only additions of workflow_dispatch trigger and xcode-app job
Checks run:
- ruby YAML parse of ci.yml
- git diff f7bd5d8e~1..f7bd5d8e (no deletions)
- scripts/app-store-build.sh (verify mode)
- git status --porcelain --untracked-files=all
Findings:
- None
Fixes:
- None
Verification commits:
- f7bd5d8e
Actor: claude
Resolved model: sonnet
Pickup session: 01MUUI4X9D6LMHFCM1
Summary: Verified xcode-app CI job: YAML parses, triggers and if-condition correct, existing jobs untouched, local app-store-build.sh verify passes and leaves tree clean.
