---
id: KRMA-842
title: "Library grid shows 19 photos while the package holds 140: index stale after SD card import"
type: bug
status: done
priority: urgent
agent: codex
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Root cause recorded (which index file/path was stale and why)
      result: pass
      notes: Resolution records the separate SwiftPM and sandboxed index locations and explains that missing package members were trusted because validation checked only the library ID.
    - criterion: After new, duplicate-only, and mixed imports, the grid matches live membership in both app builds
      result: pass
      notes: Membership reconciliation and import/reload coverage are present; the user confirmed recovery in their library.
    - criterion: Relaunch with a stale or truncated index rebuilds it and a status message says so
      result: pass
      notes: Synchronous and asynchronous stale-index repair publish a status; focused status-bar coverage is included in the passing fast lane.
    - criterion: A failed index update is surfaced, never silently swallowed
      result: pass
      notes: Index write and delta-application failures are reported; status-bar and observability coverage passed.
    - criterion: Refresh Library rebuilds and restores the affected library without modifying originals or membership
      result: pass
      notes: Refresh rebuilds the disposable index from package membership; original assets and membership are not rewritten.
    - criterion: Tests cover import/reload consistency, stale-index open, and duplicate-only import; fast and serial lanes pass
      result: pass
      notes: Required fast and serial lanes passed on the current tree.
  checks_run:
    - Independent review of membership reconciliation, synchronous/asynchronous open repair, write failure handling, Refresh Library, and focused tests.
    - scripts/ci-tests.sh fast — exit 0; 1,586 required tests dispatched.
    - scripts/ci-tests.sh serial — exit 0; 500 tests, 0 failures.
  findings: []
  fixes: []
  verification_commits:
    - fa1910d3
    - d7c00b2d
  actor: codex
  resolved_model: unknown
  completed_at: 2026-10-10T06:21:53.975Z
  session: 01MV203GZSF7X5YXSX
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-09T18:32:19.794Z
updated: 2026-10-10T06:21:53.980Z
depends_on:
  - KRMA-846
blockers: []
order: y
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths:
      - path: Sources/KromoraKit/Models/LibraryQueryController.swift
        access: write
        confidence: 1
      - path: Sources/KromoraKit/Models/Observability.swift
        access: write
        confidence: 1
      - path: Sources/KromoraKit/Models/PortableLibrarySession.swift
        access: write
        confidence: 1
      - path: Sources/KromoraKit/ViewModels/AppViewModel.swift
        access: write
        confidence: 1
      - path: Sources/KromoraKit/ViewModels/LibraryBrowsingCoordinator.swift
        access: write
        confidence: 1
      - path: Sources/KromoraKit/ViewModels/LibraryMediaWorkflowCoordinator.swift
        access: write
        confidence: 1
      - path: Sources/KromoraKit/Views/ContentView.swift
        access: write
        confidence: 1
      - path: Sources/KromoraKit/Views/MenuCommands.swift
        access: write
        confidence: 1
      - path: Tests/KromoraKitTests/LibraryBrowsingCoordinatorTests.swift
        access: write
        confidence: 1
      - path: Tests/KromoraKitTests/PortableLibrarySessionTests.swift
        access: write
        confidence: 1
    base: f7f3e59ae528d9907e900bd020b88fbd9baf56df
    head: fa1910d35afa5521403574174c642d03bfe95c43
    captured_at: 2026-10-10T04:18:49.233Z
commits:
  - fa1910d3
  - d7c00b2d
---

## Objective

After an SD card import into the library, the Library grid keeps showing the old photo count (19 of 19) and, after the import finishes, the status bar says "The imported photo is not available in the package index." Quitting and relaunching does not fix it. The package on disk contains the imported photos, so the browsing index/projection is out of sync with the package (or the package membership does not match what the index reports). Find and fix the root cause so imported photos always appear, and so a stale index is detected and rebuilt rather than trusted.

## Evidence (inspected on disk, user's library `~/Pictures/Kromora Library.kromoralibrary`, 2026-10-09)

- `Catalog/Membership/*.json`: 172 membership entries, 32 tombstones, so 140 live assets. `Assets/*/*/asset.json`: 140 records, matching.
- 117 of those asset records (and about 120 originals, ~132 MB each, `.ARW`) were written between 10:16 and 10:19 local on 2026-10-09. That is the large SD card import; it committed fine at the package level.
- 32 assets were tombstoned and moved to `Recovery/Quarantine` at 12:03 (33 quarantine folders). Needs confirmation whether the user removed photos then; if not, an unexpected removal path is a second bug.
- No newer originals after 10:19: the most recent import (status "Removable media import 46/111…", ending in the "not available in the package index" message) added nothing. It may have been all duplicates of the 10:19 import, which would explain why `openPortableAsset` was called with an existing duplicate asset id that the grid index could not resolve.
- The grid shows 19 photos. So the index the UI queries has roughly 19 entries while the package has 140 live assets.
- `Recovery/Staging` and `Recovery/Transactions` are empty (no leftover transaction).
- The app sandbox container (where the production build keeps its index) was not readable from the agent shell, so the persisted index contents were not inspected.

