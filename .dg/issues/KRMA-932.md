---
id: KRMA-932
title: Create virtual copies off the main actor (copy+hash original and index rebuild)
type: task
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Copy, hash, markVirtualCopy, and index update avoid main-actor blocking; the session API is async and preserves inline fallback.
      result: pass
      notes: Copy/hash/relationship transaction run through enqueuePackageIO when scheduled, with inline fallback otherwise. The disposable index projection is updated incrementally on MainActor from the returned delta.
    - criterion: Index update is incremental when import results provide the needed delta.
      result: pass
      notes: Kept incremental applyIndexDelta; importSources supplies the delta and the copy membership upsert includes the updated display name and copy relationship.
    - criterion: The inspector disables repeat requests during copy.
      result: pass
      notes: Published in-progress state disables and relabels the action; coordinator rejects a second request.
    - criterion: Failure is reported once, no partial copy is visible, and in-progress state clears.
      result: pass
      notes: Copy persistence uses package transaction semantics; coordinator reports operation failure through the existing status path and clears state with defer.
    - criterion: Generated PNG copies remain independent and carry source edits; main actor responsiveness and shutdown publication behavior are covered.
      result: pass
      notes: Strengthened tests use a real generated PNG, verify byte preservation and independent asset identity, assert the active edit document is saved to the copied identity, and exercise a gated main-actor hop plus shutdown suppression.
    - criterion: Swift build is warning-free and Swift 6 mode has no escape hatches.
      result: pass
      notes: swift build completed with exit 0 and no diagnostics.
    - criterion: scripts/ci-tests.sh fast exits 0.
      result: pass
      notes: Fast lane completed all 1,807 required tests with exit 0.
  checks_run:
    - swift build — passed (exit 0; no diagnostics)
    - scripts/ci-tests.sh fast — passed (exit 0; all 1,807 required tests)
    - swift test --filter KromoraKitTests.(PackageEditProjectionTests|EditHistoryCoordinatorTests) — passed (exit 0; 29 tests)
    - git diff --check — passed
  findings: []
  fixes:
    - Updated virtual-copy package coverage to use a generated PNG and verify byte preservation.
    - Asserted that current edits are saved to the new copy identity.
    - Committed as 3226bebf7d361695d57b2960fa6e848588e8a69c.
    - "Index strategy: incremental applyIndexDelta using the import delta plus the post-markVirtualCopy membership upsert; no full refreshIndex rebuild."
  verification_commits:
    - 3226bebf7d361695d57b2960fa6e848588e8a69c
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T18:47:18.531Z
  session: 01MV714AE6XDND36IG
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - must-fix
  - performance
  - package
created: 2026-10-13T14:47:42.695Z
updated: 2026-10-13T18:47:18.534Z
parent: KRMA-922
blockers: []
order: zr
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T18:39:25.419Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 3226bebf7d361695d57b2960fa6e848588e8a69c
---

## Objective

"Create Virtual Copy" must not freeze the app while it copies and hashes a 100+ MB RAW and rebuilds
the library index projection.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding M5. `PortableLibrarySession` (`Sources/KromoraKit/Models/
PortableLibrarySession.swift`) is `@MainActor`. Durable package transactions (journal writes,
`F_FULLFSYNC` per file, directory fsyncs, checksums, renames; see `PortablePackageTransaction.swift`)
run inline on the main actor from several user actions, stalling the UI.

The off-main mechanism already exists: `ImageWorkScheduler.enqueuePackageIO(id:lane:priority:
onTerminal:operation:)` (`Sources/KromoraKit/Models/ImageWorkScheduler.swift` ~L259). Its `operation`
runs off the main actor in a package-I/O lane. `PortableLibrarySession` already uses it for index
load/write and backfills (see its `scheduler`, `indexWriteJobID`, … properties and the
`enqueuePackageIO` call sites near L321, L414, L511, L575). Copy that pattern. A session created
without a scheduler (some tests) falls back to inline work; keep that fallback working.

Package values (`package`, `lease`, `clock`) are captured as `let`s before hopping off the main actor
(see `updateLibraryState` L1549 for how they are read). Mutations must still go through
`lease.withWriterMutationLock` so writer exclusivity is unchanged.

Specific to virtual copies:

- UI entry: `Sources/KromoraKit/Views/InfoInspectorView.swift` ~L282 calls
  `viewModel.createVirtualCopy()` (`AppViewModel.swift` ~L3889).
- `EditHistoryCoordinator.createVirtualCopy(of:makeCopy:didCreate:)`
  (`Sources/KromoraKit/ViewModels/EditHistoryCoordinator.swift` ~L192) takes a synchronous
  `@MainActor () throws -> VirtualCopy` closure (`makeCopy`) and runs it inline inside a spawned task
  that is main-actor isolated.
- `PortableLibrarySession.createVirtualCopy(of:)` (~L1167) reads the source record, imports the
  embedded original again (full copy and content hash), `markVirtualCopy`, then `refreshIndex()`
  (rebuilds the whole projection).
- Shutdown contract in the doc comment: "Shutdown lets an accepted copy finish writing but suppresses
  `didCreate`". Preserve it.

