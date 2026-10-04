---
id: KRMA-790
title: Trim entitlements to the capabilities Kromora actually uses
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
  - entitlements
  - sandbox
created: 2026-10-03T19:24:19.332Z
updated: 2026-10-03T19:25:45.949Z
depends_on:
  - KRMA-785
  - KRMA-787
blockers: []
order: zv
board: product
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
