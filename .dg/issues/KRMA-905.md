---
id: KRMA-905
title: Cache virtual-copy inspector metadata instead of reading asset records in view getters
type: bug
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Repeated inspector getter reads and unrelated presentation updates do not cause additional asset-record reads.
      result: pass
      notes: The inspector getters only read the coordinator snapshot. The counted ReadGate test repeatedly accesses both values and confirms only one read for the same active asset.
    - criterion: The active source/copy relationship is loaded off the main actor once per necessary asset refresh and preserves existing description and action semantics.
      result: pass
      notes: The package reader performs the synchronous record read in a detached utility task. The generated-package test confirms the copy parent prefix, original action availability, and missing-record behavior.
    - criterion: The main actor remains responsive while an injected record reader is blocked.
      result: pass
      notes: The MainActor sentinel test completes while the reader is held at its gate.
    - criterion: Stale results, source clearing, removal, and shutdown cannot publish prior metadata.
      result: pass
      notes: Generation and shutdown guards reject late results; source changes synchronously reset presentation. The coordinator tests cover late A publication, nil source, and shutdown. Library deletion clears activeSourceReference.
    - criterion: Generated package originals and copies present the correct parent identity; missing records disable copy creation without leaking an old label.
      result: pass
      notes: Verified by testRealPackageOriginalAndCopyAndMissingRecord.
    - criterion: Virtual-copy creation continues to validate package truth, and existing copy/history behavior remains intact.
      result: pass
      notes: createVirtualCopy retains its package-record validation. Existing EditHistoryCoordinator virtual-copy/history tests passed.
  checks_run:
    - swift build — passed (exit 0)
    - swift test --no-parallel --filter InfoInspectorViewTests|InfoInspectorPresentationTests|EditHistoryCoordinatorTests|PortableLibrarySessionTests|PackageSettingsTests — passed (45 tests, exit 0)
    - swift test --no-parallel --filter VirtualCopyMetadataCoordinatorTests — passed (5 tests, exit 0)
    - dg validate — passed (exit 0; existing model-name warnings)
    - git diff --check — passed (exit 0)
    - Independent review of KRMA-905 implementation, coordinator tests, source-change wiring, deletion clearing, and shutdown integration — passed
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-12T20:59:36.597Z
  session: 01MV5QGH3WMC1V71FZ
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - swift
  - app-view-model
  - maintainability
  - concurrency
created: 2026-10-12T17:11:41.318Z
updated: 2026-10-12T20:59:36.601Z
blockers: []
order: zz
board: product
context:
  files:
    - Sources/KromoraKit/Models/PortableLibrarySession.swift
    - Sources/KromoraKit/Views/InfoInspectorView.swift
    - Tests/KromoraKitTests/InfoInspectorViewTests.swift
    - Tests/KromoraKitTests/InfoInspectorPresentationTests.swift
    - Tests/KromoraKitTests/PortableLibrarySessionTests.swift
    - Sources/KromoraKit/Models/PortableLibraryPackage.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
  docs:
    - CLAUDE.md
    - AGENTS.md
    - docs/APP_ARCHITECTURE.md
    - docs/ENGINEERING_GUIDE.md
  issues:
    - KRMA-903
  commands:
    - swift build
    - swift test --no-parallel --filter 'InfoInspectorViewTests|InfoInspectorPresentationTests|EditHistoryCoordinatorTests|PortableLibrarySessionTests|PackageSettingsTests'
    - dg validate
    - git diff --check
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/ViewModels/AppViewModel.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/Models/PortableLibrarySession.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/Views/InfoInspectorView.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/InfoInspectorViewTests.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/InfoInspectorPresentationTests.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/PortableLibrarySessionTests.swift
      access: write
      confidence: 1
  observed:
    paths: []
    captured_at: 2026-10-12T20:05:56.014Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Make virtual-copy presentation getters pure in-memory reads. Load the active asset's copy relationship asynchronously once per relevant asset/package change, with explicit stale-result and shutdown handling.

## Evidence

