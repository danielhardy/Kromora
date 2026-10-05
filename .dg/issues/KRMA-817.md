---
id: KRMA-817
title: Make Effects noise reduction show up after other edits
type: bug
status: done
priority: urgent
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Noise reduction under an existing pre-LUT edit changes preview and misses prefix; repeat hits
      result: pass
    - criterion: Sharpening keyed; grain/vignette/crop/LUT still reuse prefix
      result: pass
    - criterion: Zero NR no-op; decoder and local-mask NR unchanged
      result: pass
    - criterion: New cache tests and existing NR/prefix tests green
      result: pass
  checks_run:
    - swift test --filter RenderCacheTests (34 pass)
    - swift test --filter RenderPipelineTests (50 pass)
    - scripts/ci-tests.sh warning-gate
    - scripts/ci-tests.sh fast (1521)
    - git diff --check
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-04T15:46:42.861Z
  session: 01MUTZPNK1O6QUJ7PC
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
created: 2026-10-04T13:16:01.137Z
updated: 2026-10-04T15:46:42.865Z
blockers: []
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/Models/RenderEngine.swift
    - Sources/KromoraKit/Models/RenderPipeline.swift
    - Sources/KromoraKit/Models/EffectsAdjustments.swift
    - Sources/KromoraKit/Models/EffectsControl.swift
    - Sources/KromoraKit/Views/EffectsInspectorView.swift
    - Tests/KromoraKitTests/RenderCacheTests.swift
    - Tests/KromoraKitTests/RenderPipelineTests.swift
  docs:
    - docs/ENGINEERING_GUIDE.md
    - CLAUDE.md
  issues: []
  commands:
    - swift test --filter RenderCacheTests
    - swift test --filter RenderPipelineTests
    - scripts/ci-tests.sh warning-gate
    - scripts/ci-tests.sh fast
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-04T15:42:45.915Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

The Effects inspector's Noise Reduction sliders must change the preview. Luminance NR and Color NR currently appear to do nothing once the photo has any other pre-LUT edit. This is a cache-key bug, not a missing binding.

## Product requirement

Moving Luminance NR or Color NR must change the image on screen, including when exposure, color, texture, clarity, dehaze, or another adjustment is already set. Zero must stay an exact no-op. Detail and Contrast stay as retention controls on the same pass. Do not make the user reset the photo to see noise reduction.

## What is wrong

The sliders are wired. `EffectsInspectorView` binds `DetailControl.luminanceNoise` and `.colorNoise` into `document.effects.detail`. `RenderPipeline.applyDetailControls` runs `CINoiseReduction` when either amount is above zero. `testNoiseReductionReducesLuminanceAndChromaNoiseWithoutLosingTheEdge` already shows that direct call reduces a noisy fixture. The inspector still does nothing because the preview never re-runs that call.

`RenderEngine.buildImage` materializes `buildPreLUTImage` into the processing-prefix cache whenever `hasPreLUTWork` is true. `buildPreLUTImage` includes `applyDetailControls`, so the baked bitmap contains whatever noise reduction and sharpening were set at the miss. The cache key does not. `prefixDocumentHash` digests an `EditDocument` whose effects are only texture, clarity, and dehaze:

```swift
effects: EffectsAdjustments(
    texture: document.effects.texture, clarity: document.effects.clarity,
    dehaze: document.effects.dehaze
)
```

`EffectsAdjustments()` defaults `detail` to neutral. A later Luminance NR or Color NR change produces the same key, hits, and returns the bitmap from the first miss. Grain is correctly left out of this key because grain is applied after the prefix (`testDownstreamOnlyEditsReuseTheCompletedProcessingPrefix`). Detail is inside the prefix. Omitting it is the same class of bug `testRetouchEditMissesTheProcessingPrefixAndChangesPixels` already fixed for spots: the comment there says a value inside the cached prefix needs its own entry.

`hasPreLUTWork` has the same hole. It is true for light, color, texture, clarity, dehaze, and adjustment nodes, and false for detail alone. So:

- Noise reduction on a still-neutral photo skips the cache and can reach the filter.
- Any exposure, color, texture, clarity, dehaze, or adjustment turns the cache on. The first prefix bakes the current detail. Further NR edits hit that entry and the sliders look dead.

That is the normal editing session. Sharpening Amount, Radius, Detail, and Masking, plus Luminance Detail, Luminance Contrast, Color Detail, and Color Contrast, are in the same `DetailAdjustments` value and freeze the same way. Include the whole `detail` value. Do not special-case only the two NR amounts.

## Fix

Include `document.effects.detail` in the document `prefixDocumentHash` digests. Texture, clarity, and dehaze stay. Grain, vignette, crop, and the LUT stay out; they are applied after this prefix.

