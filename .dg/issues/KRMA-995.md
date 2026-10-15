---
id: KRMA-995
title: Batch export must not apply the active photo's edits to other photos
type: bug
status: done
priority: urgent
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A package asset with no saved edit exports a neutral document, including when it was never opened and the active photo is edited.
      result: pass
      notes: The fake-engine regression verifies a never-opened package asset receives an identity EditDocument instead of the active +2 EV document.
    - criterion: An unreadable or otherwise actionable edit load fails that item with an explanation the batch summary can show; it does not export another photo’s document or increment the success count.
      result: pass
      notes: Malformed saved revision yields exported=0, failed=1, no render request, and a Skipped message that says its saved edit could not be read.
    - criterion: Mixed selections and lazy multi-photo Share use the same per-item resolution rules.
      result: pass
      notes: The mixed fake-engine batch exports the edited and neutral documents independently and counts the corrupt item as failed; lazy Share uses neutral edits for untouched items and throws for unreadable edits.
    - criterion: The active Look is not substituted; an unresolved Look on a per-asset document fails or warns that item.
      result: pass
      notes: "An unresolved per-asset Look fails before rendering. Chosen wording: its Look could not be loaded. Unreadable edit wording is its saved edit could not be read (...)."
    - criterion: Tests cover the untouched and unreadable probes plus one mixed batch through ExportCoordinator, asserting requested documents and outcome counts.
      result: pass
      notes: Focused fake-engine tests assert the neutral and saved documents, failure counts, and that invalid items do not render.
    - criterion: Export distinguishes a healthy missing edit from an actionable load failure without rewriting unrelated loaders.
      result: pass
      notes: A healthy missing revision resolves to EditDocument(); an actionable load result throws an item-level error. No unrelated loaders were changed.
    - criterion: swift build is warning-free and scripts/ci-tests.sh fast exits 0; serial runs only if the real encode path changes.
      result: pass
      notes: Both required checks passed. The real encode path was untouched, so the serial lane was not required.
  checks_run:
    - "swift test --filter ExportCoordinator: passed, 30 tests, exit 0"
    - "scripts/ci-tests.sh fast: passed, 1,913 required-fast tests, exit 0; lane audit total 2,527 (561 required-serial and 53 optional)"
    - "swift build: passed, exit 0, no warnings"
    - "git diff --check: passed, exit 0"
    - Reviewed per-item document and Look resolution, batch failure accounting, and lazy Share call path
  findings:
    - BatchItem.lut documentation said an unavailable referenced Look was safe to omit, while per-asset exports correctly fail that item. Updated the comment to match the behavior.
  fixes:
    - "Clarified the BatchItem.lut comment: absent pre-resolved tables are resolved by the coordinator, and a missing per-asset Look fails that item."
  verification_commits:
    - 0a40c43b
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T16:24:20.875Z
  session: 01MV8BFK4KZTR0BKYB
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - release-readiness
  - readiness-2026-10-14
  - must-fix
  - export
created: 2026-10-14T16:08:52.072Z
updated: 2026-10-14T16:24:20.878Z
parent: KRMA-994
blockers: []
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/ViewModels/ExportCoordinator.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
    - Sources/KromoraKit/ViewModels/ExportWorkflowCoordinator.swift
    - Sources/KromoraKit/Models/EditDocumentStore.swift
  docs:
    - CLAUDE.md
    - .context/2026-10-14-release-readiness-review.md
  issues:
    - KRMA-994
    - KRMA-1000
    - KRMA-1008
  commands:
    - swift test --filter ExportCoordinator
    - scripts/ci-tests.sh fast
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T16:19:47.055Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 0a40c43b
---

## Objective

A batch export or lazy multi-photo Share must use each photo's own edit. A healthy photo with no saved edit exports neutral. An unreadable saved edit fails that item. The active photo's edit is never a silent fallback.

## Context

Confirmed on 2026-10-14 with disposable-package probes against `main` at `312f0537`. `ExportCoordinator.resolvedDocument` (`Sources/KromoraKit/ViewModels/ExportCoordinator.swift`, around line 815) treats every load that is not `found` as the caller's fallback document. `AppViewModel.makeBatchExportRequest` (around line 4102) passes the active photo's document and Look as that fallback. Unopened photos have no in-memory document, so they take this path.

Probe result: photo A at +2 EV, untouched unopened photo B, one export, zero failures, fallback exposure `2.0`. The same happened when B's saved revision was replaced with malformed JSON: the item still exported A's exposure and counted as success.

`EditDocumentLoadResult.isUsableForPrefetch` (`Sources/KromoraKit/Models/EditDocumentStore.swift`, around line 75) already distinguishes a healthy missing revision from an actionable failure. Prefetch uses it. Export discards it.

When `isPerAsset` is false, Look resolution also does `lutResolver?(...) ?? lut` (around lines 383 and 617), so the active Look leaks along with the active document. A per-asset document whose Look cannot be resolved currently exports with a nil Look and still reports success. The review requires that missing Look dependency to be visible, not described as a fully reproduced edit.

Sibling tickets also edit export: KRMA-1000 (job lifetime) and KRMA-1008 (batch sharpening). Do not change task ownership or sharpening here. Do not add a "copy this edit onto the selection" command.

Parent epic: KRMA-994. Review: `.context/2026-10-14-release-readiness-review.md` finding 1.

## Reproduction

- Untouched: import a photo into a temporary package, leave `currentRevision` at zero, give `ExportCoordinator` the package store, omit the item's in-memory document, export with a +2 EV fallback. The engine request must not use that fallback.
- Unreadable: save a distinct edit, replace the current native revision JSON with malformed bytes, confirm the load is not a healthy miss, export again. That item fails and the requested document is not the fallback.

