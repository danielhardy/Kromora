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
updated: 2026-10-19T17:03:31.405Z
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
order: zr
board: product
blocked_reason: CI has not run on the release candidate
blocked_action: Push main (or a release branch) and share the Actions run URL
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
