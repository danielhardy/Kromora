---
id: KRMA-897
title: Reject invalid mask dimensions without overflowing during decoding
type: bug
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The exact Int.max-by-2 JSON reproduction throws recoverably without trapping or allocating a huge buffer.
      result: pass
      notes: The XCTest decoder regression for Int.max × 2 throws normally.
    - criterion: Direct construction and decoding reject zero dimensions, negative dimensions, negative-by-negative dimensions, count mismatches, and overflow.
      result: pass
      notes: Direct-construction and decode regression cases pass.
    - criterion: Positive dimensions with the correct count still normalize values and calculate coverage/isBinary identically; 1-by-N and N-by-1 masks remain supported.
      result: pass
      notes: Normalization, coverage, binary metadata, and single-row/column tests pass.
    - criterion: A generated malformed legacy inline MaskStore entry returns nil from pixel loading without crashing; valid legacy inline and current binary entries still load.
      result: pass
      notes: Malformed legacy entry returns nil; legacy inline loading and binary sidecar round-trip tests pass.
    - criterion: Tests need no large allocations. After the fix, the overflow regression should run normally in XCTest and assert an error; avoid making expected-crash behavior the permanent assertion.
      result: pass
      notes: Overflow regression is an ordinary XCTest throwing assertion and allocates no large pixel buffer.
  checks_run:
    - swift build — passed (exit 0)
    - swift test --filter 'RegionMaskTests|MaskRefinementTests|LocalMaskTests' — passed (38 tests, 0 failures; exit 0)
    - dg validate — passed (OK; existing model-name warnings; exit 0)
    - git diff --check — passed (exit 0)
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-12T19:47:04.727Z
  session: 01MV5NWFOWVIHHAC8X
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - swift
  - masking
  - robustness
  - correctness
created: 2026-10-12T16:38:01.908Z
updated: 2026-10-12T19:47:04.730Z
blockers: []
order: zq
board: product
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/Models/PhotoAnalysis/RegionMask.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/RegionMaskTests.swift
      access: write
      confidence: 1
  observed:
    paths: []
    captured_at: 2026-10-12T19:41:45.105Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Turn malformed decoded mask dimensions into a recoverable validation error/cache miss instead of an arithmetic process trap.

## Confirmed reproduction and impact

`NormalizedMask.init(size:values:)` in `Models/PhotoAnalysis/RegionMask.swift:174-175` currently checks `values.count == size.width * size.height`. `PixelDimensions` is a typealias for `PhotoPixelDimensions` (`Models/PhotoAsset.swift`), whose width/height are unvalidated `Int` values, including on decode. The multiplication executes before the throwing count check can reject the payload.

The review linked a standalone probe against the current KromoraKit build and called:

```swift
let data = Data(#"{"size":{"width":9223372036854775807,"height":2},"values":[]}"#.utf8)
_ = try JSONDecoder().decode(NormalizedMask.self, from: data)
```

On Apple Silicon this terminated with signal 5 (subprocess exit -5), rather than throwing. A `try?` around this decode does not catch integer overflow. The persisted legacy inline-pixel path in `MaskStore.pixels(for:)` also calls this initializer, so malformed cache dimensions can hit this boundary. Current binary sidecar checks already use reporting-overflow arithmetic and are a useful implementation reference.

## Context to read

- `Sources/KromoraKit/Models/PhotoAnalysis/RegionMask.swift`: validating/trusting initializers and custom Codable implementation for `NormalizedMask`.
- `Sources/KromoraKit/Models/PhotoAsset.swift`: `PhotoPixelDimensions` and the `PixelDimensions` alias. Do not impose new global photo-metadata constraints to solve a mask-local defect.
- `Sources/KromoraKit/Models/PhotoAnalysis/MaskStore.swift`: legacy inline values, current sidecar validation, and the cache-miss contract.
- `Tests/KromoraKitTests/RegionMaskTests.swift` and `Tests/KromoraKitTests/Support/MaskStoreTestSupport.swift`: existing masks and cache fixtures.

## Implementation guidance

1. At the validating mask boundary require positive width and height, then use `width.multipliedReportingOverflow(by: height)`. Reject overflow or mismatched count with an existing suitable `RegionMaskError` (prefer `invalidPixelCount` over a new error hierarchy).
2. Perform checks before reserving/copying storage or indexing pixels. Reject negative/zero dimensions, including negative-by-negative dimensions whose product would otherwise equal a small values count.
3. Preserve normal clipping of finite values into [0, 1], rejection of non-finite values, and derived coverage/isBinary behavior.
4. Keep `trustingSize` an internal producer-only path; if touching its precondition, ensure the check itself cannot overflow. Do not route decoded input through it or weaken it to accept malformed data.
5. Keep the `{size, values}` serialized schema, quality separation, valid legacy inline cache compatibility, and valid current binary sidecars unchanged. Invalid cached payloads should return nil/miss through the existing cache boundary.

