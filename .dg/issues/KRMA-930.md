---
id: KRMA-930
title: Get CI green on the release candidate (push main, fix CI-only failures)
type: task
status: review
priority: high
human_review_required: true
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - must-fix
  - ci
created: 2026-10-13T14:47:40.853Z
updated: 2026-10-21T14:19:37.135Z
parent: KRMA-922
depends_on:
  - KRMA-927
  - KRMA-928
  - KRMA-929
blockers:
  - id: evt_mv7149c2_hsxffw
    type: human
    reason: CI has not run on the release candidate
    action: Push main (or a release branch) and share the Actions run URL
    created_at: 2026-10-13T18:43:24.098Z
    resolved_at: 2026-10-21T13:08:33.491Z
    resolved_by: cli
  - id: evt_mvi5kxr4_fuhwu8
    type: human
    reason: The CI fixes are committed locally, but the required Actions rerun needs a human push.
    action: Push commit 5680094721eb7b73a4e99ebc8526252310d96815 to main and share the new GitHub Actions run URL.
    created_at: 2026-10-21T13:33:48.640Z
    resolved_at: 2026-10-21T13:41:53.093Z
    resolved_by: cli
  - id: evt_mvi6him8_yo11kp
    type: human
    reason: The smoke-harness fix is committed locally; validating it requires a human push and another Actions run.
    action: Push commit c2f4f2a8 to main and share the new GitHub Actions run URL.
    created_at: 2026-10-21T13:59:08.672Z
    resolved_at: 2026-10-21T14:00:10.580Z
    resolved_by: cli
  - id: evt_mvi77ui7_c25u9r
    type: human
    reason: The smoke and AppKit test fixes are committed locally; full CI verification requires a human push.
    action: Push commit d158e448849e993bb531672e3845d7494a9b7e40 to main and share the new GitHub Actions run URL.
    created_at: 2026-10-21T14:19:37.135Z
order: zr
board: product
blocked_reason: The smoke and AppKit test fixes are committed locally; full CI verification requires a human push.
blocked_action: Push commit d158e448849e993bb531672e3845d7494a9b7e40 to main and share the new GitHub Actions run URL.
blocked_from_status: ready
---

## Objective

CI must run on the exact release-candidate commit and be green. Today `main` is 156 commits ahead of
`origin/main` and CI has never run on it.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding M4 (fourth bullet). `CLAUDE.md` describes CI: GitHub Actions arm64
`xcode-27` image runs `scripts/ci-tests.sh fast` (parallel) and `serial`, optional lanes on demand,
then builds and verifies the packaged app (`scripts/app-store-build.sh`). Pushing is a human-approved
action in this repo (`.dg/AGENTS.md`: push only when a human asks).

## Acceptance criteria

- [ ] A HUMAN pushes `main` (or a release branch) after tickets KRMA-927, KRMA-928, KRMA-929 are done and
      KRMA-920 is verified. Agents must NOT push.
- [ ] All CI jobs pass on the pushed commit. For each CI-only failure (different Xcode image,
      slower runners), either fix it with a commit `KRMA-<this>: …` or file a child ticket.
- [ ] The passing run URL and commit SHA are recorded in a comment on this ticket.

## Implementation notes

Block on the human with: reason "CI has not run on the release candidate", action "Push main (or a
release branch) and share the Actions run URL". Once the URL exists, an agent can read failures with
`gh run view --log-failed`.


### Comment — codex @ 2026-10-19T17:03:31.404Z

October 19 review follow-ups are under KRMA-1051: KRMA-1054 owns the reproduced production entitlement-allowlist failure; KRMA-1055 owns the retired export UI smoke path; KRMA-1056 and KRMA-1057 own emitted test-isolation warnings and enforcement. Consume those fixes when evaluating release-candidate CI. Ticket filing performed no push, CI rerun, or remote status claim.


### Comment — codex @ 2026-10-21T13:33:45.867Z

The Actions run https://github.com/danielhardy/Kromora/actions/runs/39605333307 failed on d022893fe973f72ed18299bb8a07238d34fb710a: first-run onboarding blocked the smoke picker; CropKeyboardWindowTests ran in the parallel lane; LookPreviewTests relied on a fixed 10 ms cancellation window; and the slider animation test relied on a fixed 430 ms wait. Fixed in 5680094721eb7b73a4e99ebc8526252310d96815. Checks passed: CI lane audit (2,755 tests partitioned), 38 focused tests, Swift format, shell syntax, AppleScript compile, and git diff check. Human action: push this commit to main and share the new Actions run URL; repo policy prohibits agent pushes.


### Comment — codex @ 2026-10-21T13:59:02.898Z

Actions run https://github.com/danielhardy/Kromora/actions/runs/39610173168 on 5680094721eb7b73a4e99eb8bb? failed the Application smoke path at Open Image panel did not appear; the invocation used Command-O after readiness, but the panel never opened. Packaging, Xcode build, formatting, and the parallel test lane passed. The serial test lane was still running at the last check. Changed the harness to click the enabled File > Open Image… menu item directly and committed as c2f4f2a8. Local checks passed: zsh syntax, compiled AppleScript, and git diff check. Repo policy requires a human push for the next Actions run.


### Comment — codex @ 2026-10-21T13:59:06.599Z

Correction: the full head SHA for run 39610173168 is 5680094721eb7b73a4e99ebc8526252310d96815; the SHA in my previous comment was mistyped.


### Comment — codex @ 2026-10-21T14:19:36.913Z

Actions run https://github.com/danielhardy/Kromora/actions/runs/39612853644 on  c2f4f2a842ea7a8065a47f19f67c1bb9582a10cb failed in two places. Application smoke still searched for Open Image as a standalone window; AppKit presents NSOpenPanel as a sheet attached to the main window. The serial lane had four assertions fail across CropKeyboardWindowTests because NSApp.sendEvent did not deliver synthesized keys from the inactive XCTest app. Formatting, package build, Xcode app build, and the parallel test lane passed. Fixed the smoke sheet hierarchy in 8a343d7c and changed the crop tests to send these no-menu-equivalent keys through the target NSWindow in d158e448849e993bb531672e3845d7494a9b7e40. Local verification: both CropKeyboardWindowTests pass, changed-file Swift format passes, shell syntax and AppleScript compilation pass, and git diff check passes. Repo acceptance requires a human push for the next full Actions run.