Make `hasPreLUTWork` true when `detail` is not identity, so a noise-only or sharpen-only edit uses that same keyed cache instead of a side path. An unchanged detail value must still hit.

Do not raise `inputNoiseLevel`, replace `CINoiseReduction`, or retune the blend as the first change. The filter already changes pixels when it is invoked. Do not bump `pixelEpoch` unless a hashed detail value still collides; a new key is enough for the in-memory prefix.

Leave these alone:

- Develop's decoder controls, `RAWDevelopSettings.luminanceNoiseReductionAmount` and `colorNoiseReductionAmount`. Those are `CIRAWFilter` amounts on the developed-source cache, which already hashes `rawDevelop`. They are not the Effects "Luminance NR" / "Color NR" rows.
- Local mask Noise Reduction and Moiré Reduction. Those run in `applyLocalAdjustments` after the prefix, and the post-local key already digests `localAdjustments`.
- `hasSpatialWork`. It only widens zoomed-ROI padding. Do not change it in this fix.

## Tests

Add a regression next to `testRetouchEditMissesTheProcessingPrefixAndChangesPixels` in `Tests/KromoraKitTests/RenderCacheTests.swift`. It must fail on the current key.

- Render through `RenderEngine.makeCGImage` at preview quality, not through `applyDetailControls` alone. The direct pipeline test already passes and does not catch this.
- Give both documents a non-neutral pre-LUT edit such as `LightAdjustments(exposure: 0.4)`, so `hasPreLUTWork` is true today. A noise-only edit on `EditDocument()` skips the cache and can pass without a fix.
- Use a noisy source. `makeSource()` is a smooth gradient; `CINoiseReduction` may leave it unchanged, and `XCTAssertNotEqual` would then fail for the wrong reason. Follow `noisyDetailFixture` in `RenderPipelineTests`, or write a noisy image into the temp directory.
- Luminance NR 0 versus 100: the two previews differ, `processingPrefix.misses == 2`, and `hits == 0`. A third render of the second document hits.
- The same for Color NR 0 versus 100.
- Sharpening Amount 0 versus 100 under the same exposure also misses twice. That locks the whole `detail` value into the key.
- Repeat the grain test: two documents that differ only in grain amount still share one prefix (`misses == 1`, `hits == 1`).
- Keep `testNoiseReductionReducesLuminanceAndChromaNoiseWithoutLosingTheEdge` and the zero-noise identity assertion.

## Acceptance criteria

- [ ] With exposure or another pre-LUT edit already applied, moving Luminance NR or Color NR changes the preview pixels and misses the processing prefix. Repeating the same value hits.
- [ ] Sharpening is in the same key, so a sharpening-only change under an existing pre-LUT edit also misses. Grain, vignette, crop, and LUT still reuse the prefix.
- [ ] Zero noise reduction remains an exact no-op. Decoder NR and local-mask NR are unchanged.
- [ ] The new cache test fails before the hash change and passes after it. Existing noise-reduction pipeline tests and `testDownstreamOnlyEditsReuseTheCompletedProcessingPrefix` stay green.

## Verification

Deterministic tests only. Do not run `scripts/run-kromora-capture.sh`. Before handoff: `swift test --filter RenderCacheTests`, `swift test --filter RenderPipelineTests`, `scripts/ci-tests.sh warning-gate`, `scripts/ci-tests.sh fast`, `swift format lint` on changed Swift files, `git diff --check`, and `dg validate`.

Commit on the current branch with a subject that starts `KRMA-817:`. Do not push. Do not stash, reset, or revert unrelated working-tree changes. Hand off to `review` with a short comment. Do not mark the issue done.


### Comment — codex @ 2026-10-04T15:42:45.454Z

Included Effects detail in the processing-prefix key and enabled keyed caching for detail-only edits. Added end-to-end preview regressions for luminance NR, color NR, sharpening, cache hits, and downstream grain reuse. Verification passed: RenderCacheTests (34), RenderPipelineTests (50), warning-gate, fast lane (1,521), git diff --check, and dg validate. swift format lint reports existing warnings elsewhere in the files, with none in edited sections. Commit: 5ec1acac.

## Agent log

- 2026-10-04T15:46:42.861Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Noise reduction under an existing pre-LUT edit changes preview and misses prefix; repeat hits (pass)
- [x] Sharpening keyed; grain/vignette/crop/LUT still reuse prefix (pass)
- [x] Zero NR no-op; decoder and local-mask NR unchanged (pass)
- [x] New cache tests and existing NR/prefix tests green (pass)
Checks run:
- swift test --filter RenderCacheTests (34 pass)
- swift test --filter RenderPipelineTests (50 pass)
- scripts/ci-tests.sh warning-gate
- scripts/ci-tests.sh fast (1521)
- git diff --check
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUTZPNK1O6QUJ7PC