## Acceptance criteria

- [ ] The exact Int.max-by-2 JSON reproduction throws recoverably without trapping or allocating a huge buffer.
- [ ] Direct construction and decoding reject zero dimensions, negative dimensions, negative-by-negative dimensions, count mismatches, and overflow.
- [ ] Positive dimensions with the correct count still normalize values and calculate coverage/isBinary identically; 1-by-N and N-by-1 masks remain supported.
- [ ] A generated malformed legacy inline MaskStore entry returns nil from pixel loading without crashing; valid legacy inline and current binary entries still load.
- [ ] Tests need no large allocations. After the fix, the overflow regression should run normally in XCTest and assert an error; avoid making expected-crash behavior the permanent assertion.

## Verification

Run `swift build`, `swift test --filter 'RegionMaskTests|MaskRefinementTests|LocalMaskTests'`, `dg validate`, and `git diff --check`. If a new cache test suite is introduced, include it in the focused command and CI lane audit as appropriate. The pre-fix crash probe must only be run in a child process, never in the shared XCTest runner.
## Repository and workflow constraints

- Read `CLAUDE.md` and `.dg/AGENTS.md` before implementation. Target macOS 26+ on Apple Silicon, Swift 6, and Apple frameworks only. Keep the zero-opt-out concurrency contract: no `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
- Claim this issue before changing code. Preserve unrelated working-tree changes. Work on the current branch, commit only coherent issue work with this issue ID in the subject, and hand off to `review` according to `.dg/AGENTS.md`.
- Use generated temporary fixtures and deterministic synchronization. Do not run display-bound release capture benchmarks for these fixes. Product implementations belong in `Sources/KromoraKit`, not the launchers or Xcode packaging target.
- Review evidence was collected on 2026-10-12 using Xcode 27 / Swift 6.4. The combined existing `PackagePathTests|DeriveCoordinatorTests|PhotosDeliveryTests|AnalysisValueTypesTests` selection passed 24 tests, but those green results do not cover the defects described here. Do not treat them as regression coverage for the new behavior.


### Comment — claude @ 2026-10-12T19:41:44.598Z

NormalizedMask.init now requires positive dimensions and uses multipliedReportingOverflow before the count check; trustingSize precondition is overflow-safe. Added tests for direct/decoded invalid dimensions, 1xN/Nx1 masks, and a malformed legacy MaskStore entry returning nil. swift build and the focused RegionMask/MaskRefinement/LocalMask tests pass (38); git diff --check clean.

## Agent log

- 2026-10-12T19:47:04.727Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The exact Int.max-by-2 JSON reproduction throws recoverably without trapping or allocating a huge buffer. (pass) — The XCTest decoder regression for Int.max × 2 throws normally.
- [x] Direct construction and decoding reject zero dimensions, negative dimensions, negative-by-negative dimensions, count mismatches, and overflow. (pass) — Direct-construction and decode regression cases pass.
- [x] Positive dimensions with the correct count still normalize values and calculate coverage/isBinary identically; 1-by-N and N-by-1 masks remain supported. (pass) — Normalization, coverage, binary metadata, and single-row/column tests pass.
- [x] A generated malformed legacy inline MaskStore entry returns nil from pixel loading without crashing; valid legacy inline and current binary entries still load. (pass) — Malformed legacy entry returns nil; legacy inline loading and binary sidecar round-trip tests pass.
- [x] Tests need no large allocations. After the fix, the overflow regression should run normally in XCTest and assert an error; avoid making expected-crash behavior the permanent assertion. (pass) — Overflow regression is an ordinary XCTest throwing assertion and allocates no large pixel buffer.
Checks run:
- swift build — passed (exit 0)
- swift test --filter 'RegionMaskTests|MaskRefinementTests|LocalMaskTests' — passed (38 tests, 0 failures; exit 0)
- dg validate — passed (OK; existing model-name warnings; exit 0)
- git diff --check — passed (exit 0)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV5NWFOWVIHHAC8X
Summary: Independent verification passed; focused build and tests, DispatchGraph validation, and diff check are clean.
