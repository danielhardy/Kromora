---
id: KRMA-898
title: Move embedded Look byte loading off the main actor with ordered persistence handoff
type: bug
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Actual Look file reads run off the main actor, proven with an injected reader/executor assertion.
      result: pass
      notes: EmbeddedLookLoader uses @concurrent; the injected reader records the thread and the test confirms a main-actor sentinel runs while the reader is blocked.
    - criterion: A slow worker does not block an independent main-actor sentinel.
      result: pass
      notes: Deterministic gate test passes.
    - criterion: Superseded snapshots and library/store replacement cannot install stale bytes; cancelled/shutdown work cannot publish later.
      result: pass
      notes: Generation fencing and cancellation checks prevent stale publication; shutdown now awaits the canceled worker task before returning.
    - criterion: Saving immediately after importing/selecting a Look embeds its bytes and the package remains resolvable after the external fixture is removed.
      result: pass
      notes: Store save awaits the pending load; the package round-trip test removes the source file and verifies the persisted content signature.
    - criterion: An unreadable Look does not prevent other valid Looks from being installed.
      result: pass
      notes: Generated unreadable and valid Look fixture test passes.
    - criterion: Slow A/fast B completion ordering and shutdown cancellation are deterministic without wall-clock performance thresholds.
      result: pass
      notes: Generation ordering uses gated readers; cancellation test awaits the canceled task after releasing its gate. Shutdown awaits the returned worker task.
    - criterion: AppViewModel stays within its line-count ceiling and Swift 6 compilation has no opt-outs or diagnostics.
      result: pass
      notes: PackageSettingsTests checks the AppViewModel ceiling and concurrency escape hatches; swift build completed without diagnostics.
  checks_run:
    - swift build (passed)
    - swift test --no-parallel --filter LUTWorkflowTests|EditDocumentStoreTests|PortableLibraryPackageTests|PackageSettingsTests (30 tests passed before verification fix)
    - swift test --no-parallel --filter EmbeddedLookLoaderTests plus requested related suites (35 tests passed after verification fix)
    - dg validate (OK; pre-existing model-name warnings in other project records)
    - git diff --check (passed)
  findings: []
  fixes:
    - Made shutdown await cancellation of embedded Look loading and completion of its worker task, closing a late-publication window.
    - Replaced the cancellation test sleep with a deterministic await of the canceled task.
  verification_commits:
    - 540b044e
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-12T19:55:56.479Z
  session: 01MV5O5XI0A9C3RRB9
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - swift
  - concurrency
  - performance
  - looks
created: 2026-10-12T16:38:02.829Z
updated: 2026-10-12T19:55:56.482Z
blockers: []
order: zv
board: product
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/ViewModels/AppViewModel.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/Models/EditDocumentStore.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/EditDocumentStoreTests.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/LUTWorkflowTests.swift
      access: write
      confidence: 1
  observed:
    paths: []
    captured_at: 2026-10-12T19:45:35.942Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 540b044e
---

## Objective

Keep startup and Look import responsive by removing synchronous whole-Look-library file reads from the main actor, while preserving self-contained package edit persistence and latest-library-wins semantics.

## Problem and impact

`AppViewModel.configureEmbeddedLooks()` at approximately lines 1589-1598 reduces `library.allLUTs` into a `[String: Data]` by executing `Data(contentsOf: look.url)` for every Look. `AppViewModel` is main-actor isolated. The `Task` in this method starts only after all file reads complete, so it does not move the expensive work off-main. Setup/library adoption and `library.onImported` call this path; repeated imports reread the full library. A large Look collection or slow external disk can stall event handling and rendering while those synchronous reads run.

This was established by source inspection; the review did not collect new responsiveness timings. Apple recommends avoiding immediate file I/O on the main thread: https://developer.apple.com/documentation/foundation/improving-performance-and-stability-when-accessing-the-file-system.

## Context to read

- `Sources/KromoraKit/ViewModels/AppViewModel.swift`: all `configureEmbeddedLooks()` callers, `wireCoordinators`, `applyLookLibraryDelta`, package/library replacement, persistence flush and shutdown barriers.
- `Sources/KromoraKit/Models/LUTLibrary.swift`: `allLUTs`, revision/delta publication, import/rescan workers, and security-scoped access ownership.
- `Sources/KromoraKit/Models/EditDocumentStore.swift`: `setEmbeddedLookBytes`, `sourceLookBytes(for:)`, and `save`/`commitEditRevision` ordering. Look bytes make a revision portable after the external file disappears.
- `Sources/KromoraKit/Models/SecurityScopedResourceAccess.swift` and `docs/STORAGE_POLICY.md`.
- `Tests/KromoraKitTests/LUTWorkflowTests.swift`, `EditDocumentStoreTests.swift`, `PortableLibraryPackageTests.swift`, and `PackageSettingsTests.swift` (AppViewModel size guard).

## Implementation guidance

1. Snapshot only immutable Sendable input identities/URLs on the main actor and perform byte loading on an explicit worker actor or other owned off-main executor. `Task {}` inheriting the main actor is not sufficient for synchronous file reads.
2. Keep the orchestration focused; use a small collaborator if necessary rather than expanding the already-large AppViewModel. Do not create another document store or bypass `EditDocumentStore`.
3. Track the task and generation. A slow snapshot A must not overwrite snapshot B, publish to a replaced edit store/library session, or outlive shutdown. Cancel/await owned work at the appropriate lifecycle barriers.
4. Preserve the ordering between loading bytes and any dependent durable edit write. Simply making this method asynchronous and fire-and-forget can let an edit save run before its selected Look bytes are installed. Make the prerequisite explicit at the existing persistence boundary, or feed already-loaded bytes from the Look worker when that is simpler.
5. Keep external file access valid for the full worker read using the existing security-scope owner. Preserve the current treatment of unreadable Looks unless a related correctness fix is needed; avoid unrelated UI flows.
6. Do not change persisted Look IDs, content-addressed package blobs, or derive/save behavior. Do not serialize an in-memory cube to approximate the original external file bytes.

