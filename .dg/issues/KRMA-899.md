---
id: KRMA-899
title: Preserve normalized analysis invariants when decoding cached Codable values
type: bug
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: ToneStatistics and NormalizedRect mutated JSON decode to the values their validated initializers produce.
      result: pass
    - criterion: Mutated JSON tests cover below-zero and above-one statistics, confidence, RGB components, points, and rectangles.
      result: pass
    - criterion: LuminanceDistribution decoding preserves linear and perceptual semantic roles.
      result: pass
    - criterion: Valid persisted values retain their serialized schema and PhotoAnalysis optional-field compatibility remains intact.
      result: pass
      notes: Synthesized Encodable remains in use; PhotoAnalysis decoding keeps its existing decodeIfPresent fallbacks.
    - criterion: Altered nested cache facts normalize on read, while malformed shapes/types produce a cache miss.
      result: pass
    - criterion: No Auto behavior changes for valid analysis values.
      result: pass
  checks_run:
    - swift build (exit 0)
    - swift test targeted analysis/cache suite (46 tests, exit 0)
    - dg validate (exit 0; existing agent-model warnings)
    - git diff --check (exit 0)
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-12T21:41:12.942Z
  session: 01MV5RZWLEWDS9ADGX
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - swift
  - codable
  - analysis
  - robustness
created: 2026-10-12T16:38:03.823Z
updated: 2026-10-12T21:41:12.948Z
blockers: []
order: zzx
board: product
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/Models/PhotoAnalysis/AnalysisValueTypes.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/Models/PhotoAnalysis/AnalysisImage.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysis.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/Models/PhotoAnalysis/RegionMask.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/Models/PhotoAnalysis/PrimarySubjectSelector.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/AnalysisValueTypesTests.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/AnalysisImageTests.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/PhotoAnalysisCacheTests.swift
      access: write
      confidence: 1
  observed:
    paths: []
    captured_at: 2026-10-12T21:13:59.709Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Make persisted analysis decoding enforce the same normalized coordinate/statistics invariants as direct construction. Validly shaped JSON must not bypass clamps simply because Swift synthesized `init(from:)`.

## Confirmed reproduction and impact

`ToneStatistics` (`AnalysisValueTypes.swift:12`) clamps all scalar facts through `finiteUnit` in its convenience initializer. `NormalizedPoint` and `NormalizedRect` (`AnalysisImage.swift:5,32`) similarly enforce finite unit-square geometry. These types have synthesized Decodable implementations, which assign stored properties directly rather than invoking those initializers.

The review linked a probe against the current KromoraKit build. It encoded `ToneStatistics()`, modified JSON `mean` to 7 and `shadowClippingFraction` to -2, then decoded it. Direct construction produced mean 1; decoding preserved mean 7 and clipping -2. Decoding the following also preserved every invalid field:

```json
{"x":-5,"y":2,"width":10,"height":-4}
```

`PhotoAnalysisCache.analysis(for:)` checks successful decoding, key equality, and version; it does not validate nested numeric invariants afterward. These values can therefore enter Auto/region policy as cached facts even though normal producers cannot construct them that way. This is a malformed-data robustness finding, not a claim that ordinary encoder output is corrupt.

## Scope and context to read

Required bounded types for this ticket:

- `Models/PhotoAnalysis/AnalysisImage.swift`: `NormalizedPoint`, `NormalizedRect`.
- `Models/PhotoAnalysis/AnalysisValueTypes.swift`: `ToneStatistics`, `LuminanceDistribution` (including canonical linear/perceptual variant handling), `ChannelClipping`, `ColorStatistics`, `AnalysisQuality`.
- `Models/PhotoAnalysis/PhotoAnalysis.swift`: `AnalyzedRegion`; inspect the existing `PhotoAnalysis.init(from:)` to preserve older optional-field behavior.
- `Models/PhotoAnalysis/RegionMask.swift`: `RegionMask` confidence/coverage. Leave `NormalizedMask` arithmetic to the separate overflow issue from this review; these are independent fixes even though they share a file.
- `Models/PhotoAnalysis/PrimarySubjectSelector.swift`: `PrimarySubjectSelection` confidence.
- `Models/PhotoAnalysis/PhotoAnalysisCache.swift`: persisted read boundary and cache-miss behavior.
- `Tests/KromoraKitTests/AnalysisValueTypesTests.swift`, `AnalysisImageTests.swift`, `RegionMaskTests.swift`, and `PhotoAnalysisCacheTests.swift`.

This is not a request to rewrite every Codable type, change Auto scoring policy, or add new schema migrations.

## Implementation guidance

