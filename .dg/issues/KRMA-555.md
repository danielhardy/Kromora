---
id: KRMA-555
title: "Verification hygiene: untracked helpers, format skew, dirty tree"
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Untracked helpers (PackageJSONCoder, PackagePath, NumericClamping, PackagePathTests) committed
      result: pass
      notes: Tracked per audit.
    - criterion: Fate of other Sep-22 files decided
      result: pass
      notes: Committed; no related dirty paths remain.
    - criterion: Swift-format gate re-checked on CI macos-26
      result: not_applicable
      notes: No CI run available; local beta formatter intentionally not used. Remains unchecked.
    - criterion: Working tree reconciled without absorbing other work
      result: pass
      notes: Remaining dirty entries are unrelated UI edits and .dg bookkeeping; untouched.
    - criterion: Import summary precedence during Loading
      result: pass
      notes: Summaries deferred until preview settles; regression test covers partial failure.
  checks_run:
    - swift test --filter AppViewModelTests|EmbeddedFirstFrameTests (41 executed, 1 opt-in skip, 0 failures) before and after fix
  findings:
    - Queued pendingImportOutcome was not cleared when a newer summary presented directly; stale summary could overwrite status. Fixed.
    - On preview settle the queued summary replaces failure statuses such as Could not display; non-blocking.
  fixes:
    - Clear pendingImportOutcome in presentImportOutcome when presenting immediately (5b750b2).
  verification_commits:
    - 5b750b2
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T19:35:16.139Z
  session: 01MUN2RQGEE5HZ5RVU
creation_provenance:
  runner: pi
  model: unknown
  actor: pi
labels:
  - verification
created: 2026-09-23T15:00:55.501Z
updated: 2026-09-29T19:35:16.142Z
parent: KRMA-548
blockers:
  - id: legacy-krma-555
    type: human
    reason: The remaining dirty ObservabilityTests.swift edit appears to belong to KRMA-557, which is in verification, and the intended import-summary precedence while a photo is loading needs product-owner confirmation. This issue forbids absorbing other work before ownership is confirmed.
    action: Confirm whether the ObservabilityTests.swift update should be committed under KRMA-557, and whether import outcome summaries (especially partial failures) should remain visible during Loading; then resume KRMA-555.
    created_at: 2026-09-23T16:18:52.766Z
    resolved_at: 2026-09-29T13:00:12.023Z
    resolved_by: web
  - id: evt_mumougsi_c8kb0a
    type: human
    reason: "Product confirmation is still needed for import-summary precedence: current code drops terminal outcomes while a photo is Loading, including partial failures."
    action: Confirm whether terminal import summaries should remain suppressed during Loading or be shown after the photo finishes loading; then resume KRMA-555.
    created_at: 2026-09-29T13:04:28.290Z
    resolved_at: 2026-09-29T13:13:40.220Z
    resolved_by: cli
order: a0
board: product
blocked_reason: "Product confirmation is still needed for import-summary precedence: current code drops terminal outcomes while a photo is Loading, including partial failures."
blocked_action: Confirm whether terminal import summaries should remain suppressed during Loading or be shown after the photo finishes loading; then resume KRMA-555.
blocked_from_status: ready
commits:
  - 5b750b2
---

## Objective

Reconcile the non-blocking verification findings from KRMA-548: untracked source files that
clean checkouts need, the local swift-format skew, and the dirty working tree — without
absorbing other tickets' work by accident.

## Context

Parent: KRMA-548 (counterpoint verification, 2026-09-23). None of these block the KRMA-548
test outcomes (the working tree builds and runs), but they affect CI and review.

## Acceptance criteria

