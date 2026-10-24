---
id: KRMA-953
title: 'Replace 21 per-byte String(format: "%02x") hex encoders with one fast helper'
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: One shared lowercase hex helper uses an allocation-light implementation without per-byte String(format:) or map/join.
      result: pass
      notes: Models/HexEncoding.swift encodes through String(unsafeUninitializedCapacity:); the randomized reference test passed.
    - criterion: Existing duplicate encoders are removed or delegate to the helper, and all source call sites use it except the allowed shard-list formatter.
      result: pass
      notes: Source scan finds only PortableLibraryPackage.swift allShards formatting at line 614.
    - criterion: A trusted reference comparison covers 1,000 random byte arrays of length 0...64 plus the empty array.
      result: pass
      notes: HexEncodingTests.testHexStringMatchesReferenceForRandomBytes ran in the fast lane; an explicit lowercase and no-separator case is also covered.
    - criterion: Hex output remains byte-for-byte identical, lowercase, and separator-free; existing tests pass.
      result: pass
      notes: The helper tests and full fast lane passed on the final run.
    - criterion: swift build is warning-free and Swift 6 remains clean without concurrency opt-outs or availability branches.
      result: pass
      notes: swift build completed with no warnings; the helper change adds no concurrency opt-outs or availability branches.
    - criterion: scripts/ci-tests.sh fast exits 0, with the documented handling for the known StoredEditAdoption test.
      result: pass
      notes: The third full fast-lane run exited 0. Two earlier runs hit the unrelated EditPersistenceIntegrationTests.testLongGestureCheckpointsIntermediateSnapshotsBeforeMouseUp timing assertion; its isolated rerun passed. This intermittent test issue is already tracked by KRMA-1027.
  checks_run:
    - swift build — exit 0; build completed without warnings.
    - scripts/ci-tests.sh fast — initial run exit 1 on EditPersistenceIntegrationTests.testLongGestureCheckpointsIntermediateSnapshotsBeforeMouseUp timing assertion.
    - swift test --filter EditPersistenceIntegrationTests/testLongGestureCheckpointsIntermediateSnapshotsBeforeMouseUp — exit 0; isolated rerun passed.
    - scripts/ci-tests.sh fast — second run exit 1 on the same timing assertion.
    - scripts/ci-tests.sh fast — final run exit 0.
    - 'Source scan for String(format: "%02x") — only the allowed allShards formatter remains at PortableLibraryPackage.swift:614.'
  findings:
    - The long-gesture checkpoint assertion intermittently fails under the parallel fast lane but passes alone; it is already tracked by verification ticket KRMA-1027.
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-15T06:31:59.351Z
  session: 01MV95FR0VJ9H5O1ZG
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - performance
  - cleanup
created: 2026-10-13T14:48:03.715Z
updated: 2026-10-15T06:31:59.354Z
parent: KRMA-922
blockers: []
order: n
board: product
context:
  files: []
  docs:
    - .context/2026-10-14-release-readiness-review.md
  issues:
    - KRMA-994
  commands: []
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-15T06:16:50.924Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Hex-encode digests with one shared allocation-light helper instead of `String(format:)` per byte.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding S10 (last sentence). `grep -rn 'String(format: "%02x"' Sources` finds ~21
sites, for example `RenderCacheKey.swift:154` (`RenderCacheHash.digest(_ data:)`, on the hot render
path), `PreviewPresentationCoordinator.swift:282`, `OriginalSettingsBundle.swift:113`,
`CubeLUT.swift:128,606`, `PortablePhotoIdentity.swift:136`, `LibraryMembershipMatcher.swift:41,59`,
`PhotoAsset.swift:83`, `LatestPreviewFrameStore.swift:312`, `Observability.swift:241,383`,
`PhotoAnalysis/{CurrentEditMeasurement,MaskStore,PhotoAnalysisCache}.swift`, and three existing
`hexString`/`portableHexString` extensions on `Sequence`/`Data`
(`PortablePackageTransaction.swift:1168`, `PortableLibraryValidation.swift:887`,
`PortableLibraryBackup.swift:749`, `PortablePackageEditSidecar.swift:1005`). Intentional exception:
`PortableLibraryPackage.swift:614` builds the constant 256-entry shard list from `Int`s; it may stay.

