---
id: KRMA-953
title: 'Replace 21 per-byte String(format: "%02x") hex encoders with one fast helper'
type: task
status: backlog
priority: low
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - performance
  - cleanup
parent: KRMA-922
created: 2026-10-13T14:48:03.715Z
updated: 2026-10-13T14:48:21.945Z
blockers: []
order: zr
board: product
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