`AppViewModel.virtualCopySourceDescription` and `canCreateVirtualCopy` (approximately lines 3878-3889) separately call `portableLibrary.package.readAssetRecord`. That method resolves the package path, executes Data(contentsOf:), decodes JSON, extracts unknown fields and validates the record. `InfoInspectorView` reads both getters in body (approximately 276 and 280), so an inspector evaluation can read the same file twice on MainActor. Root document/status changes can reevaluate the inspector even when the copy relationship has not changed.

The action's own validation at `createVirtualCopy` is a separate command boundary. This ticket removes I/O from presentation without making the action trust a stale cache or changing package truth. Apple's guidance recommends immediate file reads off-main: https://developer.apple.com/documentation/foundation/improving-performance-and-stability-when-accessing-the-file-system.

## Context to read

- `Sources/KromoraKit/ViewModels/AppViewModel.swift`: the two getters, activeSourceReference, source adoption/removal, createVirtualCopy and shutdown.
- `Sources/KromoraKit/Views/InfoInspectorView.swift`: the virtual-copy section and observation boundary.
- `Models/PortableLibraryPackage.swift`: readAssetRecord; `Models/PortableLibrarySession.swift`: existing package worker accessors and lifecycle.
- `ViewModels/EditHistoryCoordinator.swift` and `Models/PortablePackageCopies.swift`: copy creation and refresh triggers.
- `Tests/KromoraKitTests/InfoInspectorViewTests.swift`, `InfoInspectorPresentationTests.swift`, `EditHistoryCoordinatorTests.swift`, `PortableLibrarySessionTests.swift` and `PortableLibraryPackageTests.swift`.

## Implementation steps

1. Introduce a narrow Sendable presentation snapshot containing asset identity, optional copy-of identity and record availability. Keep it in an existing focused owner or small metadata collaborator; do not cache the full mutable asset record in every view.
2. Load through an explicit off-main package read boundary. Reuse already-loaded record metadata when available; do not call materializedAsset merely to trigger unrelated fingerprint/hash work for this label.
3. Capture the active package/source identity and generation, then install the snapshot only while they remain current and the owner is live. Pending/failed/no-source snapshots must clear a previous photo's description and conservatively disable capability until known.
4. Refresh on active-source changes, copy creation and relevant record/membership replacement or asset removal. Avoid rereading when only exposure, histogram, unrelated status or inspector expansion changes.
5. Make both existing getters inspect the same snapshot and perform zero file access. Keep command-time validation authoritative; this cache must never permit writing to a missing/removed record or closed package.
6. Own cancellation and await pending reads during shutdown. If history shutdown is already implemented in KRMA-903, integrate with its owner boundaries without duplicating a store.

## Acceptance criteria

- [ ] A counted reader proves repeated reads of either getter and unrelated document/status changes cause zero new disk accesses.
- [ ] A loaded source/copy uses at most one relationship read per necessary refresh and returns the existing description/availability semantics.
- [ ] A main-actor sentinel remains runnable while an injected record reader is blocked.
- [ ] Late A success/failure cannot replace B's metadata; no-source, removal and shutdown clear stale output and reject late publication.
- [ ] A real generated package original and virtual copy display correct parent identity; failed/missing records disable the action without leaking the previous label.
- [ ] createVirtualCopy still validates against package truth and existing copy/history tests pass.

## Non-goals

Do not redesign the inspector, copy storage format or copy naming. Moving the copy command's physical-original copy to a worker is outside this presentation-cache ticket. Avoid a new metadata persistence layer; package records remain authoritative.

## Reading the source context

Source and test paths above are relative to the repository root, `/Users/dhardy/Dev/Kromora`. The installed `dg context` reader currently resolves file/doc contents inside the `.dg` space, so it can list existing repository sources as missing. Read those paths directly from the checkout; their existence was verified when this ticket was written. Keep the repository-relative context hints for planning. Do not copy product source into `.dg` or weaken DispatchGraph path validation to work around this reader limitation.