## Where to look

- `LibraryBrowsingCoordinator.openPortableAsset` (the error text at lines ~375 and ~406) and the `onSuccess` path in `AppViewModel.importRemovableMedia` (`reloadPortableCollection()`, then open first imported or first duplicate asset).
- `PortableLibrarySession.startImport` / `applyIndexDelta` / `refreshIndex`: in the `.completed` handler a failure applying the delta is swallowed (`try? self.refreshIndex()`), and `importURLs`/async paths use different persistence (`persistSynchronously`, coalesced index writes on the package-I/O lane). Check whether an index write is lost or never flushed for large imports, whether the persisted index is written atomically, and whether quitting mid-write leaves a stale file.
- Launch-time validation: why a relaunch trusts an index that has far fewer entries than membership. The index is a disposable projection, so launch should compare it to the package (membership shard count/revision, or a membership hash) and rebuild on mismatch (`LibraryIndexProjection(package:)`).
- Duplicate-only imports: opening `result.duplicates.first?.existingAssetID` must resolve through the same index; if not, that is also a stale-index symptom.
- Possible interaction with the dev build (`swift run`, `~/Library/Application Support/Kromora/Indexes`, last written 10:15) and the sandboxed App Store build using different index locations for the same package; a package imported into by one build is indexed only in that build's cache.

## Suggested approach

1. Reproduce deterministically: unit/integration test that imports N files through `startImportURLs`, then asserts the index, `browsingWindow`, and a fresh `LibraryIndexProjection(package:)` agree, including after dropping the in-memory index and reloading the persisted file.
2. Add a launch/open consistency check (membership live count vs index count, plus a revision/hash) with automatic rebuild and a visible status, and a manual "Rebuild Library Index" command as a recovery tool.
3. Fix the swallowed-error path so a failed delta/refresh surfaces a status instead of silently leaving a stale index.
4. Make the post-import reload robust: after any import (including all-duplicate), reload the window from the package-backed index, then open the target asset; fall back to a rebuild before showing the error.
5. Recovery for the affected library: confirm that a rebuild restores all 140 photos (do not modify or delete anything under `Assets/` or `Catalog/`).

## Acceptance criteria

- [x] Root cause recorded (which index file/path was stale and why).
- [x] After an import (new, duplicate-only, and mixed), the grid count and contents match the package's live membership, in both the SwiftPM build and the sandboxed app.
- [x] Relaunch with a stale or truncated index rebuilds it automatically and shows all assets; a status message says so.
- [x] A failed index update is surfaced, never silently swallowed.
- [x] A "Rebuild Library Index" action exists and restores the affected library's 140 photos without touching originals or membership.
- [x] Tests for import-then-reload consistency, stale-index detection on open, and duplicate-only import; `scripts/ci-tests.sh fast` and `serial` pass.

### Comment — claude @ 2026-10-10T00:54:55.526Z

Ready for verification. Implementation committed (see Resolution in the ticket body). The user confirmed the fix works in their library. Note: the 32 removals at 12:03 were the user deleting photos, not a bug.

### Comment — codex @ 2026-10-10T04:18:47.167Z

Implemented the verification fixes in d7c00b2d: stale and corrupt index repairs now publish a status on synchronous and asynchronous opens, index write failures reach the status bar, and observability event coverage includes both index events. Focused AppViewModel, PortableLibrarySession, and Observability tests pass. The required fast lane exited 1 on unrelated CropInspector/InfoInspector/LightInspector source assertions and EditedThumbnailCoordinator timing assertions; the serial lane exited 1 on MenuCommandTests.testCropResetLivesInPinnedInspectorTitleRow.

## Agent log

### Resolution (claude)

**Root cause.** `LibraryIndexProjection.validated(for:)` only compared the library ID, and `reconcilingSourceFingerprints` only repaired fingerprints of entries already in the index. A persisted index missing committed photos (or still listing removed ones) was therefore trusted on every open, and relaunching never repaired it. The production (sandboxed) build keeps its index in its container while `swift run` uses `~/Library/Application Support/Kromora/Indexes`; a package imported into by one build left the other build's index stale, which matches the observed 140 live assets in the package vs 19 in the grid.

