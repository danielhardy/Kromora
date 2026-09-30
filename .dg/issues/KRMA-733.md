---
id: KRMA-733
title: Hydrate the last visible Library window from bounded launch hints
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: LaunchHints bounded, versioned, atomic, library-scoped; corrupt/stale ignored
      result: pass
      notes: LaunchHintsTests.
    - criterion: Launch stays in Library; hints never canonical UI state
      result: pass
      notes: testVisibleViewportWritesHintsWithoutRestoringSelection.
    - criterion: Hinted work reads packed frame records only
      result: pass
      notes: Only frameStore.readFrames on scheduler frame-read lane.
    - criterion: Concurrency limit <=2, cap 64, background priority; asserted in tests
      result: pass
      notes: Coordinator test asserts running reads equal maxConcurrentReads and background priority.
    - criterion: First visible-ID publication supersedes hints; obsolete completions cannot publish
      result: pass
      notes: Supersession, viewport-confirmation and source-replacement tests; repeat publications no longer re-emit.
    - criterion: Relaunch tests cover useful hints, other library, removed assets, corrupt/oversized, partial index, immediate scrolling
      result: pass
      notes: Coordinator and store tests cover these.
    - criterion: Observability metrics recorded and asserted
      result: pass
      notes: Metrics emitted once with reads/bytes/useful/superseded/timings.
    - criterion: Storage policy documents LaunchHints
      result: pass
      notes: docs/STORAGE_POLICY.md.
  checks_run:
    - swift test targeted suites (46 pass)
    - scripts/ci-tests.sh fast (1454 pass, exit 0)
    - git diff --check (clean)
    - code review of 595d806 and 986e73b
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-30T21:29:35.262Z
  session: 01MUOM91A27NK31VB6
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - performance
  - reliability
  - launch
  - library
created: 2026-09-30T13:19:20.621Z
updated: 2026-09-30T21:29:35.264Z
depends_on:
  - KRMA-732
  - KRMA-736
blockers: []
estimate: 5
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/ViewModels/ApplicationShellCoordinator.swift
    - Sources/KromoraKit/ViewModels/LibraryBrowsingCoordinator.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
    - Sources/KromoraKit/Models/PortableLibrarySession.swift
    - Sources/KromoraKit/Models/ImageCollection.swift
    - Sources/KromoraKit/Views/LibraryGridView.swift
    - Sources/KromoraKit/Models/KromoraStorage.swift
    - Sources/KromoraKit/Models/KromoraSettings.swift
  docs:
    - .context/last-known-frame-plan.md
    - docs/APP_ARCHITECTURE.md
    - docs/STORAGE_POLICY.md
    - docs/TESTING.md
  issues: []
  commands:
    - swift test --filter 'ApplicationShellCoordinatorTests|LibraryBrowsingCoordinatorTests|PortableLibrarySessionTests|LibraryGridTests'
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh identity
    - git diff --check
    - dg validate
---

## Objective

Prioritize persisted frames for the last visible Library window during startup without changing
navigation truth, delaying index publication, or allowing speculative I/O to compete with the user.

## Context

Implement Phase 5 of `.context/last-known-frame-plan.md` after KRMA-732. Kromora must continue to
launch into Library.

Create a device-local `LaunchHints` value containing schema version, package/library identity, last
active asset ID, and a bounded ordered visible-ID window. Store it atomically under Application
Support through `KromoraStorage`; it is disposable operational state, not package truth. Coalesce
writes from viewport/selection changes and flush through the existing lifecycle shutdown boundary.

Once package identity is known, begin low-concurrency packed-frame reads for hinted IDs while the
asynchronous index and Look scan proceed. Do not decode sources or render from hints. When the real
viewport publishes, cancel/deprioritize hint-only work and admit actual visible IDs. Hints from a
different library, missing assets, unsupported schema, malformed data, or implausible list sizes are
ignored.

Use the existing scheduler/package-I/O ownership. Startup hydration must not block the main actor,
the first index page, source selection, or editor work. Instrument hint validation, useful hits,
supersession, bytes/read count, and time to visible-window hydration.

## Acceptance criteria

- [ ] `LaunchHints` is bounded, versioned, atomically written, and scoped to package/library
      identity; corrupt or stale records are ignored without user-visible errors.
- [ ] Launch remains in Library and never treats the hinted selection/viewport as canonical UI
      state before the real index and viewport validate it.
- [ ] Hinted work reads packed frame records only. It performs no source decode, metadata scan,
      edit load, or render.
- [ ] Hint I/O uses a named concurrency limit no higher than the KRMA-732 visible-window limit
      (initially 2), a hard cap on hinted IDs (initially 64), and is scheduled below first-page
      index publication and current user/editor work; both limits are asserted in tests.
