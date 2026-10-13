---
id: KRMA-943
title: Replace Host.current().localizedName with SCDynamicStoreCopyComputerName
type: task
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A tiny DeviceName enum in Models uses SCDynamicStoreCopyComputerName, falls back to literal This Mac, and Sources contains no Host.current references.
      result: pass
      notes: Reviewed implementation and fallback; source scan is empty after a localized documentation wording fix.
    - criterion: The lease default argument uses DeviceName.current() and the injected deviceName parameter remains available.
      result: pass
      notes: Confirmed default argument and passed injected name through DeviceNameTests.
    - criterion: Unit tests cover a non-empty current device name and recording the injected lease name.
      result: pass
      notes: Both DeviceNameTests passed in the fast lane.
    - criterion: swift build links without extra package settings.
      result: pass
      notes: swift build succeeded without Package.swift changes.
    - criterion: Build remains warning-free and Swift 6 stays clean without listed escape hatches or availability branches.
      result: pass
      notes: Build produced no diagnostics; inspected changed implementation for the prohibited constructs.
    - criterion: scripts/ci-tests.sh fast exits 0.
      result: pass
      notes: All 1,818 required fast tests completed with exit 0.
  checks_run:
    - swift build — pass (exit 0; no diagnostics).
    - scripts/ci-tests.sh fast — pass (exit 0; 1,818 required tests).
    - Host.current source scan — pass (no matches in Sources).
    - git diff --check HEAD^ HEAD — pass (exit 0).
  findings:
    - The new explanatory comment contained the literal Host.current token, causing the explicitly required grep scan to fail despite removal of the call. This was a localized acceptance-check issue.
  fixes:
    - Reworded the DeviceName.swift comment to describe blocking hostname APIs without containing the forbidden Host.current token.
  verification_commits:
    - 2e2c32a5d170414e9e1fb4b801607d53c9d8755b
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T19:49:30.285Z
  session: 01MV73DEG58I5SL3EV
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - startup
  - performance
created: 2026-10-13T14:47:52.929Z
updated: 2026-10-13T19:49:30.289Z
parent: KRMA-922
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T19:46:23.803Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 2e2c32a5d170414e9e1fb4b801607d53c9d8755b
---

## Objective

Stop `Host.current().localizedName` (known to block for seconds on some networks) from running during
launch when the writer lease records the device name.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding S4 (second bullet). `Sources/KromoraKit/Models/PortablePackageTransaction.swift`
~L222: the lease initializer default argument is `deviceName: String = Host.current().localizedName ??
ProcessInfo.processInfo.hostName`. `Host.current()` can trigger reverse DNS. `SystemConfiguration`'s
`SCDynamicStoreCopyComputerName(nil, nil)` returns the user-visible computer name from a local
store without network lookups. (SystemConfiguration is an Apple framework; zero third-party deps
holds. SwiftPM links it automatically via `import SystemConfiguration`.)

## Acceptance criteria

- [ ] A tiny `enum DeviceName { static func current() -> String }` (own file in `Models/`) uses
      `SCDynamicStoreCopyComputerName`, falling back to `ProcessInfo.processInfo.hostName`
      (`hostName` can also block; instead fall back to the literal `"This Mac"` and say so in a
      comment). No `Host.current()` remains: `grep -rn "Host.current" Sources` is empty.
- [ ] The lease default argument uses it; the injected `deviceName:` parameter still exists for tests.
- [ ] Unit test: `DeviceName.current()` returns a non-empty string; the lease records the injected name.
- [ ] `swift build` links without extra package settings (no `Package.swift` change if possible; if a
      linker setting is required, add it and mention it).
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).


### Comment — claude @ 2026-10-13T19:46:20.650Z

Added DeviceName.current() (SCDynamicStoreCopyComputerName, fallback literal 'This Mac'); lease default uses it, injected deviceName kept. No Package.swift change; build warning-free; DeviceNameTests pass. scripts/ci-tests.sh fast exited 1 on two runs with different unrelated flakes (StoredEditAdoptionTests.testShutdownWaits..., DeriveCoordinatorTests.testStaleSuccessAfterDismissDoesNotPublish); each passes when re-run alone. Not touched here.

## Agent log

- 2026-10-13T19:49:30.285Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A tiny DeviceName enum in Models uses SCDynamicStoreCopyComputerName, falls back to literal This Mac, and Sources contains no Host.current references. (pass) — Reviewed implementation and fallback; source scan is empty after a localized documentation wording fix.
- [x] The lease default argument uses DeviceName.current() and the injected deviceName parameter remains available. (pass) — Confirmed default argument and passed injected name through DeviceNameTests.
- [x] Unit tests cover a non-empty current device name and recording the injected lease name. (pass) — Both DeviceNameTests passed in the fast lane.
- [x] swift build links without extra package settings. (pass) — swift build succeeded without Package.swift changes.
- [x] Build remains warning-free and Swift 6 stays clean without listed escape hatches or availability branches. (pass) — Build produced no diagnostics; inspected changed implementation for the prohibited constructs.
- [x] scripts/ci-tests.sh fast exits 0. (pass) — All 1,818 required fast tests completed with exit 0.
Checks run:
- swift build — pass (exit 0; no diagnostics).
- scripts/ci-tests.sh fast — pass (exit 0; 1,818 required tests).
- Host.current source scan — pass (no matches in Sources).
- git diff --check HEAD^ HEAD — pass (exit 0).
Findings:
- The new explanatory comment contained the literal Host.current token, causing the explicitly required grep scan to fail despite removal of the call. This was a localized acceptance-check issue.
Fixes:
- Reworded the DeviceName.swift comment to describe blocking hostname APIs without containing the forbidden Host.current token.
Verification commits:
- 2e2c32a5d170414e9e1fb4b801607d53c9d8755b
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV73DEG58I5SL3EV
Summary: Verified the SCDynamicStore device-name change; fixed the source-scan comment, build and fast tests pass.
