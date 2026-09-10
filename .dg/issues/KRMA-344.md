---
id: KRMA-344
title: Add scene classification evidence and per-signal confidence for Auto
type: feature
status: done
priority: high
agent: pi
model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Scene classification is optional and unavailable APIs/failures are represented as missing evidence, not fatal analysis errors.
      result: pass
      notes: VisionSceneClassifier returns nil on unsupported revision, undecodable image, request error, or cancellation; PhotoAnalysisCoordinator treats nil as evidence reduction only.
    - criterion: Night, sunset/warm light, snow/high-key, fog, backlight, monochrome, and mixed-light fixtures produce evidence with confidence and no fixed scene preset.
      result: pass
      notes: 19 SceneEvidenceTests assert independent continuous likelihoods per fixture; backlight/high/low-key retained from prior work; mixed-light correctly stays 0 without pixel-correlated hue evidence.
    - criterion: Confidence is reported separately for global tone, color/neutral, scene, subject/regions, detail, and each semantic provider used by Auto.
      result: pass
      notes: AutoSignalConfidence + SemanticProviderConfidence expose independent fields; verified by testFullSignalsReportHighOverallAndPerProviderEvidence and testMissingSignalsReduceOverallWithoutErasingUsableMeasurements.
    - criterion: Conflicting or missing signals reduce confidence and correction strength predictably; they do not invent a white balance or mask.
      result: pass
      notes: Label/physics disagreement scales sceneConfidence x0.6; missing labels/regions apply fixed penalties; no slider or mask values are produced anywhere in this change (facts-only, verified by grep and by non-goals check).
    - criterion: Existing PhotoAnalysis/cache versioning remains backward-compatible with neutral defaults for older cached values.
      result: pass
      notes: Custom Codable on SceneCharacteristics and PhotoAnalysis decodeIfPresent every new field; AnalysisVersion.current unchanged; testLegacySceneJSONDecodesToNeutralDefaults and testLegacyAnalysisJSONDecodesWithDerivedConfidenceAndSameVersion pass.
    - criterion: "Focused tests assert evidence ranges and degradation behavior on synthetic fixtures and on #available-guarded unsupported paths."
      result: pass
      notes: "SceneEvidenceTests.swift: 19/19 green, including stub-classifier and undecodable-source adapter paths."
  checks_run:
    - swift build (clean, only pre-existing unrelated deprecation warnings)
    - swift test --filter SceneEvidenceTests (19/19 passed)
    - scripts/ci-tests.sh fast (748/748 passed)
    - scripts/ci-tests.sh serial (328/328 passed, including PhotoIntelligenceCorpusTests self-consistency)
    - git diff --check (clean)
    - grep for @unchecked Sendable / nonisolated(unsafe) / @preconcurrency in changed files (none found)
  findings:
    - PhotoAnalysis's custom Decodable init decoded AnalysisQuality twice (once inline to derive globalToneAvailable for signalConfidence, once again for self.quality) - harmless but redundant; fixed inline as a localized change.
  fixes:
    - "Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysis.swift: decode AnalysisQuality once in init(from:) and reuse it for both signalConfidence derivation and self.quality."
  verification_commits:
    - 955f1c53e526f2e10dd8e710a76fe460f2ba6a80
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-10T18:53:20.339Z
  session: 01MTVVPANUWB3TUVO3
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - auto
  - analysis
  - vision
created: 2026-09-10T14:40:04.363Z
updated: 2026-09-10T18:53:20.341Z
depends_on:
  - KRMA-343
  - KRMA-181
order: a0
board: product
commits:
  - 955f1c53e526f2e10dd8e710a76fe460f2ba6a80
---

## Parent epic

KRMA-341 — Content-aware Auto engine and renderer-backed candidate evaluation.


## Objective

Strengthen Auto's interpretation of the measured photograph without turning scene labels into fixed presets. Combine existing semantic signals with Vision scene classification and expose independent confidence for every usable signal.

## Scope

