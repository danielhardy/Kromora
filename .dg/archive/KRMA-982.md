---
id: KRMA-982
title: Move import file asset identity resolution off the main actor
type: task
status: done
priority: urgent
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: SourceImportDraft construction performs no file I/O
      result: pass
      notes: The synchronous initializer leaves URL-backed identity nil; AssetIdentityResolutionTests verifies construction without a resolved identity.
    - criterion: Normal file selection resolves and publishes the same stable asset identity asynchronously without blocking the main actor
      result: pass
      notes: AppViewModel.load publishes the selection before awaiting SourceImportDraft.resolved(); the generation fence publishes the resolved plan only for the current selection. Resource-identifier and canonical-path semantics are preserved.
    - criterion: BatchItem fallback identity does not perform file I/O on the main actor
      result: pass
      notes: BatchItem construction leaves URL-backed assetID nil; resolvedAssetID() uses the @concurrent resolver.
    - criterion: Tests prove no file access during synchronous construction and verify resource-identifier/path fallback identity
      result: pass
      notes: AssetIdentityResolutionTests covers draft and batch-item construction, supplied/data identities, real-file resource identity, and unreadable-file canonical path fallback.
    - criterion: swift build, scripts/ci-tests.sh fast, and scripts/ci-tests.sh serial pass
      result: pass
      notes: All declared checks exited 0; fast completed 1,832 tests and serial completed 541 tests with 0 failures.
  checks_run:
    - swift build — exit 0, no warnings
    - scripts/ci-tests.sh fast — exit 0; 1,832 tests completed
    - scripts/ci-tests.sh serial — exit 0; 541 tests, 0 failures
    - git diff --check — exit 0
    - Reviewed KRMA-982 implementation call paths, async publication/generation fencing, and asset identity fallback tests
  findings: []
  fixes:
    - Resolved each batch item fallback asset identity once and reused it for edit lookup and rendering, avoiding duplicate file metadata reads and identity drift within one export item.
  verification_commits:
    - 2ed3c973
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T20:29:58.777Z
  session: 01MV74OOO575BUNRME
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - verification
created: 2026-10-13T20:16:13.148Z
updated: 2026-10-13T20:29:58.780Z
parent: KRMA-950
blockers: []
order: n
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T20:23:05.111Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 2ed3c973
---

Failed behavior: SourceImportDraft.init defaults a missing assetID with PhotoAssetID.file(url), which calls PhotoSourceFingerprint.file(at:) for resource values and a sample digest. AppViewModel.load constructs the draft synchronously on the main actor, so file I/O remains in the selection path. ExportCoordinator.BatchItem.init also has the same fallback when no assetID is supplied. Expected outcome: preserve existing resource-identifier identity and canonical-path fallback semantics while resolving file-backed identity off the main actor; synchronous draft/item construction must not touch the file. Acceptance criteria: (1) SourceImportDraft construction performs no file I/O; (2) normal file selection resolves and publishes the same stable asset identity asynchronously without blocking the main actor; (3) BatchItem fallback identity does not perform file I/O on the main actor; (4) tests prove no file access during synchronous construction and verify resource-identifier/path fallback identity; (5) swift build, scripts/ci-tests.sh fast, and scripts/ci-tests.sh serial pass.


### Comment — claude @ 2026-10-13T20:23:08.475Z

Implemented in c18714e6. SourceImportDraft.assetID is nil for a URL with no supplied identity, and resolved() computes it through the @concurrent PhotoAssetID.resolveFile. BatchItem.assetID likewise stays nil, and resolvedAssetID() resolves it off-main inside the export loop. AssetIdentityResolutionTests cover no-I/O construction plus the path and resource-identifier fallbacks. swift build, ci-tests fast (the output I saw was truncated, so I did not confirm its exit status) and ci-tests serial (541 tests, 0 failures) pass.

## Agent log

- 2026-10-13T20:29:58.777Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] SourceImportDraft construction performs no file I/O (pass) — The synchronous initializer leaves URL-backed identity nil; AssetIdentityResolutionTests verifies construction without a resolved identity.
- [x] Normal file selection resolves and publishes the same stable asset identity asynchronously without blocking the main actor (pass) — AppViewModel.load publishes the selection before awaiting SourceImportDraft.resolved(); the generation fence publishes the resolved plan only for the current selection. Resource-identifier and canonical-path semantics are preserved.
- [x] BatchItem fallback identity does not perform file I/O on the main actor (pass) — BatchItem construction leaves URL-backed assetID nil; resolvedAssetID() uses the @concurrent resolver.
- [x] Tests prove no file access during synchronous construction and verify resource-identifier/path fallback identity (pass) — AssetIdentityResolutionTests covers draft and batch-item construction, supplied/data identities, real-file resource identity, and unreadable-file canonical path fallback.
- [x] swift build, scripts/ci-tests.sh fast, and scripts/ci-tests.sh serial pass (pass) — All declared checks exited 0; fast completed 1,832 tests and serial completed 541 tests with 0 failures.
Checks run:
- swift build — exit 0, no warnings
- scripts/ci-tests.sh fast — exit 0; 1,832 tests completed
- scripts/ci-tests.sh serial — exit 0; 541 tests, 0 failures
- git diff --check — exit 0
- Reviewed KRMA-982 implementation call paths, async publication/generation fencing, and asset identity fallback tests
Findings:
- None
Fixes:
- Resolved each batch item fallback asset identity once and reused it for edit lookup and rendering, avoiding duplicate file metadata reads and identity drift within one export item.
Verification commits:
- 2ed3c973
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV74OOO575BUNRME
Summary: Verified off-main file identity resolution; reused each batch item’s resolved identity once.
