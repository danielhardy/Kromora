---
id: KRMA-573
title: Replace square Subject and Foreground masks with outlined mattes
type: bug
status: backlog
priority: high
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - masking
  - vision
created: 2026-09-25T01:33:33.435Z
updated: 2026-09-25T01:34:07.075Z
blockers: []
order: zy
board: product
context:
  files:
    - Sources/KromoraKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift
    - Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift
    - Sources/KromoraKit/Models/PhotoAnalysis/MaskOperations.swift
    - Sources/KromoraKit/Models/LocalMaskRendering.swift
    - Sources/KromoraKit/Views/MaskingWorkspace.swift
    - Tests/KromoraKitTests/VisionSemanticMaskProviderTests.swift
  issues:
    - KRMA-572
  commands:
    - swift test --filter 'VisionSemanticMaskProviderTests|PhotoAnalysis|MaskingWorkflow|LocalMask'
    - swift build
    - git diff --check
---

## Objective

Subject and Foreground masks paint as hard squares. Background then covers the whole frame. Person already outlines the person. Match that kind of matte. This is not an overlay drawing bug.

## Diagnosis

`MaskingWorkspace.draw` stretches whatever `CGImage` it is given across the full source rect. Person looks correct through that same draw path, so the wash is not what makes Subject and Foreground square.

**Subject is a filled bounding box, on purpose.** `VisionSemanticMaskProvider.subjectMask` runs `VNGenerateAttentionBasedSaliencyImageRequest`, takes `salientObjects.first.boundingBox`, and `rectangularMask` fills that rectangle with 1s (about lines 289–322 and 577–596). The comment there says the box is the stable result and that a later ticket can use the observation heat map. A smaller square in the frame is that box. Person uses `VNGeneratePersonSegmentationRequest` and stores `observation.pixelBuffer` (`personMask`, about lines 338–401). That pixel matte is why Person outlines.

**Foreground is a square Vision buffer.** `foregroundMasks` calls `observation.generateMask(forInstances:)`. The provider comment and `VisionSemanticMaskProviderTests.testForegroundUnionAcceptsInstanceMasksAtProviderResolution` record that Vision returns those instance masks at its own resolution, a square buffer regardless of source aspect. The union keeps that square size. `MaskOperations.resized` then stretches it onto the photo. A square matte stretched into a 3:2 frame still reads as a block, not an outline. **Background is `MaskOperations.invert` of that foreground union** (`PhotoAnalysisCoordinator.performMask`, about lines 348–376). A bad or empty foreground makes Background the whole image.

## What to implement

Produce pixel mattes in the analysis image's aspect, then store those. Do not keep the bounding-box fill for Subject, and do not keep a square instance buffer as the stored Foreground mask.

- Foreground: ask Vision for a mask scaled to the analysis image size. `VNGenerateForegroundInstanceMaskObservation.generateScaledMask(forInstances:scaledToImageOfSize:)` is the API that matches source aspect. Store that buffer. The union and Background complement then share the photo's aspect. Guard it with the existing macOS 14 availability around `VNGenerateForegroundInstanceMaskRequest`.
- Subject: stop calling `rectangularMask`. Choose the foreground instance that overlaps the salient-object box, and store that instance's scaled matte. When person segmentation applies and overlaps the same box, prefer the person matte, which is already the outline quality bar. The saliency box may select which instance, and it must not be the painted mask. A saliency heat-map blob is not an acceptable substitute for an outline.
- Background stays the complement of the corrected Foreground union. No separate Vision background request.
- Bump `VisionConfiguration.providerVersion` (or the revision fields that feed it) so masks cached under the old rectangle/square provider are not reused.
- Leave Person's request path as it is, other than sharing whatever aspect mapping you add if Person's buffer is also square. Person is the visual reference, not the thing to replace.

If a real photo's scaled foreground instance is still a coarse box after this, record buffer size, aspect, and coverage in the handoff. Do not hide that by drawing a synthetic ellipse.

## Tests

In `Tests/KromoraKitTests/VisionSemanticMaskProviderTests.swift`:

- A non-square analysis image does not store Foreground at a square size. Update `testForegroundUnionAcceptsInstanceMasksAtProviderResolution` if the union now normalizes to analysis aspect before storage; the incompatible-sizes failure it guards against must stay fixed.
- Subject pixels for a fixture with a non-rectangular instance are not a filled rectangle. A bounding-box fill of the salient rect must fail this test.
- Background coverage is the complement of Foreground, not approximately 1, when Foreground covers only part of the frame.
- Existing person gating (`personNotApplicable` without a face or foreground signal) stays.

No GPU is required for the provider tests. Keep `swift test --filter VisionSemanticMaskProviderTests` and `PhotoAnalysisCoordinatorTests` green if that suite exists.

## Checks

- `swift build`
- `swift test --filter 'VisionSemanticMaskProviderTests|PhotoAnalysis|MaskingWorkflow|LocalMask'`
- `git diff --check`

## Out of scope

Side-by-side Original showing the mask wash (KRMA-572). Brush, linear, and radial masks. Changing Auto's use of saliency to choose a region, except where it would start consuming the new Subject matte and needs the same non-rectangle expectation.