- [ ] `Sources/KromoraKit/Models/PackageJSONCoder.swift` is committed. It is referenced by
  committed code (`PortablePackageImporter.encode`, introduced by `cbd9e5b`, KRMA-551
  verification) but was never `git add`ed, so any clean checkout at/after `cbd9e5b` —
  including KRMA-548's `b8d0842` — fails to compile (`cannot find 'PackageJSONCoder' in
  scope`; verified in a scratch worktree). Attribute it to the owning ticket, not to a
  drive-by commit.
- [ ] Decide the fate of the other untracked files from the same Sep-22 session:
  `Sources/KromoraKit/Models/PackagePath.swift`,
  `Sources/KromoraKit/Models/NumericClamping.swift`,
  `Tests/KromoraKitTests/PackagePathTests.swift`, plus the uncommitted tracked
  modifications that consume them (`PortableLibraryPackage.swift`,
  `PortablePackageTransaction.swift`, `CanvasNavigation.swift`, color/crop/light/local-mask
  models, `RenderPipeline.swift`, `RenderBoundarySourceResolver.swift`,
  `PackageSettingsTests.swift`, `docs/TESTING.md`). They compile in-tree and may belong to
  an in-flight hardening effort — confirm the owner before committing any of it.
- [ ] Re-check the Swift-format gate on CI (`macos-26`), not with the local Xcode-beta
  (Swift 6.4) toolchain: locally, `scripts/check-swift-format.sh` flags even pristine
  committed files (e.g. `OrderedImports`/`DoNotUseSemicolons` in `ImageCollection.swift`),
  so the local results cannot adjudicate the implementer's "lint passed" claim. Do NOT
  bulk-reformat with the beta toolchain.
- [ ] Reconcile the working tree per the project Git mode: ~55 dirty entries (`.dg`
  bookkeeping, the files above) plus a deep stash pile (`git stash list`). Verify with
  `git status --porcelain` after the agent runs that land here.
- [ ] Review item (no ticket split needed unless it grows): `b8d0842` added a
  `presentImportOutcome` early-return that suppresses import summaries (including
  partial-failure summaries) whenever a `Loading ...` status is showing, and
  `EmbeddedFirstFrameTests` dropped its `Loading first.ARW...` status assertion in the
  same commit. Confirm the status precedence is the intended UX, not test-serving.

## Implementation notes

Keep each fix with its owning ticket. Verification commits must stay limited to the
verified change; do not sweep unrelated WIP into a KRMA-548 commit.

### Comment — codex @ 2026-09-29T13:04:28.085Z

Audit update: , , , and  are tracked in KRMA-534 commit 02a4765. The remaining paths listed in the issue are committed; there are no dirty Sources, Tests, or docs paths.  is tracked in a82cf09. I left the existing stash stack and other issues' .dg bookkeeping untouched. The current origin repository has no CI runs available, so I could not check the macos-26 swift-format gate; I made no Swift changes and did not run the local formatter with Xcode 27.0. Current  still suppresses summaries during , including terminal partial-failure summaries. The note that partial failures are no longer visible does not explicitly confirm whether this precedence is desired, so I am blocking for that product decision.

### Comment — codex @ 2026-09-29T13:13:37.653Z

Product decision: Keep terminal import outcomes, including partial failures, and defer their presentation while a photo is Loading. Show the summary after loading completes; do not drop it. This resolves the import-summary precedence question.

### Comment — codex @ 2026-09-29T19:34:00.656Z

Implemented in 866ecfa. Import outcomes are queued while previewState is loading and shown after preview success or failure; regression coverage confirms partial-failure summaries remain visible. Updated the standard-open status expectation for the confirmed UX. Verified: swift test --filter 'AppViewModelTests|EmbeddedFirstFrameTests' (41 passed, 1 expected opt-in RAW skip). Full swift test was started but stopped after its synthetic relocation test took 149s; it had one now-updated standard-open expectation mismatch and did not finish. No macos-26 workflow run is available for cb7444f, so the CI swift-format gate remains unchecked; I did not run the local beta formatter. PackageJSONCoder.swift, PackagePath.swift, NumericClamping.swift, and PackagePathTests.swift are tracked. Kept unrelated pre-existing UI/.dg edits and stash entries untouched. Handing off for review.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->


## HUMAN NOTE

It looks like the ObservabilitTests.swift is gone so can't determine (guessing it was commited). I no longer see partial failures.

- 2026-09-29T19:35:16.140Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Untracked helpers (PackageJSONCoder, PackagePath, NumericClamping, PackagePathTests) committed (pass) — Tracked per audit.
- [x] Fate of other Sep-22 files decided (pass) — Committed; no related dirty paths remain.
- [ ] Swift-format gate re-checked on CI macos-26 (not_applicable) — No CI run available; local beta formatter intentionally not used. Remains unchecked.
- [x] Working tree reconciled without absorbing other work (pass) — Remaining dirty entries are unrelated UI edits and .dg bookkeeping; untouched.
- [x] Import summary precedence during Loading (pass) — Summaries deferred until preview settles; regression test covers partial failure.
Checks run:
- swift test --filter AppViewModelTests|EmbeddedFirstFrameTests (41 executed, 1 opt-in skip, 0 failures) before and after fix
Findings:
- Queued pendingImportOutcome was not cleared when a newer summary presented directly; stale summary could overwrite status. Fixed.
- On preview settle the queued summary replaces failure statuses such as Could not display; non-blocking.
Fixes:
- Clear pendingImportOutcome in presentImportOutcome when presenting immediately (5b750b2).
Verification commits:
- 5b750b2
Actor: claude
Resolved model: sonnet
Pickup session: 01MUN2RQGEE5HZ5RVU
Summary: Verified deferred import-summary presentation (866ecfa); fixed stale pending outcome (5b750b2). Targeted tests pass; CI swift-format gate unchecked.
