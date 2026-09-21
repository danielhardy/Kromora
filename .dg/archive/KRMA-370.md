---
id: KRMA-370
title: Release removable-media security scope after import to support clean eject
type: bug
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Release the collection-owned removable-volume scope after import no longer needs the source card.
      result: pass
      notes: addFromMediaVolume now starts the scope, performs the synchronous copy via addFromURLs, and stops the scope in a defer guarded by the start's return value; scopedURL (the persistent source-folder slot) is no longer touched by this path.
    - criterion: Imported managed-library assets remain usable after the card is ejected.
      result: pass
      notes: durableURL() copies the file into the managed library synchronously inside addFromURLs, before the deferred stopAccessingSecurityScopedResource runs; the regression test deletes the source file post-import and confirms the managed copy is still readable.
    - criterion: Repeated, failed, and cancelled imports do not leak security-scoped access.
      result: pass
      notes: defer runs on every exit path of addFromMediaVolume, including when addFromURLs skips unreadable/missing files; testFailedMediaVolumeImportDoesNotRetainACollectionScope covers the missing-file case and passes.
    - criterion: Add regression coverage for scope cleanup and post-eject use of managed copies.
      result: pass
      notes: MediaVolumeTests.swift adds hasActiveSourceFolderScopeForTesting assertions plus a post-eject managed-copy read-back test and a failed-import scope test.
  checks_run:
    - swift test --filter MediaVolumeImportTests (8 passed)
    - scripts/ci-tests.sh fast (887 tests, 0 failures)
    - git diff --check (clean)
    - git status --porcelain (no changes introduced by verification; pre-existing unrelated modifications from other in-progress issues left untouched)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-12T02:44:04.786Z
  session: 01MTXS40X54QUDYF7L
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - removable-media
created: 2026-09-12T02:24:56.102Z
updated: 2026-09-12T02:44:04.788Z
order: a0
board: product
---

## Objective

Release removable-media security-scoped access after selected images have been copied into Kromora's managed library, so the source card can be ejected cleanly.

## Context

The removable-media import task releases its temporary access scope, but ImageCollection.addFromMediaVolume() starts another scope and stores it in scopedURL. Because addFromURLs() copies the card files into the managed library, the source-volume scope is no longer needed after the copy completes. It currently remains held until a later source transition, collection clear, or deinit.

## Acceptance criteria

- [ ] Release the collection-owned removable-volume scope after import no longer needs the source card.
- [ ] Imported managed-library assets remain usable after the card is ejected.
- [ ] Repeated, failed, and cancelled imports do not leak security-scoped access.
- [ ] Add regression coverage for scope cleanup and post-eject use of managed copies.

## Related

- KRMA-367 covers detecting an SD card mounted after app launch; this ticket covers post-import access cleanup and eject readiness.


### Comment — codex @ 2026-09-12T02:41:30.430Z

Implemented and committed as f5147db. Removable-media imports now hold the resolved security scope only for the synchronous copy, releasing it on success and failure without overwriting any persistent source-folder scope. Added regression coverage for post-eject managed-copy readability and failed-import cleanup. Checks: swift test --filter MediaVolumeImportTests (8 passed), swift build -c release, git diff --check, dg validate (all pass; existing deprecation and runner-model warnings only).

## Agent log

- 2026-09-12T02:44:04.786Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Release the collection-owned removable-volume scope after import no longer needs the source card. (pass) — addFromMediaVolume now starts the scope, performs the synchronous copy via addFromURLs, and stops the scope in a defer guarded by the start's return value; scopedURL (the persistent source-folder slot) is no longer touched by this path.
- [x] Imported managed-library assets remain usable after the card is ejected. (pass) — durableURL() copies the file into the managed library synchronously inside addFromURLs, before the deferred stopAccessingSecurityScopedResource runs; the regression test deletes the source file post-import and confirms the managed copy is still readable.
- [x] Repeated, failed, and cancelled imports do not leak security-scoped access. (pass) — defer runs on every exit path of addFromMediaVolume, including when addFromURLs skips unreadable/missing files; testFailedMediaVolumeImportDoesNotRetainACollectionScope covers the missing-file case and passes.
- [x] Add regression coverage for scope cleanup and post-eject use of managed copies. (pass) — MediaVolumeTests.swift adds hasActiveSourceFolderScopeForTesting assertions plus a post-eject managed-copy read-back test and a failed-import scope test.
Checks run:
- swift test --filter MediaVolumeImportTests (8 passed)
- scripts/ci-tests.sh fast (887 tests, 0 failures)
- git diff --check (clean)
- git status --porcelain (no changes introduced by verification; pre-existing unrelated modifications from other in-progress issues left untouched)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTXS40X54QUDYF7L
