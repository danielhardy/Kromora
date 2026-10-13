---
id: KRMA-983
title: "KRMA-944a: Late-bind EditDocumentStore and PortableLibrarySession so AppViewModel.init needs no open package"
type: task
status: ready
priority: high
human_review_required: false
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
updated: 2026-10-13T22:12:25.361Z
blockers: []
order: zr
board: product
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
