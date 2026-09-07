---
id: LUMO-247
title: Update EditDocumentStore callers (AppViewModel, ExportCoordinator)
type: task
status: done
priority: medium
labels:
  - persistence
created: 2026-09-06T04:06:25.910Z
updated: 2026-09-06T23:42:21.756Z
depends_on:
  - LUMO-244
  - LUMO-246
order: a0
board: product
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: AppViewModel constructs the SwiftData-backed store and falls back to an in-memory store on failure, matching today's never-crash/degrade-to-neutral-edits behavior
      result: pass
      notes: AppViewModel.swift:687-711 now routes all three construction sites (convenience inits and the designated init's default parameter) through EditDocumentStore.makeDefaultStore(), which try/catches makePersistentStore(fileURL:) and falls back to an isolated in-memory container with .writeFailure status, matching the pre-existing init(fileURL:) fallback policy. Covered by EditDocumentStoreTests and 24 passing AppViewModelTests.
    - criterion: ExportCoordinator compiles against the new store type with no behavioral change
      result: pass
      notes: ExportCoordinator only holds an injected `EditDocumentStore?` and calls .load(for:) — it never constructs the store, so no source change was needed there. Confirmed by reading ExportCoordinator.swift:68-83,629-630 and a clean build; all 18 ExportCoordinatorTests pass unchanged.
    - criterion: Zero Swift 6 concurrency diagnostics, zero opt-outs
      result: pass
      notes: swift build and swift build -c release both clean; PackageSettingsTests (Swift 6 mode, tools version, no escape hatches) pass.
  checks_run:
    - swift build
    - swift build -c release
    - swift test --filter 'EditDocumentStoreTests|ExportCoordinatorTests|AppViewModelTests|SwiftDataConcurrencyProbeTests|PackageSettingsTests' (52 tests, 0 failures)
    - dg validate (OK; only pre-existing unrelated pickup-model warning)
    - git status --porcelain (no changes under this issue's files; unrelated pre-existing uncommitted work in PhotoAnalysis/masking files left untouched)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-06T23:42:21.752Z
  session: 01MTQGA368FWM4D0L6
---

## Objective

Update `EditDocumentStore` callers for the new SwiftData-backed initializer.

## Context

See the epic body for shared constraints. Child 2 rewrites `EditDocumentStore` as a `@ModelActor`
with a throwing initializer; this ticket is the mechanical fan-out to callers.

## Work

- `AppViewModel.swift` (lines ~627/633/638/652) — replace `EditDocumentStore(fileURL:)`
  construction with the new (throwing) initializer, using the same fallback-to-in-memory policy on
  failure rather than a fatal error.
- `ExportCoordinator.swift` (~68/74/83/629) — mechanical constructor/type adjustments only, no
  behavioral change.

## Acceptance criteria

- [ ] `AppViewModel` constructs the SwiftData-backed store and falls back to an in-memory store on
      failure, matching today's "never crash, degrade to neutral edits" behavior.
- [ ] `ExportCoordinator` compiles against the new store type with no behavioral change.
- [ ] Zero Swift 6 concurrency diagnostics, zero opt-outs.

## Depends on

Child 2.


### Comment — codex @ 2026-09-06T23:35:55.035Z

Implemented in ea1863e. Added explicit EditDocumentStore persistent/default factories; AppViewModel now routes all app-owned construction through the default factory, which catches SwiftData container failures, creates an isolated in-memory store, and preserves actionable writeFailure status. ExportCoordinator remains actor-typed and behaviorally unchanged. Verification: swift build; swift build -c release; focused persistence/export/SwiftData concurrency/PackageSettings lane (39 passed); git diff --check; dg validate (known pickup-model warning only).

## Agent log

- 2026-09-06T23:42:21.754Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] AppViewModel constructs the SwiftData-backed store and falls back to an in-memory store on failure, matching today's never-crash/degrade-to-neutral-edits behavior (pass) — AppViewModel.swift:687-711 now routes all three construction sites (convenience inits and the designated init's default parameter) through EditDocumentStore.makeDefaultStore(), which try/catches makePersistentStore(fileURL:) and falls back to an isolated in-memory container with .writeFailure status, matching the pre-existing init(fileURL:) fallback policy. Covered by EditDocumentStoreTests and 24 passing AppViewModelTests.
- [x] ExportCoordinator compiles against the new store type with no behavioral change (pass) — ExportCoordinator only holds an injected `EditDocumentStore?` and calls .load(for:) — it never constructs the store, so no source change was needed there. Confirmed by reading ExportCoordinator.swift:68-83,629-630 and a clean build; all 18 ExportCoordinatorTests pass unchanged.
- [x] Zero Swift 6 concurrency diagnostics, zero opt-outs (pass) — swift build and swift build -c release both clean; PackageSettingsTests (Swift 6 mode, tools version, no escape hatches) pass.
Checks run:
- swift build
- swift build -c release
- swift test --filter 'EditDocumentStoreTests|ExportCoordinatorTests|AppViewModelTests|SwiftDataConcurrencyProbeTests|PackageSettingsTests' (52 tests, 0 failures)
- dg validate (OK; only pre-existing unrelated pickup-model warning)
- git status --porcelain (no changes under this issue's files; unrelated pre-existing uncommitted work in PhotoAnalysis/masking files left untouched)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTQGA368FWM4D0L6
Summary: Independent verification: build/tests/dg validate all clean; AppViewModel and ExportCoordinator acceptance criteria confirmed met, no behavioral regressions.