- Add an internal scene-evidence value that can represent night, sunset/warm illumination, snow/high-key, fog/low-contrast, backlighting, monochrome/low-color, mixed light, and ordinary daylight as evidence with confidence rather than a hard preset.
- Use Vision scene classification where available, behind the existing Apple-only adapter and deployment guards. Keep the minimum supported macOS behavior graceful when an API is unavailable.
- Combine face, person, foreground, background, saliency, regional deltas, tone/color, and scene evidence without allowing one failed provider to erase other signals.
- Define confidence aggregation and evidence provenance so policy can scale or skip a correction when evidence is weak or contradictory.
- Keep scene facts in analysis values; recommendations belong in `AutoEnhancementPolicy`.

## Acceptance criteria

- [ ] Scene classification is optional and unavailable APIs/failures are represented as missing evidence, not fatal analysis errors.
- [ ] Night, sunset/warm light, snow/high-key, fog, backlight, monochrome, and mixed-light fixtures produce evidence with confidence and no fixed scene preset.
- [ ] Confidence is reported separately for global tone, color/neutral, scene, subject/regions, detail, and each semantic provider used by Auto.
- [ ] Conflicting or missing signals reduce confidence and correction strength predictably; they do not invent a white balance or mask.
- [ ] Existing `PhotoAnalysis`/cache versioning remains backward-compatible with neutral defaults for older cached values.
- [ ] Focused tests assert evidence ranges and degradation behavior on synthetic fixtures and on `#available`-guarded unsupported paths.

## Non-goals

- Do not change renderer controls or apply edits.
- Do not optimize Apple image-aesthetics scores.
- Do not add a required Core ML model or cloud fallback.

## Likely files

- `Sources/KromoraKit/Models/PhotoAnalysis/SceneCharacteristicsAnalyzer.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysis.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/AnalysisValueTypes.swift`
- `Tests/KromoraKitTests/PhotoAnalysis*Tests.swift`

## Verification

Run focused scene/quality/cache tests on the deployment target and current macOS SDK. Confirm no image leaves the device and no concurrency escape hatch is introduced.


### Comment — pi @ 2026-09-10T18:19:31.574Z

Implementation complete on main (uncommitted working tree; 4 modified/created production files + 1 test file, +~1100 lines). Scene-classification evidence and per-signal confidence for Auto:

What was built
- SceneEvidence.swift (new): SceneClassificationObservation value type; SceneClassifierProviding seam + VisionSceneClassifier (VNClassifyImageRequest, on-device, non-throwing — unavailable API/undecodable image/failed request/cancellation all yield nil, never a fatal error); SceneColorFacts bridge (from ColorStatistics with unknown hue marked unavailable, from PixelCorrelatedColor with entropy/mixed flags); SceneProvenance; SemanticProviderConfidence + AutoSignalConfidence with the one documented aggregation rule (overall = mean of available signals scaled by fraction present — missing signals reduce, never erase); plus SceneCharacteristicsAnalyzer.measurement bridge that rebuilds relationships/primary-subject through the shared selectors.
- SceneCharacteristicsAnalyzer.swift: 7 new independent continuous likelihoods (night, sunsetWarm, snow, fog, monochrome, mixedLight, daylight) from smooth-range products over measured tone/color facts, nudged at most +0.4 probabilistic-OR by matching Vision labels (case-insensitive substring cues, unknown identifiers never match); mixedLight stays 0 without pixel-correlated hue evidence; label-vs-physics disagreement (>0.5) scales sceneConfidence x0.6; missing labels -0.15, missing regions -0.2. Custom Codable keeps pre-344 caches readable (new likelihoods 0, legacyConfidence 0.5, legacy provenance). No presets anywhere.
- PhotoAnalysis.swift: persisted sceneClassifications (so analyze(_:) reproduces the stored scene exactly — preserves the corpus self-consistency invariant) + derived signalConfidence, both decodeIfPresent-backward-compatible under unchanged AnalysisVersion.current; assembler/static entry points accept optional classifications (default nil).
- PhotoAnalysisCoordinator.swift: injectable sceneClassifier (default VisionSceneClassifier), fetched best-effort per analysis and passed to the assembler; nil only reduces confidence.

Corpus finding: the change initially broke PhotoIntelligenceCorpusTests self-consistency (live labels shifted scene vs label-free recompute). Fixed by design, not by weakening the test: labels are now persisted input evidence, so stored scene stays a pure function of stored facts. Semantic expects (backlight >0.3, snow/fog/night ranges, tonal keys) all still pass unmodified.