## Acceptance criteria

- [ ] Actual Look file reads occur off the main actor; a deterministic injected reader/executor assertion proves this without a display benchmark.
- [ ] A slow worker does not block an independent main-actor sentinel while loading is pending.
- [ ] Superseded snapshots and library/store replacement cannot install stale bytes; cancelled/shutdown work cannot publish later.
- [ ] Saving an edit immediately after importing/selecting a Look embeds the correct bytes. Reopen the package after removing the external fixture and verify the Look still resolves with the same signature/pixels contract.
- [ ] A generated unreadable Look fixture does not prevent other valid Looks from being installed according to the existing failure policy.
- [ ] Tests cover slow A/fast B completion ordering and shutdown deterministically, without large files, real removable disks, or wall-clock performance thresholds.
- [ ] AppViewModel stays within the existing line-count ceiling and Swift 6 compilation introduces no opt-outs or diagnostics.

## Verification

Run `swift build`, `swift test --no-parallel --filter 'LUTWorkflowTests|EditDocumentStoreTests|PortableLibraryPackageTests|PackageSettingsTests'`, the new collaborator suite if separate, `dg validate`, and `git diff --check`. Required evidence is structural and deterministic; do not run last-known-frame or other display-bound release capture scripts.
## Repository and workflow constraints

- Read `CLAUDE.md` and `.dg/AGENTS.md` before implementation. Target macOS 26+ on Apple Silicon, Swift 6, and Apple frameworks only. Keep the zero-opt-out concurrency contract: no `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
- Claim this issue before changing code. Preserve unrelated working-tree changes. Work on the current branch, commit only coherent issue work with this issue ID in the subject, and hand off to `review` according to `.dg/AGENTS.md`.
- Use generated temporary fixtures and deterministic synchronization. Do not run display-bound release capture benchmarks for these fixes. Product implementations belong in `Sources/KromoraKit`, not the launchers or Xcode packaging target.
- Review evidence was collected on 2026-10-12 using Xcode 27 / Swift 6.4. The combined existing `PackagePathTests|DeriveCoordinatorTests|PhotosDeliveryTests|AnalysisValueTypesTests` selection passed 24 tests, but those green results do not cover the defects described here. Do not treat them as regression coverage for the new behavior.


### Comment — codex @ 2026-10-12T17:12:21.502Z

The 2026-10-12 focused AppViewModel review reconfirmed configureEmbeddedLooks as the embedded-Look I/O finding. Reuse this ticket rather than creating a duplicate. Its scope includes off-main reads, snapshot generation/shutdown ownership and ordering against durable edit writes. The related observation-only library/settings cleanup is KRMA-908; neither ticket may weaken the other boundary.


### Comment — claude @ 2026-10-12T19:45:31.760Z

Embedded Look bytes now load via EmbeddedLookLoader (@concurrent) from EditDocumentStore.loadEmbeddedLooks, holding security scopes for the read. Generation-fenced (latest wins), cancelled at shutdown, and save awaits the pending load. Tests in EmbeddedLookLoaderTests; related suites pass (60).

## Agent log

- 2026-10-12T19:55:56.479Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Actual Look file reads run off the main actor, proven with an injected reader/executor assertion. (pass) — EmbeddedLookLoader uses @concurrent; the injected reader records the thread and the test confirms a main-actor sentinel runs while the reader is blocked.
- [x] A slow worker does not block an independent main-actor sentinel. (pass) — Deterministic gate test passes.
- [x] Superseded snapshots and library/store replacement cannot install stale bytes; cancelled/shutdown work cannot publish later. (pass) — Generation fencing and cancellation checks prevent stale publication; shutdown now awaits the canceled worker task before returning.
- [x] Saving immediately after importing/selecting a Look embeds its bytes and the package remains resolvable after the external fixture is removed. (pass) — Store save awaits the pending load; the package round-trip test removes the source file and verifies the persisted content signature.
- [x] An unreadable Look does not prevent other valid Looks from being installed. (pass) — Generated unreadable and valid Look fixture test passes.
- [x] Slow A/fast B completion ordering and shutdown cancellation are deterministic without wall-clock performance thresholds. (pass) — Generation ordering uses gated readers; cancellation test awaits the canceled task after releasing its gate. Shutdown awaits the returned worker task.
- [x] AppViewModel stays within its line-count ceiling and Swift 6 compilation has no opt-outs or diagnostics. (pass) — PackageSettingsTests checks the AppViewModel ceiling and concurrency escape hatches; swift build completed without diagnostics.
Checks run:
- swift build (passed)
- swift test --no-parallel --filter LUTWorkflowTests|EditDocumentStoreTests|PortableLibraryPackageTests|PackageSettingsTests (30 tests passed before verification fix)
- swift test --no-parallel --filter EmbeddedLookLoaderTests plus requested related suites (35 tests passed after verification fix)
- dg validate (OK; pre-existing model-name warnings in other project records)
- git diff --check (passed)
Findings:
- None
Fixes:
- Made shutdown await cancellation of embedded Look loading and completion of its worker task, closing a late-publication window.
- Replaced the cancellation test sleep with a deterministic await of the canceled task.
Verification commits:
- 540b044e
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV5O5XI0A9C3RRB9
Summary: Verification passed. Embedded Look loading is off-main with ordered durable writes; shutdown now awaits cancellation and worker completion. Checks passed; no remaining findings.
