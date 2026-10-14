---
id: KRMA-983
title: "KRMA-944a: Late-bind EditDocumentStore and PortableLibrarySession so AppViewModel.init needs no open package"
type: task
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: AppViewModel.init supports deferred startup without opening a package or acquiring a lease, and the unbound edit store reports opening rather than packageFailure.
      result: pass
      notes: LateBoundLibraryTests covers deferred construction, no package creation, opening status, flush, and shutdown.
    - criterion: Session-dependent wiring is centralized in the bind path.
      result: pass
      notes: bindPortableLibrary owns session setup and index callbacks; init-time reads are limited to dynamic callbacks and the shared eager bind path.
    - criterion: EditDocumentStore binding is actor-isolated and once-only; unbound read and write behavior fails closed.
      result: pass
      notes: Tests cover first and rejected second bind, construction already bound, unbound read and write, and non-actionable status.
    - criterion: Existing initializer and fixture call sites remain compatible; touched test-file count is recorded.
      result: pass
      notes: "Existing call sites compile unchanged. Issue implementation touched two test paths: Fixtures.swift and new LateBoundLibraryTests.swift; verification extended LateBoundLibraryTests.swift."
    - criterion: Eager package binding preserves behavior and the AppViewModel line ceiling is respected.
      result: pass
      notes: Fast and serial suites pass; AppViewModel.swift is 5106 lines, below the 5120 ceiling.
    - criterion: Build is warning-free and Swift concurrency escape hatches or availability branches are absent from changed implementation files.
      result: pass
      notes: "swift build completed with no diagnostics; structural search found no @unchecked Sendable, nonisolated(unsafe), @preconcurrency, or #available."
    - criterion: Required fast and serial test lanes pass.
      result: pass
      notes: fast passed 1874 tests; serial passed 543 tests.
  checks_run:
    - swift build (exit 0; no warnings)
    - scripts/ci-tests.sh fast (1874 tests; exit 0)
    - scripts/ci-tests.sh serial (543 tests; exit 0)
    - git diff --check HEAD^ HEAD (exit 0)
    - Structural search for prohibited concurrency opt-outs and availability branches (no matches)
  findings:
    - openLibrary ignored a false result from EditDocumentStore.bind, which could expose an opened session while the injected store remained bound elsewhere.
  fixes:
    - "openLibrary now rejects failed binding, closes the newly opened session to release its lease, and reports the failure. Regression coverage verifies the lease can be reacquired. Verification commit: 94b2e895."
  verification_commits:
    - 94b2e895
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T00:25:55.655Z
  session: 01MV7D26H0CP2JVWGE
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - startup
  - package
  - needs-decomposition
created: 2026-10-13T20:38:44.684Z
updated: 2026-10-14T00:25:55.659Z
blockers: []
order: t
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T00:02:49.934Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 94b2e895
---

## Objective

Make `AppViewModel.init` construct fully without an open package: the edit store, the library session and the lease-dependent wiring become late-bound, so a later ticket (KRMA-984) can open the package asynchronously. **No behavior change in this ticket**: after it, the app still opens the package at the same moment, just through the new late-binding seam. It is a refactor that must land green on its own.

## Context

Parent: KRMA-944 (read it and its decomposition comment). Review finding S4: `.context/2026-10-13-release-readiness-review.md`. Also read KRMA-557 (index load already off-main), `docs/APP_ARCHITECTURE.md`, `docs/STORAGE_POLICY.md`.