Verification: 19/19 SceneEvidenceTests green (night/sunset/snow/fog/mono/mixed/daylight ranges, label boost caps, contradiction penalty, degradation, per-signal aggregation, failed-mask isolation, measurement bridge, stub+garbage-data adapter paths, legacy JSON for scene and analysis, label round-trip reproducibility); neighboring suites green (SceneCharacteristics/Assembly/Cache/Coordinator/CurrentEditMeasurement/AutoLightEngine/AutoAdjustment/AutoCandidateEvaluation, 67 tests); scripts/ci-tests.sh fast exit 0; scripts/ci-tests.sh serial exit 0 (corpus included); swift build clean; dg validate OK; git diff --check clean; no Swift 6 escape hatches. No renderer-control, policy, or scoring changes per non-goals.

## Agent log

- 2026-09-10T18:53:20.339Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Scene classification is optional and unavailable APIs/failures are represented as missing evidence, not fatal analysis errors. (pass) — VisionSceneClassifier returns nil on unsupported revision, undecodable image, request error, or cancellation; PhotoAnalysisCoordinator treats nil as evidence reduction only.
- [x] Night, sunset/warm light, snow/high-key, fog, backlight, monochrome, and mixed-light fixtures produce evidence with confidence and no fixed scene preset. (pass) — 19 SceneEvidenceTests assert independent continuous likelihoods per fixture; backlight/high/low-key retained from prior work; mixed-light correctly stays 0 without pixel-correlated hue evidence.
- [x] Confidence is reported separately for global tone, color/neutral, scene, subject/regions, detail, and each semantic provider used by Auto. (pass) — AutoSignalConfidence + SemanticProviderConfidence expose independent fields; verified by testFullSignalsReportHighOverallAndPerProviderEvidence and testMissingSignalsReduceOverallWithoutErasingUsableMeasurements.
- [x] Conflicting or missing signals reduce confidence and correction strength predictably; they do not invent a white balance or mask. (pass) — Label/physics disagreement scales sceneConfidence x0.6; missing labels/regions apply fixed penalties; no slider or mask values are produced anywhere in this change (facts-only, verified by grep and by non-goals check).
- [x] Existing PhotoAnalysis/cache versioning remains backward-compatible with neutral defaults for older cached values. (pass) — Custom Codable on SceneCharacteristics and PhotoAnalysis decodeIfPresent every new field; AnalysisVersion.current unchanged; testLegacySceneJSONDecodesToNeutralDefaults and testLegacyAnalysisJSONDecodesWithDerivedConfidenceAndSameVersion pass.
- [x] Focused tests assert evidence ranges and degradation behavior on synthetic fixtures and on #available-guarded unsupported paths. (pass) — SceneEvidenceTests.swift: 19/19 green, including stub-classifier and undecodable-source adapter paths.
Checks run:
- swift build (clean, only pre-existing unrelated deprecation warnings)
- swift test --filter SceneEvidenceTests (19/19 passed)
- scripts/ci-tests.sh fast (748/748 passed)
- scripts/ci-tests.sh serial (328/328 passed, including PhotoIntelligenceCorpusTests self-consistency)
- git diff --check (clean)
- grep for @unchecked Sendable / nonisolated(unsafe) / @preconcurrency in changed files (none found)
Findings:
- PhotoAnalysis's custom Decodable init decoded AnalysisQuality twice (once inline to derive globalToneAvailable for signalConfidence, once again for self.quality) - harmless but redundant; fixed inline as a localized change.
Fixes:
- Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysis.swift: decode AnalysisQuality once in init(from:) and reuse it for both signalConfidence derivation and self.quality.
Verification commits:
- 955f1c53e526f2e10dd8e710a76fe460f2ba6a80
Actor: claude
Resolved model: sonnet
Pickup session: 01MTVVPANUWB3TUVO3
Summary: Verification passed: 19/19 SceneEvidenceTests, fast (748/748) and serial (328/328, incl. corpus) lanes green, no Swift 6 escape hatches, backward-compatible decoding confirmed. Applied one localized fix (redundant AnalysisQuality decode) and committed all KRMA-344 work.