## Acceptance criteria

- [ ] The heavy part (import copy + hash + `markVirtualCopy` + index update) runs inside
      `enqueuePackageIO`, exposed as an `async throws` session method (e.g. `createVirtualCopy(of:)
      async throws`). `makeCopy` becomes `@Sendable () async throws -> VirtualCopy` (or equivalent) and
      `EditHistoryCoordinator` awaits it; only `didCreate` and UI updates run on the main actor.
- [ ] `refreshIndex()` is replaced by an incremental `applyIndexDelta` for the single new asset if
      `importPackageSources` already returns what is needed; if not, keep `refreshIndex()` but it must
      run off the main actor too. State which you chose in the review comment.
- [ ] While the copy is in flight the Info inspector button shows a disabled/in-progress state and a
      second tap cannot start a second copy (add a published `isCreatingVirtualCopy`-style flag on the
      existing owner; do not add a new global object).
- [ ] Failure is reported once via the existing error path; no partial copy remains visible (existing
      transaction semantics) and the in-progress flag clears.
- [ ] Tests: virtual copy of a generated PNG creates an independent asset with the source edits
      copied (existing tests under `grep -rn createVirtualCopy Tests`); a new test proves that during a
      gated `makeCopy` the main actor stays responsive (run a trivial `@MainActor` hop with a
      timeout while the gate is closed) and that shutdown during the copy suppresses `didCreate`.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).

## Implementation notes

Do not change the product behavior that virtual copies duplicate the original (separate decision
ticket). Do not touch culling, delete, or open-repair paths.


### Comment — claude @ 2026-10-13T18:39:21.135Z

Index update: kept it incremental. importSources already returns an indexDelta; I merge it with an upsert of the copy's membership entry (read after markVirtualCopy, so the display name/copy flag are included) and apply it via applyIndexDelta on the main actor, so no refreshIndex rebuild. Copy+hash+markVirtualCopy run in enqueuePackageIO (importCopyHash lane; inline when no scheduler); markVirtualCopy is under withWriterMutationLock; shutdown cancelAndWaits the job so the lease outlives it. session.createVirtualCopy(of:) is now async throws; EditHistoryCoordinator awaits makeCopy (@MainActor async), exposes isCreatingVirtualCopy (second request returns nil, flag cleared via defer on success/failure/shutdown), and the Info inspector button disables/relabels. Tests added: gated makeCopy keeps main actor responsive + rejects second request + clears flag; shutdown during copy suppresses didCreate; scheduled session creates independent copy with incremental index. swift build warning-free; scripts/ci-tests.sh fast exits 0 (no StoredEditAdoptionTests failure). Commit 8b1c0ae7.

## Agent log

- 2026-10-13T18:47:18.531Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Copy, hash, markVirtualCopy, and index update avoid main-actor blocking; the session API is async and preserves inline fallback. (pass) — Copy/hash/relationship transaction run through enqueuePackageIO when scheduled, with inline fallback otherwise. The disposable index projection is updated incrementally on MainActor from the returned delta.
- [x] Index update is incremental when import results provide the needed delta. (pass) — Kept incremental applyIndexDelta; importSources supplies the delta and the copy membership upsert includes the updated display name and copy relationship.
- [x] The inspector disables repeat requests during copy. (pass) — Published in-progress state disables and relabels the action; coordinator rejects a second request.
- [x] Failure is reported once, no partial copy is visible, and in-progress state clears. (pass) — Copy persistence uses package transaction semantics; coordinator reports operation failure through the existing status path and clears state with defer.
- [x] Generated PNG copies remain independent and carry source edits; main actor responsiveness and shutdown publication behavior are covered. (pass) — Strengthened tests use a real generated PNG, verify byte preservation and independent asset identity, assert the active edit document is saved to the copied identity, and exercise a gated main-actor hop plus shutdown suppression.
- [x] Swift build is warning-free and Swift 6 mode has no escape hatches. (pass) — swift build completed with exit 0 and no diagnostics.
- [x] scripts/ci-tests.sh fast exits 0. (pass) — Fast lane completed all 1,807 required tests with exit 0.
Checks run:
- swift build — passed (exit 0; no diagnostics)
- scripts/ci-tests.sh fast — passed (exit 0; all 1,807 required tests)
- swift test --filter KromoraKitTests.(PackageEditProjectionTests|EditHistoryCoordinatorTests) — passed (exit 0; 29 tests)
- git diff --check — passed
Findings:
- None
Fixes:
- Updated virtual-copy package coverage to use a generated PNG and verify byte preservation.
- Asserted that current edits are saved to the new copy identity.
- Committed as 3226bebf7d361695d57b2960fa6e848588e8a69c.
- Index strategy: incremental applyIndexDelta using the import delta plus the post-markVirtualCopy membership upsert; no full refreshIndex rebuild.
Verification commits:
- 3226bebf7d361695d57b2960fa6e848588e8a69c
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV714AE6XDND36IG
Summary: Verified off-main virtual copy flow; strengthened PNG and copied-edit coverage.