1. Add explicit keyed `init(from:)` implementations for the required invariant-bearing types, routing decoded values through their existing validating initializers. Reuse existing clamp/default behavior rather than creating a second policy.
2. Preserve existing serialized property names, enum values, optionality, and which fields are required. Do not introduce broad `decodeIfPresent` defaults that turn unrelated malformed/incomplete JSON into valid cache entries.
3. Keep valid persisted values and round trips unchanged. Continue to let malformed type/shape JSON throw so PhotoAnalysisCache can return a miss. For finite out-of-range numeric inputs, normalize exactly as direct construction does.
4. Preserve rectangle containment after clamping origins (width <= 1 - x, height <= 1 - y) and the existing non-finite fallback semantics. Preserve LuminanceDistribution's enforced `.linear`/`.perceptual` roles through its initializer.
5. Keep synthesized Encodable where it correctly preserves the schema; avoid needless manual encoding. No new dependency, persisted format version bump, or concurrency opt-out should be necessary.

## Acceptance criteria

- [ ] The demonstrated ToneStatistics and NormalizedRect JSON payloads decode to the same values their existing validated initializers produce.
- [ ] Table-driven mutated-JSON tests cover below-zero and above-one inputs for required scalar/confidence fields, RGB vector components, points, and rectangles.
- [ ] LuminanceDistribution decoding cannot swap the semantic variant of its linear and perceptual entries.
- [ ] Valid fixtures round-trip without field/schema changes; existing PhotoAnalysis optional-field compatibility tests remain green.
- [ ] A generated persisted PhotoAnalysisCache entry with altered nested statistics/bounds yields normalized facts on read; malformed shapes/types still produce a cache miss. Exercise the cache boundary, not only individual struct decoding.
- [ ] No new Auto algorithm behavior is introduced for already-valid analysis values.

## Verification

Run `swift build`, `swift test --filter 'AnalysisValueTypesTests|AnalysisImageTests|RegionMaskTests|PhotoAnalysisCacheTests|PhotoAnalysisAssemblyTests|PrimarySubjectSelectorTests'`, `dg validate`, and `git diff --check`. Use JSONSerialization mutation of an encoded valid fixture when it avoids hard-coding large schemas; do not rely only on valid-value round-trip tests, which are exactly what missed this defect.
## Repository and workflow constraints

- Read `CLAUDE.md` and `.dg/AGENTS.md` before implementation. Target macOS 26+ on Apple Silicon, Swift 6, and Apple frameworks only. Keep the zero-opt-out concurrency contract: no `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
- Claim this issue before changing code. Preserve unrelated working-tree changes. Work on the current branch, commit only coherent issue work with this issue ID in the subject, and hand off to `review` according to `.dg/AGENTS.md`.
- Use generated temporary fixtures and deterministic synchronization. Do not run display-bound release capture benchmarks for these fixes. Product implementations belong in `Sources/KromoraKit`, not the launchers or Xcode packaging target.
- Review evidence was collected on 2026-10-12 using Xcode 27 / Swift 6.4. The combined existing `PackagePathTests|DeriveCoordinatorTests|PhotosDeliveryTests|AnalysisValueTypesTests` selection passed 24 tests, but those green results do not cover the defects described here. Do not treat them as regression coverage for the new behavior.


### Comment — claude @ 2026-10-12T21:13:56.137Z

Added validating init(from:) for NormalizedPoint/Rect, ToneStatistics, LuminanceDistribution, ChannelClipping, ColorStatistics, AnalysisQuality, AnalyzedRegion, RegionMask, PrimarySubjectSelection. Mutated-JSON and cache-boundary tests added; targeted suite passes (46 tests).

## Agent log

- 2026-10-12T21:41:12.942Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] ToneStatistics and NormalizedRect mutated JSON decode to the values their validated initializers produce. (pass)
- [x] Mutated JSON tests cover below-zero and above-one statistics, confidence, RGB components, points, and rectangles. (pass)
- [x] LuminanceDistribution decoding preserves linear and perceptual semantic roles. (pass)
- [x] Valid persisted values retain their serialized schema and PhotoAnalysis optional-field compatibility remains intact. (pass) — Synthesized Encodable remains in use; PhotoAnalysis decoding keeps its existing decodeIfPresent fallbacks.
- [x] Altered nested cache facts normalize on read, while malformed shapes/types produce a cache miss. (pass)
- [x] No Auto behavior changes for valid analysis values. (pass)
Checks run:
- swift build (exit 0)
- swift test targeted analysis/cache suite (46 tests, exit 0)
- dg validate (exit 0; existing agent-model warnings)
- git diff --check (exit 0)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV5RZWLEWDS9ADGX
Summary: Verification passed: cached analysis decoding normalizes invariant-bearing values; all declared checks passed.