**Starting point (verified 2026-10-13).** `AppViewModel.init` (`Sources/KromoraKit/ViewModels/AppViewModel.swift` L1029-~1500) opens the package synchronously inside a `do/catch` (L1077-1116) via `openPortableLibrarySession` (L1646; it also handles dead-writer and expired-lease recovery) and then threads the result into everything:
- `let editStore: EditDocumentStore` (L759) is an **actor** whose `packageRoot`/`packageLease` are `private let` (`Models/EditDocumentStore.swift` L162-163). It is passed by value to `EditPersistenceCoordinator`, `ExportCoordinator` (L1152), `SourceSessionCoordinator` (L1173), `LibraryDeletionCoordinator` (L1194), plus stored uses at L385, 750, 954, 1614, 4393, 4710, and the collaborator at `admissionEditStore`.
- `let portableLibrary: PortableLibrarySession?` (L784) is read at 59 sites in `AppViewModel.swift` and 30 more across other files (grep `portableLibrary` in `Sources`). `LibraryDeletionCoordinator` receives it by value (L1196); `ApplicationShellCoordinator` receives `packageLease: portableLibrary?.lease` (L1186).
- Init-tail wiring that needs the session: the membership observer `Task` (~L1222-1229), `libraryMatcherLoader` for media workflow and Photos review (~L1262-1267), `onPresentedAspectRatioUpdates` and `onIndexLoadingStateChange` plus the "Opening library index…" status (~L1452-1480), `libraryBrowsingCoordinator.prepareLaunchHints()`, and the `recoveredPreviousWriter` notice (L1493).
- `portableLibraryOpenError` (L983) feeds `reportPortableLibraryUnavailable` for imports.
- Tests: about 438 `makeAppViewModel(`/`AppViewModel(` call sites pass `editStore:` and `portableLibrarySession:` today. These must keep compiling unchanged; that is the main constraint on the design.

## Recommended design (decide, then record in the ticket comment)

1. **Keep the same `editStore` reference for the life of the model.** Give `EditDocumentStore` an unbound state (it already has a private unbound `init()`, used by `makeInMemoryProjectionStore()`) and an actor-isolated `bind(package:lease:)` that sets `packageRoot`/`packageLease` (change them to `private var`). Eight coordinators then keep their `let` reference and need no edits. Before binding, operations fail closed with a distinct "library is opening" status, not the actionable `packageFailure` alert (otherwise a read racing the open would surface a spurious error). Check each `Status` consumer, including `editStoreStatus`.
2. **`portableLibrary` becomes `private(set) var portableLibrary: PortableLibrarySession?`**, set once by a single `bindPortableLibrary(_:)` method on `AppViewModel` that performs all the session-dependent wiring listed above in one place, in the same order as today. `LibraryDeletionCoordinator` and `ApplicationShellCoordinator` stop receiving the session/lease at construction and receive it through their own `bind(...)`; do the same for `libraryMatcherLoader`.
3. **`init` keeps its current parameters** (`editStore:`, `portableLibrarySession:`, `portablePackageURL:`, `leaseRecoveryConfirmer:`). When a session or store is injected, or when the caller asks for the existing eager behavior, init calls the new bind path synchronously, so the 438 test call sites do not change. An explicit `openLibrary(confirmer:)` entry point (unused in production until KRMA-984) performs the real open and then calls the same bind path.
4. The eager production path (`AppLaunch.makeViewModel` in `Presentation/AppLaunch.swift`) keeps behaving as today.

Alternative considered and not recommended: wrapping the store in a new indirection type. It touches every store call site for no gain over (1).

## Acceptance criteria

- [ ] `AppViewModel.init` can run with no package URL opened: a new test constructs a model through the unbound path and asserts `portableLibrary == nil`, that no lease was acquired (nothing written under a temp package URL) and that `editStore` reports the "opening" status rather than `packageFailure`.
- [ ] A single `bindPortableLibrary` (name may differ) holds all session-dependent wiring; `grep -n "openedPortableLibrary\|portableLibrary?\." AppViewModel.swift` shows no remaining init-time session wiring outside it.
- [ ] `EditDocumentStore.bind(package:lease:)` is actor-isolated, may be called once, and a second call is rejected (assert in a test). The unbound-store behavior for read, write, flush and shutdown is covered by tests.
- [ ] Existing call sites compile unchanged (`makeAppViewModel` and direct `AppViewModel(...)` initializers still accept `editStore:` and `portableLibrarySession:`); no test needs more than mechanical edits, and the count of touched test files is stated in the review comment.
- [ ] Behavior is identical when the package is bound eagerly: the whole fast and serial lanes pass without new expectations.
- [ ] `AppViewModel.swift` is not longer than before (ceiling 5,120, 5,101 on 2026-10-13); move wiring into a coordinator if it would grow.
- [ ] `swift build` is warning-free; no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, or `#available`. `bind` mutates actor-isolated state only.
- [ ] `scripts/ci-tests.sh fast` and `scripts/ci-tests.sh serial` pass (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails in fast, re-run it alone and note it).