## Acceptance criteria

- [ ] A package asset with no saved edit exports a neutral document, including when it was never opened and the active photo is edited.
- [ ] An unreadable or otherwise actionable edit load fails that item with an explanation the batch summary can show. It does not export another photo's document and it does not increment the success count.
- [ ] Mixed selections (edited, untouched, unreadable) in one batch follow those rules per item. Lazy multi-photo Share uses the same resolution helper and follows the same rules.
- [ ] The active Look is not substituted when the item did not resolve its own document. A resolved document whose Look id cannot be loaded fails or warns that item; it must not be reported as a fully reproduced edit with the Look silently dropped. State the chosen wording in the review comment.
- [ ] Tests cover the two probe variants and one mixed batch through `ExportCoordinator` (a fake engine is enough). Assert the requested document and the outcome counts.
- [ ] Callers other than export/share may keep using `EditDocumentLoadResult`, but export must not collapse "missing" and "failed" into one boolean. Do not rewrite unrelated loaders.
- [ ] `swift build` is warning-free. `scripts/ci-tests.sh fast` exits 0. Run `scripts/ci-tests.sh serial` if you touch the real encode path; a fake-engine test does not require it.

## Constraints

- Re-read the cited lines before editing. Line numbers drift.
- Swift 6 language mode stays on. No `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, or `#available` branches. No new dependencies.
- Do not run `scripts/run-kromora-capture.sh`. Display-bound numbers already live in `docs/TESTING.md`.
- Preserve unrelated working-tree changes. Do not revert other tickets' edits.
- One issue at a time. Commit subject starts with this issue id. Hand off at `review`; do not mark `done`.


### Comment — cursor @ 2026-10-14T16:14:19.551Z

Filed for the backlog under KRMA-994. The board promoted this complete AI ticket to ready (project ai_ticket_creation policy) and pickup claimed it before it could be moved back. The acceptance criteria in this issue are the intended fix; sibling export tickets KRMA-1000 and KRMA-1008 are still backlog and should not be edited here.


### Comment — claude @ 2026-10-14T16:19:46.532Z

Implemented in 19d21ef5. Export/Share now resolve each item's own edit: live snapshot or stored record wins; a healthy package asset with no saved edit exports a neutral document; an unreadable/actionable load (or corrupt revision) fails that item with 'Skipped <name>: its saved edit could not be read (...)' and is counted as failed, never as exported. The caller's fallback document/Look is used only for items with no store/asset identity (loose files). Look wording: a per-asset document naming a Look that cannot be loaded fails the item with 'its Look could not be loaded' (not silently dropped, no active-Look substitution). Lazy Share (renderEncodedData(for:)) throws the same errors. Tests: untouched-unopened, corrupt revision, mixed batch, lazy Share, unloadable Look in ExportCoordinatorTests; the existing selection-snapshot test now registers its files in a package. swift build clean; scripts/ci-tests.sh fast exit 0; serial not run (real encode path untouched).

## Agent log

- 2026-10-14T16:24:20.875Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A package asset with no saved edit exports a neutral document, including when it was never opened and the active photo is edited. (pass) — The fake-engine regression verifies a never-opened package asset receives an identity EditDocument instead of the active +2 EV document.
- [x] An unreadable or otherwise actionable edit load fails that item with an explanation the batch summary can show; it does not export another photo’s document or increment the success count. (pass) — Malformed saved revision yields exported=0, failed=1, no render request, and a Skipped message that says its saved edit could not be read.
- [x] Mixed selections and lazy multi-photo Share use the same per-item resolution rules. (pass) — The mixed fake-engine batch exports the edited and neutral documents independently and counts the corrupt item as failed; lazy Share uses neutral edits for untouched items and throws for unreadable edits.
- [x] The active Look is not substituted; an unresolved Look on a per-asset document fails or warns that item. (pass) — An unresolved per-asset Look fails before rendering. Chosen wording: its Look could not be loaded. Unreadable edit wording is its saved edit could not be read (...).
- [x] Tests cover the untouched and unreadable probes plus one mixed batch through ExportCoordinator, asserting requested documents and outcome counts. (pass) — Focused fake-engine tests assert the neutral and saved documents, failure counts, and that invalid items do not render.
- [x] Export distinguishes a healthy missing edit from an actionable load failure without rewriting unrelated loaders. (pass) — A healthy missing revision resolves to EditDocument(); an actionable load result throws an item-level error. No unrelated loaders were changed.
- [x] swift build is warning-free and scripts/ci-tests.sh fast exits 0; serial runs only if the real encode path changes. (pass) — Both required checks passed. The real encode path was untouched, so the serial lane was not required.
Checks run:
- swift test --filter ExportCoordinator: passed, 30 tests, exit 0
- scripts/ci-tests.sh fast: passed, 1,913 required-fast tests, exit 0; lane audit total 2,527 (561 required-serial and 53 optional)
- swift build: passed, exit 0, no warnings
- git diff --check: passed, exit 0
- Reviewed per-item document and Look resolution, batch failure accounting, and lazy Share call path
Findings:
- BatchItem.lut documentation said an unavailable referenced Look was safe to omit, while per-asset exports correctly fail that item. Updated the comment to match the behavior.
Fixes:
- Clarified the BatchItem.lut comment: absent pre-resolved tables are resolved by the coordinator, and a missing per-asset Look fails that item.
Verification commits:
- 0a40c43b
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV8BFK4KZTR0BKYB
Summary: Verified per-photo batch export and lazy Share resolution; all required checks passed.
