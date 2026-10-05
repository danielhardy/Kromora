---
id: KRMA-811
title: "Epic: Production build verification, CI, and documentation"
type: feature
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: scripts/app-store-build.sh verifies the production app locally and archives on request, with no upload step.
      result: pass
      notes: KRMA-800 passed; the build script exists and its verification/archive path does not upload.
    - criterion: CI builds and verifies the Xcode app on main.
      result: pass
      notes: KRMA-801 passed with CI workflow verification for the Xcode-built app on main.
    - criterion: Only one packaging path remains; an invariant test protects the thin-Xcode-layer rule.
      result: pass
      notes: KRMA-802 and KRMA-803 passed; the old packaging path was retired and the structural invariant test was added.
    - criterion: CLAUDE.md and docs/PACKAGING.md describe the new model.
      result: pass
      notes: KRMA-804 and KRMA-805 passed; both agent guidance and packaging documentation were updated.
  checks_run:
    - Confirmed declared child issues KRMA-800, KRMA-801, KRMA-802, KRMA-803, KRMA-804, and KRMA-805 are done with verification_report.verdict=pass.
    - git merge-base --is-ancestor for each declared child commit against HEAD 59f9039f (all passed).
    - Confirmed scripts/app-store-build.sh and Xcode/Kromora.xcodeproj are present.
    - Reviewed child reports for CI, single packaging path, invariant test, and documentation.
  findings: []
  fixes: []
  verification_commits:
    - a00dc741
    - f7bd5d8e
    - dfcffbff
    - 60e0331e
    - 247598c6
    - 14a490b4
  actor: codex
  resolved_model: unknown
  completed_at: 2026-10-05T14:50:51.673Z
  session: 01MUVDADXCHSFX1CBA
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - epic
  - appstore
created: 2026-10-03T19:25:24.781Z
updated: 2026-10-05T14:50:51.676Z
depends_on:
  - KRMA-800
  - KRMA-801
  - KRMA-802
  - KRMA-803
  - KRMA-804
  - KRMA-805
blockers: []
order: a0
board: product
commits:
  - a00dc741
  - f7bd5d8e
  - dfcffbff
  - 60e0331e
  - 247598c6
  - 14a490b4
---

## Completion disposition

This aggregate tracking parent is complete: each declared child dependency is done with a passing verification report, and each child implementation commit is present in repository history.

## Objective

Make the production build repeatable and guarded: release script, CI job, one packaging path, an invariant test, and agent and packaging docs.

Source plan: `.context/2026-09-30-app-store-release-plan.md` (Plan Workstreams 6, 7, 8).

## Outcome

- [x] `scripts/app-store-build.sh` verifies the production app locally and archives on request, with no upload step.
- [x] CI builds and verifies the Xcode app on `main`.
- [x] Only one packaging path remains; an invariant test protects the thin-Xcode-layer rule.
- [x] CLAUDE.md and docs/PACKAGING.md describe the new model.

## Child tickets (in execution order)

- KRMA-800 — Add scripts/app-store-build.sh to verify and archive the production target
- KRMA-801 — Add an Xcode production-build CI job and verify the app it builds
- KRMA-802 — Retire scripts/build-macos-app.sh: package and smoke CI use the Xcode-built app
- KRMA-803 — Add a structural test that the Xcode project stays a thin packaging layer
- KRMA-804 — Document the build architecture invariant for agents in CLAUDE.md and AGENTS.md
- KRMA-805 — Rewrite docs/PACKAGING.md and README distribution notes for App Store, TestFlight, and source

## Agent log

- 2026-10-05T14:50:51.673Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] scripts/app-store-build.sh verifies the production app locally and archives on request, with no upload step. (pass) — KRMA-800 passed; the build script exists and its verification/archive path does not upload.
- [x] CI builds and verifies the Xcode app on main. (pass) — KRMA-801 passed with CI workflow verification for the Xcode-built app on main.
- [x] Only one packaging path remains; an invariant test protects the thin-Xcode-layer rule. (pass) — KRMA-802 and KRMA-803 passed; the old packaging path was retired and the structural invariant test was added.
- [x] CLAUDE.md and docs/PACKAGING.md describe the new model. (pass) — KRMA-804 and KRMA-805 passed; both agent guidance and packaging documentation were updated.
Checks run:
- Confirmed declared child issues KRMA-800, KRMA-801, KRMA-802, KRMA-803, KRMA-804, and KRMA-805 are done with verification_report.verdict=pass.
- git merge-base --is-ancestor for each declared child commit against HEAD 59f9039f (all passed).
- Confirmed scripts/app-store-build.sh and Xcode/Kromora.xcodeproj are present.
- Reviewed child reports for CI, single packaging path, invariant test, and documentation.
Findings:
- None
Fixes:
- None
Verification commits:
- a00dc741
- f7bd5d8e
- dfcffbff
- 60e0331e
- 247598c6
- 14a490b4
Actor: codex
Resolved model: unknown
Pickup session: 01MUVDADXCHSFX1CBA
Summary: Verified: all six production build, CI, packaging, and documentation tickets are done with passing reports and their commits are in repository history.
