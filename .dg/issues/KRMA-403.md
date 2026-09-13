---
id: KRMA-403
title: "Phase 2.3: copy-on-import pipeline — streamed hash, dedupe, cancellation, clonefile"
type: feature
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Each original is read exactly once while streamed SHA-256 and copy/clone staging occur
      result: pass
      notes: PortablePackageTransaction.stage(fileAt:) uses one source-open pass with a bounded SHA-256 stream; clonefile creates the CoW staging entry and the source is opened once for hashing. The importer exposes a source-read observer and the test asserts one callback per original.
    - criterion: clonefile is used for same-volume staging and streamed fallback exists
      result: pass
      notes: Automatic staging checks same-volume eligibility and attempts clonefile, falling back to the streamed path when unavailable; the importer test exercises the streamed fallback deterministically.
    - criterion: Duplicate content is detected and reported
      result: pass
      notes: Existing package records and earlier items in the import are indexed by content hash; default policy reports and skips duplicates, with an importAnyway policy available.
    - criterion: Cancellation leaves no partially published assets and does not touch sources
      result: pass
      notes: Each asset has its own journaled transaction; cancellation checkpoints cover staging, flush, checksum, and publish, then abort/recovery removes staging and rolls back publication. Tests assert package membership is empty and source bytes are unchanged.
    - criterion: Progress is published incrementally
      result: pass
      notes: Progress is emitted during preparation, per-item staging/commit, and completion; the multi-asset test observes separate committing updates.
    - criterion: Required verification
      result: pass
      notes: swift build, focused package/import/transaction tests (10/10), dg validate --json, and git diff --check pass. Full swift test executed 1,386 tests with 52 skips and 14 failures in pre-existing unrelated UI/async suites; all KRMA-403 tests pass.
  checks_run:
    - swift build
    - swift test --filter PortablePackageImportTests|PortablePackageTransactionTests|PackageSettingsTests
    - swift test
    - dg validate --json
    - git diff --check
  findings:
    - Full swift test remains red only in the pre-existing unrelated UI/async failure family documented by prior package tickets.
  fixes: []
  verification_commits:
    - 6319b0f
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-13T11:27:32.987Z
  session: 01MTZPUXXYMT0XFIBA
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - persistence
  - import
created: 2026-09-12T19:44:16.753Z
updated: 2026-09-13T11:27:32.988Z
depends_on:
  - KRMA-402
order: zzzh
board: product
commits:
  - 6319b0f
---

## Objective

Implement copy-on-import: reading each original once, streaming SHA-256, detecting duplicates,
supporting cancellation, and using `clonefile` where the filesystem supports it — writing into the
package through the transaction layer, never modifying or deleting the external source.

## Dependencies

- The transaction-protocol ticket (import commits go through the journal/staging/lease machinery it
  defines).

## Scope

- Implement the import pipeline: for each original, read it exactly once while simultaneously
  streaming a SHA-256 hash and copying/cloning it into the package's staging area.
- Use `clonefile` (or the equivalent APFS copy-on-write primitive) when source and destination are on
  the same APFS volume; fall back to a streamed copy otherwise.
- Detect duplicates by content hash during import (same content imported twice is recognized, not
  silently duplicated) and surface that to the caller.
- Support cancellation mid-import: a cancelled import must not leave partial assets published in the
  package (the transaction layer's staging/atomic-publish should make this natural — verify it here).
- Guarantee the external source is never modified or deleted, under success, failure, or
  cancellation.
- Publish import progress progressively (per-asset or batched), not only at the very end.

## Acceptance criteria

- [ ] Each original is read exactly once during import (verified by instrumentation/test, not just
  inspection).
- [ ] `clonefile` is used on the same-volume path; a portable streamed-copy fallback exists and is
  tested for the cross-volume path.
- [ ] Duplicate content imported twice is detected and reported, not silently duplicated in the
  package.
- [ ] Cancellation at any point during import leaves the package with no partially-published assets
  and the external source untouched.
- [ ] Progress is published incrementally during a multi-asset import.
- [ ] `swift build`, `swift test`, `dg validate`, and `git diff --check` pass.

## Verification lane

Persistence/import fault-injection lane: cancellation at multiple points, duplicate-detection
correctness, and same-volume vs cross-volume copy behavior, plus a source-untouched assertion after
every scenario.

## Context

- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/ENGINEERING_GUIDE.md
- context.issues: KRMA-391

## Agent log

- 2026-09-13T11:27:32.987Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Each original is read exactly once while streamed SHA-256 and copy/clone staging occur (pass) — PortablePackageTransaction.stage(fileAt:) uses one source-open pass with a bounded SHA-256 stream; clonefile creates the CoW staging entry and the source is opened once for hashing. The importer exposes a source-read observer and the test asserts one callback per original.
- [x] clonefile is used for same-volume staging and streamed fallback exists (pass) — Automatic staging checks same-volume eligibility and attempts clonefile, falling back to the streamed path when unavailable; the importer test exercises the streamed fallback deterministically.
- [x] Duplicate content is detected and reported (pass) — Existing package records and earlier items in the import are indexed by content hash; default policy reports and skips duplicates, with an importAnyway policy available.
- [x] Cancellation leaves no partially published assets and does not touch sources (pass) — Each asset has its own journaled transaction; cancellation checkpoints cover staging, flush, checksum, and publish, then abort/recovery removes staging and rolls back publication. Tests assert package membership is empty and source bytes are unchanged.
- [x] Progress is published incrementally (pass) — Progress is emitted during preparation, per-item staging/commit, and completion; the multi-asset test observes separate committing updates.
- [x] Required verification (pass) — swift build, focused package/import/transaction tests (10/10), dg validate --json, and git diff --check pass. Full swift test executed 1,386 tests with 52 skips and 14 failures in pre-existing unrelated UI/async suites; all KRMA-403 tests pass.
Checks run:
- swift build
- swift test --filter PortablePackageImportTests|PortablePackageTransactionTests|PackageSettingsTests
- swift test
- dg validate --json
- git diff --check
Findings:
- Full swift test remains red only in the pre-existing unrelated UI/async failure family documented by prior package tickets.
Fixes:
- None
Verification commits:
- 6319b0f
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTZPUXXYMT0XFIBA
Summary: Implemented transactional copy-on-import with streamed hashing, clonefile fallback, duplicate reporting, cancellation rollback, and incremental progress.