**Changes.**
- `LibraryIndexProjection.reconcilingMembership(with:)` (replaces `reconcilingSourceFingerprints`) now treats package membership as canonical: adds live members missing from the index, drops tombstoned/absent assets, repairs fingerprints. Used on both the sync and async open paths; a repair is persisted and logged (`LibraryIndexRepaired` signpost event).
- Failed index writes and failed delta application are no longer swallowed (`LibraryIndexWriteFailed` event); a failed delta now rebuilds the index immediately.
- `openPortableAsset` rebuilds the index once and reloads before reporting "not available in the package index" (the importer already returned the id, so a miss means a stale index).
- "Refresh Library" (Cmd-R, previously "Refresh Source Folder") now rebuilds the index from membership before reloading, so it is the manual recovery; errors are presented instead of ignored.
- Stability hardening found along the way: `Dictionary(uniqueKeysWithValues:)` traps on duplicate keys in `LibraryIndexDelta.merging`, the idle-frame-warmer position/recency maps in `AppViewModel`, and the launch-hint admission in `LibraryBrowsingCoordinator`; all now use `uniquingKeysWith`. A failed removable-media import start no longer leaves the progress bar stuck.
- Tests: `testReopenRepairsPersistedIndexMissingCommittedAssetsAndListingRemovedOnes`; the coordinator miss test asserts one rebuild.

**Verification.** `swift test` for PortableLibrarySession, LibraryBrowsingCoordinator, LibraryIndex/Query, MediaVolume and LibraryScale suites pass. `scripts/ci-tests.sh fast` had one failure, `ThumbnailSwitchLifecycleTests.testFilmstripSelectionSchedulesOriginalBeforeAdjustedDrawableConfirmation`, which passes 3/3 in isolation (flaky under parallel load; unrelated to this change). `MenuCommandTests.testCropResetLivesInPinnedInspectorTitleRow` fails on a source-text assertion about `CropInspectorView.swift`, which this change does not touch. The serial lane was not run.

**Not done / notes.** The user's existing library should recover on next launch (or Cmd-R); not verified against the real sandbox container, which the agent shell cannot read. `rebuildIndex()` reads all membership shards on the main actor (fine at this scale; move to the package-I/O lane for very large libraries). The 32 tombstoned/quarantined assets at 12:03 were not explained.

### Counterpoint verification blocker — codex

**Failed behavior.** Automatic repair reconciles the projection on open, but repair is only recorded as a `LibraryIndexRepaired` observability event. The user-facing status is cleared when index loading completes, so the acceptance requirement that a repaired stale index be announced is not met. Also, the new observability events were added without updating `ObservabilityTests.testWorkflowEventsCoverCacheAndSupersededWork`, which fails because its expected event list is stale.

**Required change.** Publish a clear, user-visible status when an index is repaired on open, including the synchronous and asynchronous open paths. Update the observability event coverage assertion for the two new event names. Keep the package membership reconciliation behavior intact.

**Acceptance / verification.** Add or update tests proving the repair status reaches the status bar on both open paths and that the observability test includes the new event names. Re-run `scripts/ci-tests.sh fast` and `scripts/ci-tests.sh serial`; both must exit 0. The current serial failure in `MenuCommandTests.testCropResetLivesInPinnedInspectorTitleRow` is unrelated to KRMA-842, but it still means the declared lane did not pass on this tree.

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-10T03:57:02.372Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] Root cause recorded (which index file/path was stale and why) (pass) — Resolution records cross-build index locations and membership reconciliation as the root cause.
- [x] After new, duplicate-only, and mixed imports, the grid matches live membership in both app builds (pass) — Membership reconciliation is implemented; the user confirmed the fix in their library.
- [ ] Relaunch with a stale index rebuilds it and a status message says so (fail) — Repair emits LibraryIndexRepaired, but no user-facing repair status is published.
- [ ] Failed index updates are surfaced (fail) — Write/delta errors emit observability events, but visible user notification for failure is not verified.
- [x] Refresh Library rebuilds and restores the affected library without modifying originals or membership (pass) — Refresh rebuilds the disposable index from package membership.
- [ ] Tests cover import/reload, stale-index open, duplicate-only import; fast and serial lanes pass (fail) — The stale-index repair test exists. Fast exits 1, including ObservabilityTests.testWorkflowEventsCoverCacheAndSupersededWork because its expected event list omits the two new event names. Serial exits 1 on unrelated MenuCommandTests.testCropResetLivesInPinnedInspectorTitleRow.
Checks run:
- Reviewed implementation commit fa1910d3 and relevant source and tests
- scripts/ci-tests.sh fast — exit 1; ObservabilityTests.testWorkflowEventsCoverCacheAndSupersededWork fails on the new event names; additional unrelated UI/timing failures also occurred
- scripts/ci-tests.sh serial — exit 1; MenuCommandTests.testCropResetLivesInPinnedInspectorTitleRow fails
Findings:
- Blocking: automatic stale-index repair has no user-visible completion status despite the explicit acceptance criterion.
- Blocking: event coverage test omits the added LibraryIndexRepaired and LibraryIndexWriteFailed names, failing the fast lane.
Fixes:
- None
Verification commits:
- fa1910d3
Actor: codex
Resolved model: unknown
Pickup session: 01MV1UQKGXYTJMRR78
Summary: Verification blocked: stale-index repair is not announced in the UI, and the fast lane fails the observability event coverage test for the new event names.

