---
id: LUMO-245
title: "Spike: validate SwiftData under Swift 6 strict concurrency"
type: spike
status: backlog
priority: medium
labels:
  - persistence
  - spike
created: 2026-09-06T04:06:24.051Z
updated: 2026-09-06T04:06:34.958Z
depends_on:
  - LUMO-244
order: zzzzx
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
