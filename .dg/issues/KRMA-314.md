---
id: KRMA-314
title: "KRMA-301 verification follow-up: strengthen preview-decode test coverage to match acceptance criteria"
type: task
status: done
priority: low
verification_agent: pi
verification_model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Orientation parity compares preview and filmstrip pixels for orientations 2, 3, and 6 with a recorded per-byte delta tolerance; HEIC is exercised when the runner can encode it.
      result: pass
    - criterion: Full-resolution standard decode pixels match the pre-change CIImage(contentsOf:) reference exactly.
      result: pass
    - criterion: RenderPipeline non-full decode with zero nativeExtent uses the fallback path for valid input and rejects corrupt input cleanly.
      result: pass
  checks_run:
    - swift build — passed; existing Core Image deprecation warnings only
    - swift test --disable-sandbox --filter RenderPipelineTests — 38 executed, 2 expected RAW skips, 0 failures
    - swift test --disable-sandbox --filter RenderPipelineTests.testPreviewDecodeBakesOrientationLikeTheFilmstrip|RenderPipelineTests.testPreviewDecodeExtentMatchesPlannerAndFullRemainsNative|RenderPipelineTests.testPreviewDecodeWithZeroDimensionNativeExtentUsesFallbackAndRejectsCorruptInput — 3 passed
    - git diff --check — passed
  findings: []
  fixes: []
  verification_commits:
    - 217692b09a882cb319ee3163fb1dfb38de943562
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-09T17:10:21.520Z
  session: 01MTUCOPB7JK9APFWZ
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - perf
  - decode
created: 2026-09-09T08:32:27.852Z
updated: 2026-09-10T12:53:55.933Z
parent: KRMA-301
order: x7c
board: product
commits:
  - 217692b09a882cb319ee3163fb1dfb38de943562
---

## Objective

KRMA-301 (`0248c50`) implemented ImageIO thumbnail decoding for standard-image previews and is
functionally sound (verified: `swift build` clean, `ci-tests.sh fast`/`serial` green modulo two
pre-existing unrelated failures — `LUTWorkflowTests` flaky counter assertion and dirty
uncommitted `PreviewCutoverTests.swift` from KRMA-300 — neither touched by this change). But the
tests it added satisfy the *spirit* of the acceptance criteria, not the letter, in three places.
None of these are believed to hide an actual bug (traced by hand below); this ticket is to close
the coverage gap.

## Gaps vs. KRMA-301 acceptance criteria

1. **`OrientationParityTest`** (KRMA-301 AC #2) asked for canvas-preview vs. filmstrip-thumbnail
   pixels compared with a per-pixel delta threshold, plus a HEIC fixture. The added test
   (`testPreviewDecodeBakesOrientationLikeTheFilmstrip`, `RenderPipelineTests.swift`) only compares
   `CIImage.extent` width/height between the two paths, using EXIF orientation 6 (a 90° rotation,
   which changes the extent's aspect ratio). An orientation whose transform does not change the
   extent's aspect ratio — e.g. orientation 2 (horizontal mirror) or 3 (180° rotation) — would pass
   this test even if `kCGImageSourceCreateThumbnailWithTransform` and
   `ImageDecoder.orientedLoadOptions` disagreed on the mirror/rotation direction. No HEIC fixture is
   exercised at all.
2. **`FullResUnchangedTest`** (KRMA-301 AC #3) asked for `.full`/export output bytes/pixels to
   equal the pre-change `CIImage(contentsOf:)` reference exactly. The added assertion
   (`testPreviewDecodeExtentMatchesPlannerAndFullRemainsNative`) only checks
   `full.extent.size == nativeExtent`. This is low-risk since the `.full` branch is code that
   `developedSource` already ran before this change (the new `previewStandardImage` call is gated
   on `!scale.isFull`), but the acceptance criterion's literal byte-for-byte check was never added.
3. **`CorruptInputTest`** (KRMA-301 AC #4) asked for zero-dimension inputs to throw
   `ImageError.cannotLoad`. The added test only covers a truncated JPEG through
   `ImageDecoder.load`. A zero-dimension `nativeExtent` on the new `RenderPipeline` preview path
   was traced by hand: `validSourceSize` rejects `width/height < 1` and returns `nil`, so
   `previewStandardImage` falls back to the pre-existing `standardImage(for:)` path — the same
   place `ImageError.cannotLoad` would already be thrown from at the `ImageDecoder` layer — but no
   test pins that fallback for the new code path specifically.

## Scope

- Extend `testPreviewDecodeBakesOrientationLikeTheFilmstrip` (or add a new test) to do a
  pixel-level comparison (resampled to a common size, with a recorded delta tolerance) rather than
  extent-only, and add orientation values whose transform doesn't change the aspect ratio (2, 3).
  Add a HEIC fixture if `Fixtures.swift` can produce one on CI's runner.
- Add a byte/pixel-exact comparison for `.full` against the pre-change `CIImage(contentsOf:)` call
  (can call it directly in the test rather than reverting the production code).
- Add a `RenderPipeline`-level (not just `ImageDecoder`-level) test that a zero-dimension
  `nativeExtent` on a non-full scale still resolves to `nil`/throws through the fallback path.

## Out of scope

No production code change is expected — this is closing a test-coverage gap identified during
counterpoint verification, not a correctness fix.

## Objective

KRMA-301 verification follow-up: strengthen preview-decode test coverage to match acceptance criteria

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ]

## Implementation notes

<!-- Approach, constraints, links -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-09T17:10:21.520Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Orientation parity compares preview and filmstrip pixels for orientations 2, 3, and 6 with a recorded per-byte delta tolerance; HEIC is exercised when the runner can encode it. (pass)
- [x] Full-resolution standard decode pixels match the pre-change CIImage(contentsOf:) reference exactly. (pass)
- [x] RenderPipeline non-full decode with zero nativeExtent uses the fallback path for valid input and rejects corrupt input cleanly. (pass)
Checks run:
- swift build — passed; existing Core Image deprecation warnings only
- swift test --disable-sandbox --filter RenderPipelineTests — 38 executed, 2 expected RAW skips, 0 failures
- swift test --disable-sandbox --filter RenderPipelineTests.testPreviewDecodeBakesOrientationLikeTheFilmstrip|RenderPipelineTests.testPreviewDecodeExtentMatchesPlannerAndFullRemainsNative|RenderPipelineTests.testPreviewDecodeWithZeroDimensionNativeExtentUsesFallbackAndRejectsCorruptInput — 3 passed
- git diff --check — passed
Findings:
- None
Fixes:
- None
Verification commits:
- 217692b09a882cb319ee3163fb1dfb38de943562
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTUCOPB7JK9APFWZ
Summary: Strengthened preview decode verification with pixel-level orientation parity, optional HEIC coverage, exact full-resolution identity, and zero-dimension fallback/corrupt-input coverage.
