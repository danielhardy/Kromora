---
id: KRMA-533
title: Harden the direct-distribution updater and verify App Sandbox behavior
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A regression test covers verification of the staged copy and failure before rename.
      result: pass
      notes: Tests/KromoraKitTests/UpdateTests.swift:testStagedCopyVerificationFailureLeavesCurrentAppUntouched (added in f1c5a96) forces the staged-copy verifier to throw and asserts the running app and its marker are untouched and no leftover staged/retired directories remain. UpdateInstaller.swift's swap(newApp:into:verifyStaged:) now re-verifies the staged copy before the atomic rename, closing the prior verify-then-copy gap.
    - criterion: Manual signed sandboxed release-build outcome is recorded with reproducible steps.
      result: pass
      notes: "docs/PACKAGING.md 'Sandboxed updater validation' section (completed this session, commit a9cb803) records a 2026-09-23 test with a real Developer ID identity/provisioning/notarization: hdiutil attach fails under App Sandbox ('Device not configured'), reproduced twice, with the isolating unsandboxed control and method described. This session cannot re-run the manual signed-build test itself (no Developer ID identity in this environment) so the recorded result is trusted as reported, but it is internally consistent with the shipped canInstallInPlace=false gate."
    - criterion: Unsupported in-place install is not advertised; fallback behavior is user-safe and actionable.
      result: pass
      notes: KromoraUpdateInstaller.canInstallInPlace is hardcoded false with a comment pointing at the documented rationale. UpdateCoordinator.installAndRelaunch falls back to openReleasePage when canInstallInPlace is false, and UpdateSheet only ever offers 'Install and Relaunch' when canInstallInPlace is true, otherwise showing 'Open Release Page' bound to the default action.
    - criterion: Updater security invariants remain intact and relevant tests pass.
      result: pass
      notes: verify() still requires anchor apple generic, matching Team ID/bundle ID, and strict nested validation; -noverify on hdiutil attach is documented as acceptable because SecStaticCode verification (not the DMG container) is the trust boundary. swift build and the fast test suite (KROMORA_DIRECT_DISTRIBUTION=1 scripts/ci-tests.sh fast, 1185/1185) pass, including UpdateTests and PackageSettingsTests (Swift 6 / zero escape-hatch gates).
  checks_run:
    - swift build
    - KROMORA_DIRECT_DISTRIBUTION=1 swift test --filter UpdateTests (6/6 pass)
    - KROMORA_DIRECT_DISTRIBUTION=1 swift test --filter PackageSettingsTests (4/4 pass)
    - KROMORA_DIRECT_DISTRIBUTION=1 scripts/ci-tests.sh fast (1185/1185 pass, exit 0)
  findings: []
  fixes:
    - Committed the already-drafted (uncommitted) UpdateInstaller.swift comment and docs/PACKAGING.md 'Sandboxed updater validation' rewrite that record the confirmed manual test outcome, splitting out unrelated bundle-identifier-rename and notarization-script hunks that were interleaved in the same working tree and belong to other in-flight tickets.
  verification_commits:
    - a9cb803598235c3a60ee11445102b63bf0c9b73e
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-23T22:43:12.465Z
  session: 01MUEOMR4R17FV55MV
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - security
  - distribution
created: 2026-09-21T20:33:13.027Z
updated: 2026-09-23T22:43:12.467Z
depends_on:
  - KRMA-546
estimate: 3
order: zv
board: product
commits:
  - a9cb803598235c3a60ee11445102b63bf0c9b73e
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

## Agent log

- 2026-09-23T22:43:12.465Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A regression test covers verification of the staged copy and failure before rename. (pass) — Tests/KromoraKitTests/UpdateTests.swift:testStagedCopyVerificationFailureLeavesCurrentAppUntouched (added in f1c5a96) forces the staged-copy verifier to throw and asserts the running app and its marker are untouched and no leftover staged/retired directories remain. UpdateInstaller.swift's swap(newApp:into:verifyStaged:) now re-verifies the staged copy before the atomic rename, closing the prior verify-then-copy gap.
- [x] Manual signed sandboxed release-build outcome is recorded with reproducible steps. (pass) — docs/PACKAGING.md 'Sandboxed updater validation' section (completed this session, commit a9cb803) records a 2026-09-23 test with a real Developer ID identity/provisioning/notarization: hdiutil attach fails under App Sandbox ('Device not configured'), reproduced twice, with the isolating unsandboxed control and method described. This session cannot re-run the manual signed-build test itself (no Developer ID identity in this environment) so the recorded result is trusted as reported, but it is internally consistent with the shipped canInstallInPlace=false gate.
- [x] Unsupported in-place install is not advertised; fallback behavior is user-safe and actionable. (pass) — KromoraUpdateInstaller.canInstallInPlace is hardcoded false with a comment pointing at the documented rationale. UpdateCoordinator.installAndRelaunch falls back to openReleasePage when canInstallInPlace is false, and UpdateSheet only ever offers 'Install and Relaunch' when canInstallInPlace is true, otherwise showing 'Open Release Page' bound to the default action.
- [x] Updater security invariants remain intact and relevant tests pass. (pass) — verify() still requires anchor apple generic, matching Team ID/bundle ID, and strict nested validation; -noverify on hdiutil attach is documented as acceptable because SecStaticCode verification (not the DMG container) is the trust boundary. swift build and the fast test suite (KROMORA_DIRECT_DISTRIBUTION=1 scripts/ci-tests.sh fast, 1185/1185) pass, including UpdateTests and PackageSettingsTests (Swift 6 / zero escape-hatch gates).
Checks run:
- swift build
- KROMORA_DIRECT_DISTRIBUTION=1 swift test --filter UpdateTests (6/6 pass)
- KROMORA_DIRECT_DISTRIBUTION=1 swift test --filter PackageSettingsTests (4/4 pass)
- KROMORA_DIRECT_DISTRIBUTION=1 scripts/ci-tests.sh fast (1185/1185 pass, exit 0)
Findings:
- None
Fixes:
- Committed the already-drafted (uncommitted) UpdateInstaller.swift comment and docs/PACKAGING.md 'Sandboxed updater validation' rewrite that record the confirmed manual test outcome, splitting out unrelated bundle-identifier-rename and notarization-script hunks that were interleaved in the same working tree and belong to other in-flight tickets.
Verification commits:
- a9cb803598235c3a60ee11445102b63bf0c9b73e
Actor: claude
Resolved model: sonnet
Pickup session: 01MUEOMR4R17FV55MV
Summary: Verified: staged-copy reverification closes the copy-then-verify gap, canInstallInPlace is permanently gated off with the sandboxed hdiutil failure documented and reproducible, fallback UI is safe, and the fast test suite (1185/1185) plus build pass.
