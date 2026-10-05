---
id: KRMA-805
title: Rewrite docs/PACKAGING.md and README distribution notes for App Store, TestFlight, and source
type: task
status: done
priority: medium
verification_agent: claude
human_review_required: false
verification_model: sonnet
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: docs/PACKAGING.md covers every section; every named script/file/setting exists
      result: pass
      notes: All paths, xcconfig settings, entitlements, script modes, CI job and verifier checks confirmed against the repo.
    - criterion: No DMG/notarization/Developer ID/updater mention beyond one retirement sentence
      result: pass
      notes: Required grep returns no matches; retirement stated as "Direct-download distribution was retired."
    - criterion: README.md and scripts/README.md agree
      result: pass
      notes: Archive path, verify-xcode-app.sh entry, and distribution notes are consistent.
    - criterion: No source or script changes
      result: pass
      notes: Commit 14a490b4 touches only README.md, docs/PACKAGING.md, scripts/README.md.
  checks_run:
    - grep -rniE "dmg|notariz|developer id|updater" README.md docs/PACKAGING.md scripts/README.md (no matches)
    - path existence check for all referenced files/scripts/docs
    - cross-check of entitlements, xcconfig settings, app-store-build.sh signing/archive logic, verify-xcode-app.sh checks, ci.yml xcode-app job
    - git diff --check (clean)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-05T02:31:59.019Z
  session: 01MUUMVR6GAA3BMFAI
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - docs
  - packaging
created: 2026-10-03T19:24:44.001Z
updated: 2026-10-05T02:31:59.023Z
depends_on:
  - KRMA-804
  - KRMA-800
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-05T02:31:26.083Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Make `docs/PACKAGING.md` the accurate single guide for how Kromora is built, signed, archived, and uploaded.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, "Distribution model", Workstreams 6 and 7). Earlier tickets pruned the DMG/updater sections and replaced the bundle script with the Xcode project (`Xcode/Kromora.xcodeproj`, `Xcode/Config/*.xcconfig`, `App/`), `scripts/app-store-build.sh`, and `scripts/verify-xcode-app.sh`. Read the current `docs/PACKAGING.md`, `README.md`, `scripts/README.md`, and `docs/TESTING.md` first. `CLAUDE.md` is canonical for agents; do not duplicate its architecture section, link to it.

## Scope

Rewrite `docs/PACKAGING.md` with sections: Distribution model (App Store, TestFlight, source); Layout (what lives in `App/`, `Xcode/`, `Sources/Kromora/`); Local verification (`scripts/app-store-build.sh`, what `verify-xcode-app.sh` checks); Signing and capabilities (the final entitlement set and why each is there, App Sandbox, hardened runtime, privacy posture, platform-applicable manifest requirements, usage strings); Versioning (`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Base.xcconfig`, when to bump); Release procedure (archive in Xcode, Distribute App, App Store Connect, TestFlight first; no automated upload); CI (`xcode-app` job). State the human prerequisites (Apple Developer Program membership, App ID `com.last8.kromora.photo`, App Store Connect record, distribution certificate and profile) without including any secrets or team IDs. For Kromora's native macOS-only target, do not describe a required-reason API manifest as a current signing or packaging prerequisite; refer to `docs/APP_STORE_SANDBOX_AUDIT.md` for the current platform scope and revisit if target platforms or SDK requirements change.

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


### Comment — codex @ 2026-10-05T02:31:20.608Z

Rewrote the packaging guide for App Store, TestFlight, and source workflows; documented build/archive signing, entitlements, privacy requirements, versioning, human prerequisites, and CI. Aligned README distribution notes and scripts/README archive details. Verification: required grep had no matches; local links, scripts, and named settings resolve; git diff --check passed. No source or script implementation changes.

## Agent log

- 2026-10-05T02:31:59.019Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] docs/PACKAGING.md covers every section; every named script/file/setting exists (pass) — All paths, xcconfig settings, entitlements, script modes, CI job and verifier checks confirmed against the repo.
- [x] No DMG/notarization/Developer ID/updater mention beyond one retirement sentence (pass) — Required grep returns no matches; retirement stated as "Direct-download distribution was retired."
- [x] README.md and scripts/README.md agree (pass) — Archive path, verify-xcode-app.sh entry, and distribution notes are consistent.
- [x] No source or script changes (pass) — Commit 14a490b4 touches only README.md, docs/PACKAGING.md, scripts/README.md.
Checks run:
- grep -rniE "dmg|notariz|developer id|updater" README.md docs/PACKAGING.md scripts/README.md (no matches)
- path existence check for all referenced files/scripts/docs
- cross-check of entitlements, xcconfig settings, app-store-build.sh signing/archive logic, verify-xcode-app.sh checks, ci.yml xcode-app job
- git diff --check (clean)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUUMVR6GAA3BMFAI
Summary: Verified PACKAGING.md rewrite; all named files, settings, scripts and CI job exist and match; docs agree.