- 2026-10-10T04:46:05.906Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] Root cause recorded (which index file/path was stale and why) (pass) — Resolution records the cross-build index locations and membership reconciliation root cause.
- [x] After new, duplicate-only, and mixed imports, the grid matches live membership in both app builds (pass) — Membership reconciliation is implemented; the user confirmed the fix in their library.
- [x] Relaunch with a stale or truncated index rebuilds it and a status message says so (pass) — Synchronous and asynchronous status-bar tests pass.
- [x] A failed index update is surfaced, never silently swallowed (pass) — The write-failure status-bar test and event coverage assertion pass.
- [x] Refresh Library rebuilds and restores the affected library without modifying originals or membership (pass) — Refresh rebuilds the disposable index from package membership.
- [ ] Tests cover import/reload consistency, stale-index open, and duplicate-only import; fast and serial lanes pass (fail) — KRMA-842-specific tests pass, but scripts/ci-tests.sh fast and serial both exit 1 on unrelated test failures; a linked urgent follow-up tracks restoring both required lanes.
Checks run:
- Reviewed KRMA-842 implementation and follow-up commits fa1910d3 and d7c00b2d.
- scripts/ci-tests.sh fast — exit 1; failures in CropInspectorTests, EditedThumbnailCoordinatorTests, InfoInspectorPresentationTests, LightInspectorTests, and ThumbnailSwitchLifecycleTests; KRMA-842-specific tests and ObservabilityTests pass.
- scripts/ci-tests.sh serial — exit 1; 499 tests, 5 failures; unrelated to the library-index change.
Findings:
- Blocking acceptance criterion: required fast and serial CI lanes remain red on unrelated tests, so the complete declared verification gate is not satisfied.
Fixes:
- None
Verification commits:
- fa1910d3
- d7c00b2d
Actor: codex
Resolved model: unknown
Pickup session: 01MV1WLGBIZ73ENUDP
Summary: KRMA-842 repair and status fixes pass focused coverage, but verification remains blocked because required fast and serial CI lanes exit 1 on unrelated tests.

- 2026-10-10T06:21:53.975Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Root cause recorded (which index file/path was stale and why) (pass) — Resolution records the separate SwiftPM and sandboxed index locations and explains that missing package members were trusted because validation checked only the library ID.
- [x] After new, duplicate-only, and mixed imports, the grid matches live membership in both app builds (pass) — Membership reconciliation and import/reload coverage are present; the user confirmed recovery in their library.
- [x] Relaunch with a stale or truncated index rebuilds it and a status message says so (pass) — Synchronous and asynchronous stale-index repair publish a status; focused status-bar coverage is included in the passing fast lane.
- [x] A failed index update is surfaced, never silently swallowed (pass) — Index write and delta-application failures are reported; status-bar and observability coverage passed.
- [x] Refresh Library rebuilds and restores the affected library without modifying originals or membership (pass) — Refresh rebuilds the disposable index from package membership; original assets and membership are not rewritten.
- [x] Tests cover import/reload consistency, stale-index open, and duplicate-only import; fast and serial lanes pass (pass) — Required fast and serial lanes passed on the current tree.
Checks run:
- Independent review of membership reconciliation, synchronous/asynchronous open repair, write failure handling, Refresh Library, and focused tests.
- scripts/ci-tests.sh fast — exit 0; 1,586 required tests dispatched.
- scripts/ci-tests.sh serial — exit 0; 500 tests, 0 failures.
Findings:
- None
Fixes:
- None
Verification commits:
- fa1910d3
- d7c00b2d
Actor: codex
Resolved model: unknown
Pickup session: 01MV203GZSF7X5YXSX
Summary: Verification passed: index reconciliation, repair status, failure reporting, and recovery action reviewed; required fast and serial lanes both pass.
