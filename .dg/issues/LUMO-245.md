---
id: LUMO-245
title: "Spike: validate SwiftData under Swift 6 strict concurrency"
type: spike
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A throwaway @Model + @ModelActor build/test compiles and runs under Swift 6 strict concurrency with zero opt-outs
      result: pass
    - criterion: ModelContainer crosses the actor boundary and ModelContext remains actor-confined
      result: pass
  checks_run:
    - swift test --filter SwiftDataConcurrencyProbeTests.testModelAndModelActorAreSwift6ConcurrencySafe -- 1 passed
    - swift test --filter PackageSettingsTests -- 3 passed
    - swift test -- 913 executed, 41 skipped, 0 failures
    - git diff --check -- passed
    - probe source contains no @unchecked Sendable, nonisolated(unsafe), or @preconcurrency
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-06T23:25:45.522Z
  session: 01MTQFSCUTJ63E2JZ7
labels:
  - persistence
  - spike
created: 2026-09-06T04:06:24.051Z
updated: 2026-09-07T04:02:48.231Z
depends_on:
  - LUMO-244
order: iv3qs7zb
board: product
---

## Objective

Gate for the rest of the "SwiftData-backed edit persistence" epic. Validate that SwiftData holds up
cleanly under this repo's Swift 6 strict-concurrency bar before any real rewrite work starts.

## Context

See the epic body for full background and shared constraints. This ticket exists because the whole
epic is only worth doing if SwiftData's `@Model`/`@ModelActor` pattern compiles under
`.swiftLanguageMode(.v6)` with zero opt-outs (no `@unchecked Sendable`, `nonisolated(unsafe)`,
`@preconcurrency`) — exactly the bar `PackageSettingsTests` enforces everywhere else in `LumoKit`.

## Work

- Write a throwaway `@Model` class and a throwaway `@ModelActor` actor wrapping it.
- Confirm it compiles under Swift 6 language mode with zero opt-outs.
- Confirm `ModelContainer` is usable as `Sendable` across the actor boundary.
- Confirm `ModelContext` stays actor-confined via `@ModelActor` (no leaking a non-Sendable context
  out of the actor).

## Acceptance criteria

- [ ] A passing throwaway build/test proves the `@Model` + `@ModelActor` pattern compiles cleanly
      under Swift 6 strict concurrency with zero opt-outs.
- [ ] If the pattern does *not* hold cleanly, stop and report back with the specific diagnostic
      before any other child ticket in this epic proceeds — do not paper over it with an opt-out.

## Depends on

None (first ticket in the epic).

## Agent log

- 2026-09-06T23:25:45.523Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A throwaway @Model + @ModelActor build/test compiles and runs under Swift 6 strict concurrency with zero opt-outs (pass)
- [x] ModelContainer crosses the actor boundary and ModelContext remains actor-confined (pass)
Checks run:
- swift test --filter SwiftDataConcurrencyProbeTests.testModelAndModelActorAreSwift6ConcurrencySafe -- 1 passed
- swift test --filter PackageSettingsTests -- 3 passed
- swift test -- 913 executed, 41 skipped, 0 failures
- git diff --check -- passed
- probe source contains no @unchecked Sendable, nonisolated(unsafe), or @preconcurrency
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTQFSCUTJ63E2JZ7
Summary: Swift 6 SwiftData concurrency probe passes. Added an isolated @Model and @ModelActor test that passes ModelContainer through a detached @Sendable task, performs actor-confined ModelContext insert/save/fetch, and returns only a Sendable Int. No concurrency opt-outs were added. Verification: focused probe passed; PackageSettingsTests passed; full swift test passed (913 executed, 41 skipped, 0 failures).