## Required checks

```sh
swift build
swift test --no-parallel --filter 'InfoInspectorViewTests|InfoInspectorPresentationTests|EditHistoryCoordinatorTests|PortableLibrarySessionTests|PackageSettingsTests'
dg validate
git diff --check
```

Run any newly added collaborator suite as well. These are targeted regression checks; broaden them only when the changed boundary or new failures justify it.

## Repository constraints and implementation handoff

- Read `CLAUDE.md` and `.dg/AGENTS.md`, then claim this issue before code changes. Work on the current branch and preserve unrelated working-tree changes. Execute one issue at a time; dependency tickets must be implemented before dependent work.
- Target macOS 26+ on Apple Silicon, Swift 6, Apple frameworks only. No backwards-compatibility fallback, third-party dependency, @unchecked Sendable, nonisolated(unsafe), or @preconcurrency. Keep application implementation inside KromoraKit and retain AppViewModel's existing line-count ceiling.
- Use generated temporary fixtures and deterministic continuation/event gates. Put package/index/cache paths under test-owned temporary directories. Do not run display-bound release capture scripts or use arbitrary sleeps as proof of cancellation correctness.
- Run the focused checks below plus `dg validate` and `git diff --check`. Record commands, outcomes and any environmental limitation. Existing green tests do not replace new regression coverage for this issue.
- Commit coherent issue work with this issue ID followed by a colon in the subject. Follow the implementation handoff to `review`; do not mark done or bypass independent verification. Update architecture guidance only for the final ownership/behavior.


### Comment — claude @ 2026-10-12T20:05:52.637Z

Added VirtualCopyMetadataCoordinator: one off-main package read per active-asset change, generation/shutdown-guarded; getters are now in-memory. createVirtualCopy still validates against package truth. swift build, focused tests (50 pass), git diff --check OK; dg validate only unrelated model warnings.

## Agent log

- 2026-10-12T20:59:36.597Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Repeated inspector getter reads and unrelated presentation updates do not cause additional asset-record reads. (pass) — The inspector getters only read the coordinator snapshot. The counted ReadGate test repeatedly accesses both values and confirms only one read for the same active asset.
- [x] The active source/copy relationship is loaded off the main actor once per necessary asset refresh and preserves existing description and action semantics. (pass) — The package reader performs the synchronous record read in a detached utility task. The generated-package test confirms the copy parent prefix, original action availability, and missing-record behavior.
- [x] The main actor remains responsive while an injected record reader is blocked. (pass) — The MainActor sentinel test completes while the reader is held at its gate.
- [x] Stale results, source clearing, removal, and shutdown cannot publish prior metadata. (pass) — Generation and shutdown guards reject late results; source changes synchronously reset presentation. The coordinator tests cover late A publication, nil source, and shutdown. Library deletion clears activeSourceReference.
- [x] Generated package originals and copies present the correct parent identity; missing records disable copy creation without leaking an old label. (pass) — Verified by testRealPackageOriginalAndCopyAndMissingRecord.
- [x] Virtual-copy creation continues to validate package truth, and existing copy/history behavior remains intact. (pass) — createVirtualCopy retains its package-record validation. Existing EditHistoryCoordinator virtual-copy/history tests passed.
Checks run:
- swift build — passed (exit 0)
- swift test --no-parallel --filter InfoInspectorViewTests|InfoInspectorPresentationTests|EditHistoryCoordinatorTests|PortableLibrarySessionTests|PackageSettingsTests — passed (45 tests, exit 0)
- swift test --no-parallel --filter VirtualCopyMetadataCoordinatorTests — passed (5 tests, exit 0)
- dg validate — passed (exit 0; existing model-name warnings)
- git diff --check — passed (exit 0)
- Independent review of KRMA-905 implementation, coordinator tests, source-change wiring, deletion clearing, and shutdown integration — passed
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV5QGH3WMC1V71FZ
Summary: Independent verification passed; required build, focused tests, collaborator tests, DispatchGraph validation, and diff checks succeeded.