## Acceptance criteria

- [ ] One helper (e.g. `extension Sequence where Element == UInt8 { var hexString: String }` or
      `extension SHA256.Digest`) in a shared file, implemented with a lookup table / `String(unsafeUninitializedCapacity:)`
      or `String(decoding:as:)` over a byte buffer (no per-byte `String(format:)`, no
      `map … joined()`).
- [ ] The existing duplicate extensions delegate to it or are deleted; every site above uses it.
      `grep -rn 'String(format: "%02x"' Sources` returns only the allowed shard-list site.
- [ ] A test compares the helper's output to a trusted slow implementation for 1,000 random byte arrays
      of random length 0...64 plus the empty array.
- [ ] Behavior is byte-for-byte identical (lowercase hex, no separators); existing tests pass.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).

## 2026-10-14 review

Finding 11 in `.context/2026-10-14-release-readiness-review.md` still calls out per-byte `String(format:)` hex conversion, including on the render-identity path. This ticket remains only the shared helper. The identity redesign is KRMA-954. Do not change what is hashed. Epic KRMA-994 tracks the finding; this issue stays a child of KRMA-922.


### Comment — claude @ 2026-10-15T06:16:50.392Z

Implemented: Models/HexEncoding.swift helper; all %02x digest sites and 4 duplicate Digest extensions now use it (only allShards shard list and '%02x.pack' filename formatting remain). HexEncodingTests added. swift build warning-free; scripts/ci-tests.sh fast exit 0. Changes left uncommitted in the working tree (shared with unrelated pre-existing edits).

## Agent log

- 2026-10-15T06:31:59.351Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] One shared lowercase hex helper uses an allocation-light implementation without per-byte String(format:) or map/join. (pass) — Models/HexEncoding.swift encodes through String(unsafeUninitializedCapacity:); the randomized reference test passed.
- [x] Existing duplicate encoders are removed or delegate to the helper, and all source call sites use it except the allowed shard-list formatter. (pass) — Source scan finds only PortableLibraryPackage.swift allShards formatting at line 614.
- [x] A trusted reference comparison covers 1,000 random byte arrays of length 0...64 plus the empty array. (pass) — HexEncodingTests.testHexStringMatchesReferenceForRandomBytes ran in the fast lane; an explicit lowercase and no-separator case is also covered.
- [x] Hex output remains byte-for-byte identical, lowercase, and separator-free; existing tests pass. (pass) — The helper tests and full fast lane passed on the final run.
- [x] swift build is warning-free and Swift 6 remains clean without concurrency opt-outs or availability branches. (pass) — swift build completed with no warnings; the helper change adds no concurrency opt-outs or availability branches.
- [x] scripts/ci-tests.sh fast exits 0, with the documented handling for the known StoredEditAdoption test. (pass) — The third full fast-lane run exited 0. Two earlier runs hit the unrelated EditPersistenceIntegrationTests.testLongGestureCheckpointsIntermediateSnapshotsBeforeMouseUp timing assertion; its isolated rerun passed. This intermittent test issue is already tracked by KRMA-1027.
Checks run:
- swift build — exit 0; build completed without warnings.
- scripts/ci-tests.sh fast — initial run exit 1 on EditPersistenceIntegrationTests.testLongGestureCheckpointsIntermediateSnapshotsBeforeMouseUp timing assertion.
- swift test --filter EditPersistenceIntegrationTests/testLongGestureCheckpointsIntermediateSnapshotsBeforeMouseUp — exit 0; isolated rerun passed.
- scripts/ci-tests.sh fast — second run exit 1 on the same timing assertion.
- scripts/ci-tests.sh fast — final run exit 0.
- Source scan for String(format: "%02x") — only the allowed allShards formatter remains at PortableLibraryPackage.swift:614.
Findings:
- The long-gesture checkpoint assertion intermittently fails under the parallel fast lane but passes alone; it is already tracked by verification ticket KRMA-1027.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV95FR0VJ9H5O1ZG
Summary: Verified the shared hex encoder; required build and fast lane pass.