## Verification

```
swift build
scripts/ci-tests.sh fast
scripts/ci-tests.sh serial
```

## Risks and notes

- **Working-tree conflict.** The tree has uncommitted changes in `Presentation/` (`AppLaunch.swift`, `SheetPresenting.swift`, `KromoraAppDelegate.swift`, `KromoraScene.swift`, `TerminationGuard.swift`, `AppKitFileDialogAdapter.swift`) and `AppViewModel.swift` itself (KRMA-986 work). Commit or land those first; do not build on top of or revert them.
- Do not change package formats or lease semantics.
- Ordering of the init-tail wiring matters (callbacks before `prepareLaunchHints`, observers before index load). Preserve it exactly; this ticket moves code, it must not reorder it.
- If sequencing proves larger than described, stop, record what you found as child tickets, and do not land a half-migration.

### Comment — claude @ 2026-10-14T00:02:46.411Z

Implemented per the recommended design. EditDocumentStore: makeUnboundStore(), once-only actor-isolated bind(package:lease:) (returns false on a second call or a store built bound), new non-actionable Status.opening; failed-open projection store still reports packageFailure. AppViewModel: portableLibrary is now private(set) var, new init flag defersLibraryOpen (default false, so all existing init parameters and call sites are unchanged), single bindPortableLibrary (shared by eager init and openLibrary(confirmer:), same order as before; index-state handler lives in AppViewModel+Library.swift). LibraryBrowsing/Import/Deletion coordinators and ApplicationShell gained bind(...) instead of taking the session at construction. Test churn: 1 existing file touched (Fixtures.swift: one defaulted makeAppViewModel parameter), 1 new file (LateBoundLibraryTests, 6 tests). AppViewModel.swift 5101 lines (unchanged). swift build warning-free; scripts/ci-tests.sh fast and serial both exit 0. Not exercised: openLibrary is unused in production until KRMA-984.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-14T00:25:55.655Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] AppViewModel.init supports deferred startup without opening a package or acquiring a lease, and the unbound edit store reports opening rather than packageFailure. (pass) — LateBoundLibraryTests covers deferred construction, no package creation, opening status, flush, and shutdown.
- [x] Session-dependent wiring is centralized in the bind path. (pass) — bindPortableLibrary owns session setup and index callbacks; init-time reads are limited to dynamic callbacks and the shared eager bind path.
- [x] EditDocumentStore binding is actor-isolated and once-only; unbound read and write behavior fails closed. (pass) — Tests cover first and rejected second bind, construction already bound, unbound read and write, and non-actionable status.
- [x] Existing initializer and fixture call sites remain compatible; touched test-file count is recorded. (pass) — Existing call sites compile unchanged. Issue implementation touched two test paths: Fixtures.swift and new LateBoundLibraryTests.swift; verification extended LateBoundLibraryTests.swift.
- [x] Eager package binding preserves behavior and the AppViewModel line ceiling is respected. (pass) — Fast and serial suites pass; AppViewModel.swift is 5106 lines, below the 5120 ceiling.
- [x] Build is warning-free and Swift concurrency escape hatches or availability branches are absent from changed implementation files. (pass) — swift build completed with no diagnostics; structural search found no @unchecked Sendable, nonisolated(unsafe), @preconcurrency, or #available.
- [x] Required fast and serial test lanes pass. (pass) — fast passed 1874 tests; serial passed 543 tests.
Checks run:
- swift build (exit 0; no warnings)
- scripts/ci-tests.sh fast (1874 tests; exit 0)
- scripts/ci-tests.sh serial (543 tests; exit 0)
- git diff --check HEAD^ HEAD (exit 0)
- Structural search for prohibited concurrency opt-outs and availability branches (no matches)
Findings:
- openLibrary ignored a false result from EditDocumentStore.bind, which could expose an opened session while the injected store remained bound elsewhere.
Fixes:
- openLibrary now rejects failed binding, closes the newly opened session to release its lease, and reports the failure. Regression coverage verifies the lease can be reacquired. Verification commit: 94b2e895.
Verification commits:
- 94b2e895
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV7D26H0CP2JVWGE
Summary: Verified deferred library binding; required checks pass, with one localized binding fix.
