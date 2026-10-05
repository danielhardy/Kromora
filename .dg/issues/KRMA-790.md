---
id: KRMA-790
title: Trim entitlements to the capabilities Kromora actually uses
type: task
status: done
priority: high
verification_agent: claude
human_review_required: false
verification_model: sonnet
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Entitlements file has no network entitlement and matches the audit final set, each key justified
      result: pass
      notes: Five keys match audit section 4; Pictures and removable-media have path comments; others justified in the audit.
    - criterion: build-macos-app.sh, verify-app-signature.sh, verify-library-package-metadata.sh pass
      result: pass
    - criterion: verify-app-signature.sh fails if an extra com.apple.security.* entitlement is added
      result: pass
      notes: Re-signed a copy of the built app with network.client added; script exited 1 reporting it as unexpected. Source tree untouched.
    - criterion: docs/PACKAGING.md lists the same entitlements as the file
      result: pass
  checks_run:
    - scripts/build-macos-app.sh
    - scripts/verify-app-signature.sh .build/Kromora.app
    - scripts/verify-library-package-metadata.sh
    - negative check with extra network.client entitlement on a copied app
    - grep for stale network.client references outside the audit
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-04T17:45:00.653Z
  session: 01MUU40GA4LYTZY67L
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - entitlements
  - sandbox
created: 2026-10-03T19:24:19.332Z
updated: 2026-10-04T17:45:00.657Z
depends_on:
  - KRMA-785
  - KRMA-787
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-04T17:43:17.314Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Make `Kromora.entitlements` the minimal capability contract for the sandboxed app, using the sandbox audit's recommendation table.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstream 4). `Sources/Kromora/Kromora.entitlements` currently sets app-sandbox, user-selected read-write, removable-media read-only, app-scope bookmarks, pictures read-write, and network client (the last only existed for the GitHub updater, now deleted). The audit conclusions are in `docs/APP_STORE_SANDBOX_AUDIT.md` section 4 "Recommendations". Three scripts assert the entitlement set: `scripts/verify-app-signature.sh` (an `expected` dict), `scripts/verify-library-package-metadata.sh` (requires the Pictures entitlement to be true), and `docs/PACKAGING.md`. Apple reviewers reject apps that request entitlements they do not use.

## Scope

- Remove `com.apple.security.network.client` and its XML comment.
- For `com.apple.security.assets.pictures.read-write` and `com.apple.security.files.removable-media.read-only`: follow the audit's recommendation. If the audit says a code path really needs one, keep it and add an XML comment naming the code path; if not, remove it. If the audit is ambiguous on either, keep it and file a backlog issue to settle it with a sandboxed run.
- Update `scripts/verify-app-signature.sh` and `scripts/verify-library-package-metadata.sh` so they assert exactly the final set (and that no unexpected `com.apple.security.*` key is present) and `docs/PACKAGING.md` so its entitlement description matches.

## Acceptance criteria

- [ ] The entitlements file contains no network entitlement and matches the audit's final set, each key justified by a comment or the audit document.
- [ ] `scripts/build-macos-app.sh`, `scripts/verify-app-signature.sh`, and `scripts/verify-library-package-metadata.sh` all pass.
- [ ] `verify-app-signature.sh` fails if an extra `com.apple.security.*` entitlement is added (check once by temporarily adding one, then revert).
- [ ] `docs/PACKAGING.md` lists the same entitlements as the file.

## Verification

- Run the three scripts in order and diff the entitlement keys against the audit's table.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.


### Comment — codex @ 2026-10-04T17:43:14.272Z

Implemented and committed as 3398378f (KRMA-790: trim sandbox entitlements). Removed the network client entitlement, retained the five capabilities recommended by the audit with path comments for Pictures and removable-media access, and updated the exact-set entitlement checks plus Packaging guidance. Checks passed: scripts/build-macos-app.sh; scripts/verify-app-signature.sh; scripts/verify-library-package-metadata.sh; negative verifier check rejected an added network entitlement; entitlement keys matched the audit table; git diff --check.

## Agent log

- 2026-10-04T17:45:00.654Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Entitlements file has no network entitlement and matches the audit final set, each key justified (pass) — Five keys match audit section 4; Pictures and removable-media have path comments; others justified in the audit.
- [x] build-macos-app.sh, verify-app-signature.sh, verify-library-package-metadata.sh pass (pass)
- [x] verify-app-signature.sh fails if an extra com.apple.security.* entitlement is added (pass) — Re-signed a copy of the built app with network.client added; script exited 1 reporting it as unexpected. Source tree untouched.
- [x] docs/PACKAGING.md lists the same entitlements as the file (pass)
Checks run:
- scripts/build-macos-app.sh
- scripts/verify-app-signature.sh .build/Kromora.app
- scripts/verify-library-package-metadata.sh
- negative check with extra network.client entitlement on a copied app
- grep for stale network.client references outside the audit
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUU40GA4LYTZY67L
Summary: Entitlements trimmed to the audit's five-key set; verifiers assert the exact set; docs match.