- [ ] The first real visible-ID publication supersedes hints; obsolete completions cannot publish
      into reused cells or change selection/scroll state.
- [ ] Relaunch tests cover same-library useful hints, different-library hints, removed assets,
      corrupt/oversized records, partial index progress, and immediate user scrolling.
- [ ] Observability records hint validation, useful hits, supersession, bytes/reads, time to
      visible-window hydration, and time to first index page, with each metric asserted present in
      tests. Pass/fail targets for hydration and the first-index-page regression check (no
      measurable regression versus a hints-disabled run) are judged in KRMA-734.
- [ ] Storage policy documents LaunchHints as device-local, disposable, and excluded from backup.

## Implementation notes

- Keep the ID window small (the last viewport plus a modest prefetch margin), with a hard decode cap.
- Use value types across tasks and preserve Swift 6 isolation.
- Do not add restoration into Edit or a new library authority.

### Comment — codex @ 2026-09-30T20:04:58.217Z

Implemented bounded, device-local LaunchHints persistence and background packed-frame hydration. Actual viewport publication supersedes hint reads; hints never restore selection or scrolling. Verified targeted suites, scripts/ci-tests.sh fast, scripts/ci-tests.sh identity, git diff --check, and dg validate.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-30T20:10:45.550Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] LaunchHints bounded, versioned, atomic, library-scoped; corrupt/stale ignored (pass) — Covered by LaunchHintsTests.
- [x] Launch stays in Library; hints never canonical UI state (pass) — Coordinator test confirms selection is not restored.
- [x] Hinted work reads packed frame records only (pass) — Code review: only frameStore.readFrames on the scheduler.
- [ ] Named concurrency limit <=2, cap 64, scheduled below index/editor work; asserted in tests (fail) — Constants are asserted, but no test exercises the coordinator admission or priority.
- [ ] First visible-ID publication supersedes hints; obsolete completions cannot publish (fail) — Implemented, but untested.
- [ ] Relaunch tests cover useful hints, other library, removed assets, corrupt/oversized, partial index, immediate scrolling (fail) — Only store-level corrupt/oversized/other-library tests exist. The hydration scenarios are missing.
- [ ] Observability metrics recorded and each asserted present in tests (fail) — Only the LaunchHydrationMetrics struct is tested. Time-to-visible-window is overwritten on every publish.
- [x] Storage policy documents LaunchHints (pass) — docs/STORAGE_POLICY.md updated.
Checks run:
- swift test targeted suites (48 pass)
- scripts/ci-tests.sh fast (pass)
- scripts/ci-tests.sh identity (pass)
- git diff --check (clean)
- dg validate (model warnings only)
Findings:
- Hydration path in LibraryBrowsingCoordinator has no direct tests
- visibleIDsPublished re-emits events and overwrites time-to-visible on every scroll
- applyStoredFrames(allowHintIdentity:) classifies against hint-derived identity
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUOJBCO8FWNV4FP7
Summary: Acceptance criteria for relaunch/hydration tests and metric assertions are unmet; tracked in KRMA-736.

- 2026-09-30T21:29:35.262Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] LaunchHints bounded, versioned, atomic, library-scoped; corrupt/stale ignored (pass) — LaunchHintsTests.
- [x] Launch stays in Library; hints never canonical UI state (pass) — testVisibleViewportWritesHintsWithoutRestoringSelection.
- [x] Hinted work reads packed frame records only (pass) — Only frameStore.readFrames on scheduler frame-read lane.
- [x] Concurrency limit <=2, cap 64, background priority; asserted in tests (pass) — Coordinator test asserts running reads equal maxConcurrentReads and background priority.
- [x] First visible-ID publication supersedes hints; obsolete completions cannot publish (pass) — Supersession, viewport-confirmation and source-replacement tests; repeat publications no longer re-emit.
- [x] Relaunch tests cover useful hints, other library, removed assets, corrupt/oversized, partial index, immediate scrolling (pass) — Coordinator and store tests cover these.
- [x] Observability metrics recorded and asserted (pass) — Metrics emitted once with reads/bytes/useful/superseded/timings.
- [x] Storage policy documents LaunchHints (pass) — docs/STORAGE_POLICY.md.
Checks run:
- swift test targeted suites (46 pass)
- scripts/ci-tests.sh fast (1454 pass, exit 0)
- git diff --check (clean)
- code review of 595d806 and 986e73b
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUOM91A27NK31VB6
Summary: Re-verified after KRMA-736: hydration tests and metrics now cover all criteria.
