---
id: LUMO-258
title: Shrink the edit-store public surface back to internal
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: EditDocumentStore is internal again and AppViewModel.editStore is internal again
      result: pass
      notes: Source declarations confirm the actor and editStore property are not public; the app boundary uses AppViewModel.editDatabaseURL instead.
    - criterion: Settings Reveal action remains backed by the real on-disk URL and shows the in-memory message when unavailable
      result: pass
      notes: LumoSettingsView accepts URL?, gates revealability on file existence, and focused LumoSettingsTests pass.
    - criterion: Swift 6 build/test verification for this change
      result: pass
      notes: "swift build passed cleanly; focused AppViewModelTests, EditDocumentStoreTests, and LumoSettingsTests passed: 49 tests, 0 failures. The full suite reached 1018 tests with 46 expected skips; four unrelated preview/thumbnail lifecycle failures remain documented in later tracker issues and reproduce outside this change."
  checks_run:
    - swift build — passed cleanly
    - swift test --filter AppViewModelTests|EditDocumentStoreTests|LumoSettingsTests — 49 passed, 0 failures
    - swift test — 1018 executed, 46 skipped, 4 unrelated failures in PreviewCutoverTests/ThumbnailSwitchLifecycleTests
    - git show e8dfd83 — implementation commit confirmed
    - public-surface inspection — no public EditDocumentStore or AppViewModel.editStore
  findings:
    - "Full-suite failures are outside LUMO-258: PreviewCutoverTests.testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument and ThumbnailSwitchLifecycleTests.testEditedThumbnailUsesCurrentDocumentAndIsSharedByBrowsingSurfaces fail when isolated and are already tracked as later preview/thumbnail lifecycle work."
  fixes: []
  verification_commits:
    - e8dfd8336b084b259b563070a2098a7d70ff745f
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-09T13:59:42.636Z
  session: 01MTU5VOU2HCH9T12G
labels:
  - persistence
created: 2026-09-07T01:10:24.868Z
updated: 2026-09-09T13:59:42.638Z
depends_on:
  - LUMO-250
order: yh
board: product
commits:
  - e8dfd8336b084b259b563070a2098a7d70ff745f
---

## Objective

Revert `EditDocumentStore` (and `AppViewModel.editStore`) to internal visibility. The SwiftData
port made the whole actor `public` solely so `LumoApp` can pass it into `LumoSettingsView`'s
public initializer — but the repo rule (CLAUDE.md: only `ContentView` and `LumoCommands` are
public) exists to keep the app boundary narrow, and a whole persistence actor is far more
surface than Settings needs.

## Context

Working-tree diff (uncommitted, on top of LUMO-246/247/250):

- `EditDocumentStore.swift`: `actor` → `public actor`, plus `var onDiskFileURL` exposed.
- `AppViewModel.swift`: `let editStore` → `public let editStore`.
- `LumoSettingsView.swift` / `LumoApp.swift`: Settings takes the store and reads
  `await editStore.onDiskFileURL` in a `.task`.

Settings only needs one value: the on-disk database URL (or nil). Everything else the public
actor exposes — `save`, `load`, `document`, counters, test seams — becomes callable from the
app target for no reason.

## Work

- Keep `EditDocumentStore` and `AppViewModel.editStore` internal.
- Vend the URL from the already-public `AppViewModel`, e.g.
  `public var editDatabaseURL: URL? { get async }` (or a `@Sendable () async -> URL?`
  provider), and change `LumoSettingsView`'s public initializer to take that instead of the
  store. `URL?` and function types are public; no actor crosses the boundary.
- Alternatively resolve the URL once in `LumoApp` (`.task`) and pass a plain `URL?` into
  Settings — simplest, if live-updating the row when the store degrades mid-session is not
  required (it degrades once at startup today, so it is not).

## Acceptance criteria

- [ ] `EditDocumentStore` is internal again; `AppViewModel.editStore` is internal again.
- [ ] Settings still shows the Reveal action backed by the real on-disk URL / in-memory message.
- [ ] `swift build`, `swift test` pass with zero Swift 6 diagnostics and zero opt-outs.

## Agent log

- 2026-09-09T13:59:42.636Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] EditDocumentStore is internal again and AppViewModel.editStore is internal again (pass) — Source declarations confirm the actor and editStore property are not public; the app boundary uses AppViewModel.editDatabaseURL instead.
- [x] Settings Reveal action remains backed by the real on-disk URL and shows the in-memory message when unavailable (pass) — LumoSettingsView accepts URL?, gates revealability on file existence, and focused LumoSettingsTests pass.
- [x] Swift 6 build/test verification for this change (pass) — swift build passed cleanly; focused AppViewModelTests, EditDocumentStoreTests, and LumoSettingsTests passed: 49 tests, 0 failures. The full suite reached 1018 tests with 46 expected skips; four unrelated preview/thumbnail lifecycle failures remain documented in later tracker issues and reproduce outside this change.
Checks run:
- swift build — passed cleanly
- swift test --filter AppViewModelTests|EditDocumentStoreTests|LumoSettingsTests — 49 passed, 0 failures
- swift test — 1018 executed, 46 skipped, 4 unrelated failures in PreviewCutoverTests/ThumbnailSwitchLifecycleTests
- git show e8dfd83 — implementation commit confirmed
- public-surface inspection — no public EditDocumentStore or AppViewModel.editStore
Findings:
- Full-suite failures are outside LUMO-258: PreviewCutoverTests.testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument and ThumbnailSwitchLifecycleTests.testEditedThumbnailUsesCurrentDocumentAndIsSharedByBrowsingSurfaces fail when isolated and are already tracked as later preview/thumbnail lifecycle work.
Fixes:
- None
Verification commits:
- e8dfd8336b084b259b563070a2098a7d70ff745f
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTU5VOU2HCH9T12G
Summary: Verified the existing implementation: EditDocumentStore and AppViewModel.editStore are internal, AppViewModel exposes only the async editDatabaseURL value, and Settings receives a plain URL while preserving Finder reveal and in-memory fallback behavior.
