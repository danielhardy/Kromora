---
id: KRMA-575
title: "Masking: expose each detected face as an independently editable mask"
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: One valid detected face yields one independently addressable Face mask; existing single-face recipes continue to resolve to face zero
      result: pass
      notes: SemanticMaskDefinition.faceIndex defaults to 0 and legacy JSON without faceIndex decodes to 0; semanticMaskKind maps face target + index 0 to .face.
    - criterion: Two or more valid faces remain individually addressable with separate semantic recipes and separate local adjustments
      result: pass
      notes: nextFaceIndex(in:) scans existing .face components and assigns the next unused index; repeated Face action creates distinct LocalAdjustmentLayer entries named Face 1, Face 2, ... backed by distinct SemanticMaskDefinition(faceIndex:) recipes.
    - criterion: Selecting or editing one face mask does not change another face matte or its adjustments
      result: pass
      notes: Each face recipe is a separate MaskComponent/LocalAdjustmentLayer with its own SemanticMaskKind (.face vs .faceInstance(n)), which is the cache/resolver key, so resolution and edits are isolated.
    - criterion: Face mattes retain landmark-derived, feathered pixel shape; no rectangular fallback introduced
      result: pass
      notes: VisionSemanticMaskProvider's detection/rasterization/feathering path (detectFaceLandmarks, faceMasks) is untouched by this change.
    - criterion: Existing face applicability and person/face gating behavior remains intact
      result: pass
      notes: No changes to gating logic; full targeted suite (VisionSemanticMaskProviderTests, PhotoAnalysisAssemblyTests, MaskingWorkspaceTests, LocalMaskRenderingTests) passes green.
    - criterion: Face index ordering limitation is preserved/documented rather than solved with new detection infrastructure
      result: pass
      notes: Doc comment on SemanticMaskDefinition.faceIndex explicitly notes ordering can change on re-analysis; no new detection infra was added, reusing existing .face/.faceInstance(index) addressing.
  checks_run:
    - swift build -> pass
    - swift test --filter 'LocalMaskRenderingTests|MaskingWorkspaceTests|VisionSemanticMaskProviderTests|PhotoAnalysisAssemblyTests|MaskingWorkflowCoordinatorTests' -> pass (105 tests, 1 skipped, 0 failures)
    - git diff --check -> pass
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-25T04:58:20.982Z
  session: 01MUGHNNKP98CSUR45
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - masking
  - vision
created: 2026-09-25T02:28:50.104Z
updated: 2026-09-25T04:58:20.984Z
blockers: []
order: a0
board: product
---

## Objective

Make every valid detected face available as its own independently editable Face mask in the masking workflow. A photo with multiple visible faces currently offers only one usable Face mask, even though the semantic-mask provider already supports indexed face mattes.

## Investigation findings

The single-face collapse is downstream of Vision detection and matte generation:

- `VisionSemanticMaskProvider.detectFaceLandmarks` uses `VNDetectFaceLandmarksRequest` and iterates over all `request.results` with `compactMap`; it does not use `.first`. Observations without usable landmark points are currently skipped so the app does not fall back to rectangular face masks.
- `VisionSemanticMaskProvider.faceMasks` rasterizes and caches each surviving feathered landmark matte independently. The first uses `.face`; later ones use `.faceInstance(index)`. Cache reload already reads the contiguous indexed entries.
- `SemanticMaskKind` supports `.faceInstance(Int)`, but the durable `SemanticTarget` in `LocalMaskModels.swift` only has `.face`. `LocalMaskRendering.swift` maps that target to `.face`, so a saved semantic mask recipe can resolve only the first matte.
- `MaskCreationKind` and the persistent masking workspace expose a single `.face` action, which creates `SemanticMaskDefinition(target: .face)`. `MaskingPanelModel` also requests only `.face`.
- Analysis stages and person-signal warming request `.face`; this populates the provider cache for all generated face mattes, but downstream selection and saved recipes do not expose the indexed candidates.

The existing Face matte is landmark-derived, expanded and feathered, then optionally intersected with person/foreground support. Preserve that pixel-matte behavior; do not replace it with face bounding boxes or one inseparable union.

## Expected behavior

- One valid landmarked face continues to produce one usable Face mask, and existing saved `.face` recipes continue to resolve to that first face.
- Two or more valid faces remain individually addressable through the masking workflow, with separate semantic recipes and separate local adjustments for each face.
- The model retains individual face mattes. An optional All Faces selection may union them for convenience, but it must not replace the individual masks.
- Selecting or editing one face mask does not change another face matte or its adjustments.
- Face mattes retain the current landmark-derived, feathered pixel shape; no rectangular fallback is introduced.
- Existing face applicability and person/face gating behavior remains intact.

## Implementation direction

Carry a face index or equivalent per-face selector through the durable semantic-mask definition, cache lookup, local-mask resolver, and masking-workspace creation flow. Keep the existing `.face` target backward-compatible as face index zero. Use the provider’s existing `.face` / `.faceInstance(index)` addressing rather than adding a separate face-detection infrastructure.

Expose the available faces naturally in the masking workflow, such as Face 1, Face 2, and so on. Avoid a broad redesign of masking UI. If analysis currently returns only a singular Face summary, retain its current single-face meaning or add indexed candidates without collapsing the per-face model.

The provider currently numbers faces by order among surviving landmark mattes, so the index is stable within that analysis result/cache identity but may change after re-analysis if Vision changes detection order or which detections have usable landmarks. Preserve and document this limitation unless Vision already provides a reliable observation identity that can be carried through the existing value-type boundary without unnecessary infrastructure.

