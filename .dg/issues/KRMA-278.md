---
id: KRMA-278
title: EditDocumentStore.status can stick on a stale writeFailure after a successful relink retry
type: bug
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: "Intended semantics decided: a load reports only its own outcome; store-wide worst actionable status tracked separately"
      result: pass
    - criterion: Successful retry of a previously-failed relink (collision or plain rekey) reports .relinked, not a stale .writeFailure
      result: pass
    - criterion: A genuinely unrelated ongoing problem (e.g. .corrupt elsewhere) does not leak into an unrelated healthy load, while still retained as store-level diagnostic
      result: pass
  checks_run:
    - "swift build: clean"
    - "swift test --filter EditDocumentStoreTests: 16 tests, 0 failures"
    - "scripts/ci-tests.sh fast: 640 tests, 0 failures"
    - "git status --porcelain -- Sources Tests: clean"
    - Manual review of AppViewModel.swift:1392-1396 confirms UI consumes per-load status/isActionable and correctly clears editStoreStatus on a subsequent non-actionable load
  findings: []
  fixes: []
  verification_commits:
    - bd3e63d
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-08T19:16:34.040Z
  session: 01MTT1T0R99XOEQ5NH
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-08T02:43:19.888Z
updated: 2026-09-10T12:53:52.909Z
parent: KRMA-261
depends_on:
  - KRMA-261
order: a0
board: product
commits:
  - bd3e63d
---

## Objective

`EditDocumentStore.load(for:)`'s relink paths call `restoreActionableStatus(after:)` after a
persist attempt. That helper re-applies `previousStatus` whenever it was `isActionable` and the
new outcome isn't itself a `.writeFailure` — but it cannot distinguish "a genuinely separate,
still-live problem" from "this same call's own prior failed attempt, now resolved by retrying."

## Context

Found while verifying KRMA-261 (relink assetID collisions). Repro test:
`EditDocumentStoreTests.testRelinkCollisionRollsBackOnPersistFailureSoRetrySucceeds` in
`Tests/LumoKitTests/EditDocumentStoreTests.swift` (added on KRMA-261's verification commit).

Sequence: a relink's `persist()` fails once (injected failure) → `status = .writeFailure`,
`modelContext.rollback()` correctly undoes the delete + rekey → the caller retries the same
`load()` → this time `persist()` succeeds and the record is correctly relinked (`found`,
`document` are both right) → but `restoreActionableStatus` sees `previousStatus` (the leftover
`.writeFailure` from the prior attempt) `.isActionable == true`, and since this attempt's own
status isn't a fresh `.writeFailure`, it overwrites the successful `.relinked` status with the
stale `.writeFailure`. The store's data is fine; only the reported `status`/`message` lies to the
caller (e.g. a UI banner could keep showing "Could not save edit records" after the edit is
safely persisted). The stale status is only cleared by an unrelated, fully successful `save()`
(which unconditionally sets `status = .ready`), not by a successful `load()`/relink.

This predates KRMA-261 — the same `restoreActionableStatus` call already existed on the
non-collision, direct-hit relink branch — but KRMA-261 is the first place a retry-after-failure
of the *same* relink is explicitly a first-class scenario, so it's the clearest place to fix it.

## Acceptance criteria

- [ ] Decide the intended semantics: should `status` after a load-triggered relink distinguish
      "this call's own outcome" from "a leftover problem elsewhere in the store," and if so, how
      (e.g. track staleness per record, or simply let a fully successful relink always win)?
- [ ] A successful retry of a previously-failed relink (collision or plain rekey) reports
      `.relinked`, not a stale `.writeFailure` from the earlier attempt.
- [ ] Existing behavior of surfacing a genuinely unrelated ongoing problem (e.g. `.corrupt`
      elsewhere) is not regressed if it's still considered load-bearing.

## Implementation notes

Likely touches `restoreActionableStatus(after:)` and both its call sites in
`Sources/LumoKit/Models/EditDocumentStore.swift`. Not a blocker for KRMA-261: data integrity and
`found`/`document` are correct on retry; only the reported status is stale.

### Comment — codex @ 2026-09-08T19:14:02.366Z

Implemented in bd3e63d. EditDocumentStore now reports each load's own outcome, so successful collision and plain-rekey retries return .relinked instead of a stale prior .writeFailure. Store-wide worst actionable diagnostics remain retained separately, including unrelated corrupt records. Added regression coverage for both retry shapes and corruption isolation. Verification: swift test (959 passed, 44 expected skips), swift build, git diff --check, dg validate (schema OK; existing unknown pickup-model warning).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-08T19:16:34.041Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Intended semantics decided: a load reports only its own outcome; store-wide worst actionable status tracked separately (pass)
- [x] Successful retry of a previously-failed relink (collision or plain rekey) reports .relinked, not a stale .writeFailure (pass)
- [x] A genuinely unrelated ongoing problem (e.g. .corrupt elsewhere) does not leak into an unrelated healthy load, while still retained as store-level diagnostic (pass)
Checks run:
- swift build: clean
- swift test --filter EditDocumentStoreTests: 16 tests, 0 failures
- scripts/ci-tests.sh fast: 640 tests, 0 failures
- git status --porcelain -- Sources Tests: clean
- Manual review of AppViewModel.swift:1392-1396 confirms UI consumes per-load status/isActionable and correctly clears editStoreStatus on a subsequent non-actionable load
Findings:
- None
Fixes:
- None
Verification commits:
- bd3e63d
Actor: claude
Resolved model: sonnet
Pickup session: 01MTT1T0R99XOEQ5NH
Summary: Verified: reviewed bd3e63d's refactor of EditDocumentStore. finishLoad() now sets the published/returned status to each load's own outcome (relink success, corrupt, or write-failure) instead of restoreActionableStatus reintroducing a stale prior status. A separate worstActionableStatus (severity-ranked, never regresses) is retained purely as an internal diagnostic consulted only by save()'s cannotWrite message when persistenceUnavailable is permanently true. Confirmed AppViewModel (line 1392) already consumes the per-load result's status/isActionable to set/clear editStoreStatus, so the fix is UI-visible: a successful retry now clears the stale write-failure banner as intended. Ran swift build (clean), swift test --filter EditDocumentStoreTests (16/16 pass, including the two new regression tests for plain-rekey and collision retry, plus testLoadStatusBelongsToThePhotoBeingLoaded proving an unrelated corrupt record does not leak into a healthy load), and scripts/ci-tests.sh fast (640/640 pass, including SwiftDataConcurrencyGateTests). git status clean on tracked source/tests. No blockers, no broader findings warranting a child ticket.
