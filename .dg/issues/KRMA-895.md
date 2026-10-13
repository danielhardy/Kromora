---
id: KRMA-895
title: Create existing-album PhotoKit change requests inside performChanges
type: bug
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Both album change requests are constructed and mutated inside their respective performChanges closures.
      result: pass
    - criterion: A nil existing-album change request produces the album-warning result without retrying or duplicating the created asset.
      result: pass
      notes: Code review confirms the nil request is transported out of the nonthrowing closure and raised into the existing album-placement warning path; no retry or second asset creation occurs.
    - criterion: File export and successful Photos asset creation retain their current semantics when optional album placement fails.
      result: pass
      notes: The asset transaction precedes album placement; addAsset failures are caught and returned as an album warning.
    - criterion: Automated coverage guards production transaction placement without Photos authorization or library mutation.
      result: pass
      notes: Structural test checks both factories and both addAssets mutations occur inside performChanges. It does not exercise live PhotoKit behavior.
    - criterion: Required tests do not request Photos permissions or modify a real Photos library; live existing/new album behavior is reported accurately.
      result: pass
      notes: No live Photos test was run; it requires authorization and a real library.
    - criterion: Swift 6 build and focused checks pass with no new diagnostics.
      result: pass
      notes: swift build and the focused PhotosDeliveryTests suite passed.
  checks_run:
    - swift build — passed (exit 0)
    - swift test --no-parallel --filter PhotosDeliveryTests — passed (5 tests, exit 0)
    - dg validate — passed with pre-existing agent-model warnings
    - git diff --check — passed (exit 0)
  findings: []
  fixes:
    - Strengthened the structural regression test to also guard both addAssets mutations inside performChanges.
  verification_commits:
    - 136862fc1f6f5ce5079367796168349fd8d5b965
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-12T19:37:37.227Z
  session: 01MV5NKRQN5RFP1G98
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - swift
  - photos
  - correctness
created: 2026-10-12T16:37:59.890Z
updated: 2026-10-12T19:37:37.230Z
blockers: []
order: y
board: product
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/Models/PhotosDelivery.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/PhotosDeliveryTests.swift
      access: write
      confidence: 1
  observed:
    paths: []
    captured_at: 2026-10-12T19:29:44.917Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 136862fc1f6f5ce5079367796168349fd8d5b965
---

## Objective

Prevent a process-level PhotoKit exception when an export is delivered to an existing Photos album. Both creation and mutation of a `PHAssetCollectionChangeRequest` must occur inside its photo-library change block.

## Problem and user impact

In `PhotoKitDelivery.addAsset(withIdentifier:toAlbumNamed:)`, the existing-album branch currently creates `PHAssetCollectionChangeRequest(for: existing)` at `PhotosDelivery.swift:166`, then enters `library.performChanges` at line 169 only to call `change.addAssets`. That factory call already requires an active change block. This is a framework transaction violation; an Objective-C exception is not converted into a Swift error by `do/catch`. The new-album branch directly below correctly creates its request inside `performChanges` and even documents the rule.

Trigger: export a photo with Photos delivery enabled and an album name that already exists. The file has already committed before Photos delivery starts, so a PhotoKit crash can terminate an otherwise successful export. This was established by source inspection and the Apple contract; the review did not mutate the user's Photos library or reproduce the exception against it.

Apple reference: https://developer.apple.com/documentation/photos/phassetcollectionchangerequest/init%28for%3A%29 (discussion requires creating the change request within a photo library change block).

## Context to read

- `Sources/KromoraKit/Models/PhotosDelivery.swift`: `PhotoKitDelivery.deliver`, `createAsset`, and `addAsset`; `PhotosDeliveryResult` and `PhotosDeliveryError`.
- `Sources/KromoraKit/ViewModels/ExportCoordinator.swift`: post-file-commit Photos delivery and warning reporting.
- `Tests/KromoraKitTests/PhotosDeliveryTests.swift`: current tests substitute `FakePhotosDelivery`; they do not exercise the production PhotoKit transaction boundary.
- `docs/ENGINEERING_GUIDE.md` and `scripts/ci-tests.sh`: ownership and verification lanes.

## Implementation guidance

1. Keep fetching the existing album and newly created asset outside the mutation block; move the existing-album request factory and its mutations together inside `library.performChanges`.
2. Keep handling an unavailable change request as a recoverable album-placement failure. Respect the actual imported Swift signature of the change closure; do not assume it can throw. If needed, transport a small result back after the awaited transaction using safe Swift 6 semantics.
3. Preserve the delivery contract: file export is already safe; asset creation failure is reported separately; album placement failure after successful asset creation returns a warning, not a total export failure or a second asset creation attempt.
4. Keep this localized. Do not add Objective-C exception catching, concurrency escape hatches, or a generalized Photos framework wrapper just to hide the violation.