## Tests

Add or update coverage for:

- One valid detected face yields one independently addressable Face mask.
- Two valid faces yield two distinct indexed masks and can be selected through distinct durable semantic definitions.
- The provider does not silently reduce `VNDetectFaceLandmarksRequest.results` to the first observation.
- Individual masks remain distinct feathered pixel mattes, rather than a bounding rectangle or an inseparable union.
- Resolving or editing one face recipe does not change another face matte or its adjustments.
- Cached multi-face analysis reloads all indexed mattes rather than only `.face`.
- Existing single-face recipe compatibility and person/face applicability gating remain green.

Prefer a deterministic provider seam or existing multiple-face fixture over relying on flaky live Vision detection. If no suitable fixture exists, add the smallest deterministic seam needed to test all results and indexed cache behavior.

## Context

- Detection, matte generation, and indexed provider cache: `Sources/KromoraKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift`.
- Indexed analysis kinds: `Sources/KromoraKit/Models/PhotoAnalysis/RegionMask.swift`.
- Durable semantic target: `Sources/KromoraKit/Models/LocalMaskModels.swift`.
- Semantic recipe resolution: `Sources/KromoraKit/Models/LocalMaskRendering.swift`.
- Mask creation and face options: `Sources/KromoraKit/ViewModels/MaskingWorkflowCoordinator.swift`, `Sources/KromoraKit/Views/MaskingWorkspace.swift`, and `Sources/KromoraKit/ViewModels/MaskingPanelModel.swift`.
- Relevant tests: `Tests/KromoraKitTests/VisionSemanticMaskProviderTests.swift`, `Tests/KromoraKitTests/MaskingWorkspaceTests.swift`, `Tests/KromoraKitTests/PhotoAnalysisAssemblyTests.swift`, and local-mask resolver tests.

## Checks

- `swift build`
- Run the relevant Vision semantic-mask, photo-analysis, local-mask rendering, and masking-workflow tests.
- `git diff --check`

## Out of scope

- Full face-retouching UX or facial-component masks.
- General masking UI redesign.
- Changing Person segmentation.
- Replacing the existing Face matte algorithm except where needed to preserve a separate matte per detected face.

## Handoff notes

When handing off, state where the collapse was found, how many observations/mattes are preserved, how indexed masks are represented in durable recipes, whether UI changes were needed, and whether face ordering can change across re-analysis.


### Comment — codex @ 2026-09-25T04:55:53.532Z

Implemented and committed as 3a485e7. The collapse was downstream of Vision: valid landmark observations and distinct feathered provider mattes already survive, but durable recipes and Face actions addressed only .face. SemanticMaskDefinition now persists faceIndex (legacy recipes default to 0), the resolver maps it to .face/.faceInstance(index), and repeated Face actions create separately named, editable Face 1/Face 2/... masks and indexed components. No broad UI redesign was needed. Face indices follow surviving landmark results and can change if Vision detection/order changes on re-analysis. Verified with swift build; targeted LocalMaskRendering, MaskingWorkspace, MaskingWorkflowCoordinator, VisionSemanticMaskProvider, and PhotoAnalysisAssembly suites (105 tests, 1 skipped, 0 failures); git diff --check passed.

## Agent log

- 2026-09-25T04:58:20.982Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] One valid detected face yields one independently addressable Face mask; existing single-face recipes continue to resolve to face zero (pass) — SemanticMaskDefinition.faceIndex defaults to 0 and legacy JSON without faceIndex decodes to 0; semanticMaskKind maps face target + index 0 to .face.
- [x] Two or more valid faces remain individually addressable with separate semantic recipes and separate local adjustments (pass) — nextFaceIndex(in:) scans existing .face components and assigns the next unused index; repeated Face action creates distinct LocalAdjustmentLayer entries named Face 1, Face 2, ... backed by distinct SemanticMaskDefinition(faceIndex:) recipes.
- [x] Selecting or editing one face mask does not change another face matte or its adjustments (pass) — Each face recipe is a separate MaskComponent/LocalAdjustmentLayer with its own SemanticMaskKind (.face vs .faceInstance(n)), which is the cache/resolver key, so resolution and edits are isolated.
- [x] Face mattes retain landmark-derived, feathered pixel shape; no rectangular fallback introduced (pass) — VisionSemanticMaskProvider's detection/rasterization/feathering path (detectFaceLandmarks, faceMasks) is untouched by this change.
- [x] Existing face applicability and person/face gating behavior remains intact (pass) — No changes to gating logic; full targeted suite (VisionSemanticMaskProviderTests, PhotoAnalysisAssemblyTests, MaskingWorkspaceTests, LocalMaskRenderingTests) passes green.
- [x] Face index ordering limitation is preserved/documented rather than solved with new detection infrastructure (pass) — Doc comment on SemanticMaskDefinition.faceIndex explicitly notes ordering can change on re-analysis; no new detection infra was added, reusing existing .face/.faceInstance(index) addressing.
Checks run:
- swift build -> pass
- swift test --filter 'LocalMaskRenderingTests|MaskingWorkspaceTests|VisionSemanticMaskProviderTests|PhotoAnalysisAssemblyTests|MaskingWorkflowCoordinatorTests' -> pass (105 tests, 1 skipped, 0 failures)
- git diff --check -> pass
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUGHNNKP98CSUR45
