---
id: KRMA-533
title: Harden the direct-distribution updater and verify App Sandbox behavior
type: task
status: verification
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - security
  - distribution
created: 2026-09-21T20:33:13.027Z
updated: 2026-09-23T02:01:38.572Z
depends_on:
  - KRMA-546
estimate: 3
order: w
board: product
---

## Objective

Close the updater's verify-then-copy gap and establish a supported behavior for signed App Sandbox direct-distribution builds.

## Context and evidence

UpdateInstaller is careful about HTTPS, Developer ID anchoring, Team ID/bundle ID pinning, nested validation, and positional shell arguments. The staged app is verified while mounted, then copied and swapped without re-verifying the staged copy. Kromora.entitlements enables App Sandbox for every build, but hdiutil through Process and replacing an app in /Applications may not work from a sandboxed direct build. hdiutil attach -noverify is acceptable only if the code-signature rationale is documented.

## Scope

- Re-run verify(newApp) against the staged copy after copy and before atomic rename.
- Add a test proving a staged copy must pass verification.
- Perform a manual check using a signed sandboxed release build for attach, validation, staging, and in-place install.
- If in-place install cannot work, gate canInstallInPlace and fall back to opening the release page; alternatively define a separate unsandboxed direct-distribution entitlement policy if that is the approved product decision.
- Document the -noverify choice and sandbox outcome in docs/PACKAGING.md.
- Keep release notes rendered as plain text; do not broaden remote content rendering.

## Acceptance criteria

- [ ] A regression test covers verification of the staged copy and failure before rename.
- [ ] Manual signed sandboxed release-build outcome is recorded with reproducible steps.
- [ ] Unsupported in-place install is not advertised; fallback behavior is user-safe and actionable.
- [ ] Updater security invariants remain intact and relevant tests pass.

## Dependencies and coordination

Independent. This is a distribution/security ticket; keep it separate from general packaging or documentation cleanup.

## Likely files and checks

Sources/KromoraKit/Presentation/UpdateInstaller.swift, Kromora.entitlements, updater tests, docs/PACKAGING.md, and signed release-build validation scripts.