## Acceptance criteria

- [ ] Existing- and new-album change requests are both constructed and mutated inside their respective `performChanges` closures.
- [ ] A nil existing-album change request produces the established album-warning result without retrying or duplicating the created asset.
- [ ] File export and successful Photos asset creation retain their current semantics when optional album placement fails.
- [ ] Add automated coverage for the production transaction placement, rather than relying solely on the fake `PhotosDelivering` tests. A narrow structural regression guard is acceptable for this framework rule if a lightweight behavioral seam would require broad abstraction. Explain what it covers and what requires actual PhotoKit authorization.
- [ ] Required tests do not request Photos permissions or modify a real Photos library. If a supervised manual test is available, record separate existing-album/new-album results; do not claim an unperformed live test passed.
- [ ] Swift 6 build and focused checks pass with no new diagnostics.

## Verification

Run `swift build`, `swift test --no-parallel --filter PhotosDeliveryTests`, `dg validate`, and `git diff --check`. Add the new regression test to the appropriate existing suite, or ensure a new suite is assigned to the correct CI lane. Report any unrelated pre-existing failures separately.
## Repository and workflow constraints

- Read `CLAUDE.md` and `.dg/AGENTS.md` before implementation. Target macOS 26+ on Apple Silicon, Swift 6, and Apple frameworks only. Keep the zero-opt-out concurrency contract: no `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
- Claim this issue before changing code. Preserve unrelated working-tree changes. Work on the current branch, commit only coherent issue work with this issue ID in the subject, and hand off to `review` according to `.dg/AGENTS.md`.
- Use generated temporary fixtures and deterministic synchronization. Do not run display-bound release capture benchmarks for these fixes. Product implementations belong in `Sources/KromoraKit`, not the launchers or Xcode packaging target.
- Review evidence was collected on 2026-10-12 using Xcode 27 / Swift 6.4. The combined existing `PackagePathTests|DeriveCoordinatorTests|PhotosDeliveryTests|AnalysisValueTypesTests` selection passed 24 tests, but those green results do not cover the defects described here. Do not treat them as regression coverage for the new behavior.


### Comment — claude @ 2026-10-12T19:29:41.787Z

Moved PHAssetCollectionChangeRequest(for:) inside the performChanges closure; a nil request is reported via a flag and throws the existing album-warning error (no retry, asset not duplicated). Added a structural regression test (testAlbumChangeRequestsAreCreatedInsidePerformChanges) that checks both factories appear inside performChanges in the source. Live behavior needs real Photos authorization and was not tested manually. swift build, PhotosDeliveryTests (5), git diff --check pass; dg validate shows only pre-existing model warnings.

## Agent log

- 2026-10-12T19:37:37.227Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Both album change requests are constructed and mutated inside their respective performChanges closures. (pass)
- [x] A nil existing-album change request produces the album-warning result without retrying or duplicating the created asset. (pass) — Code review confirms the nil request is transported out of the nonthrowing closure and raised into the existing album-placement warning path; no retry or second asset creation occurs.
- [x] File export and successful Photos asset creation retain their current semantics when optional album placement fails. (pass) — The asset transaction precedes album placement; addAsset failures are caught and returned as an album warning.
- [x] Automated coverage guards production transaction placement without Photos authorization or library mutation. (pass) — Structural test checks both factories and both addAssets mutations occur inside performChanges. It does not exercise live PhotoKit behavior.
- [x] Required tests do not request Photos permissions or modify a real Photos library; live existing/new album behavior is reported accurately. (pass) — No live Photos test was run; it requires authorization and a real library.
- [x] Swift 6 build and focused checks pass with no new diagnostics. (pass) — swift build and the focused PhotosDeliveryTests suite passed.
Checks run:
- swift build — passed (exit 0)
- swift test --no-parallel --filter PhotosDeliveryTests — passed (5 tests, exit 0)
- dg validate — passed with pre-existing agent-model warnings
- git diff --check — passed (exit 0)
Findings:
- None
Fixes:
- Strengthened the structural regression test to also guard both addAssets mutations inside performChanges.
Verification commits:
- 136862fc1f6f5ce5079367796168349fd8d5b965
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV5NKRQN5RFP1G98
Summary: Passed independent verification; strengthened transaction-coverage guard.
