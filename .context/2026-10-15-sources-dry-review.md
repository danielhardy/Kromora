# Sources review: DRY, unused code, and avoidable bloat

**Date:** 2026-10-15, America/Los_Angeles  
**Repository baseline:** `e9c83f3e` plus the existing working tree  
**Scope:** All Swift and Metal source files under `Sources/`  
**Requested outcome:** Review only. No implementation changes. Priorities reflect quality and impact, not implementation effort.

## Assessment

The best cleanup opportunities are duplicated **rules and workflows**, rather than large blocks of identical text. Kromora already shares much of its rendering pipeline and has useful coordinator boundaries. The remaining duplication is concentrated in geometry, control presentation, cache infrastructure, asynchronous request management, and migration-era APIs.

Two duplicated rules already produce different answers:

1. Rendering and pointer mapping construct different perspective quadrilaterals.
2. Semantic-mask producers calculate bounds using different thresholds and coordinate conventions.

These deserve attention before cosmetic deduplication. There are also clear removal targets: an unconnected legacy masking panel, an older Auto engine with no production invocation, and several uncalled helpers. Verified backup/restore is a larger, deliberately deferred subsystem that should be considered separately from accidental dead code.

The recommended direction is to delete obsolete paths, then extract narrow shared policies around the surviving behavior. Avoid replacing small explicit code with a universal framework. A successful cleanup reduces the number of places that must change together without weakening concurrency, persistence, or rendering contracts.

## Scope and evidence

The review inventoried and scanned **279 code files, containing 92,892 lines**: 276 Swift files and three Metal sources. It included whole-tree symbol/reference searches, whitespace-insensitive repeated-block detection, structural similarity searches, and targeted manual inspection of implementations, their callers, and relevant tests. This is a static review across the complete source inventory, not a claim of manual line-by-line verification of every file or exhaustive compiler-proven reachability.

| Area | Files | Lines |
| --- | ---: | ---: |
| SwiftPM launcher | 1 | 11 |
| Models, excluding analysis subdirectories | 126 | 40,750 |
| Photo analysis | 26 | 11,166 |
| Retouch analysis | 4 | 442 |
| Platform adapters | 1 | 40 |
| Presentation adapters and app lifecycle | 11 | 1,005 |
| Metal sources | 3 | 722 |
| Resource support | 2 | 115 |
| View models and coordinators | 54 | 21,318 |
| Views | 51 | 17,323 |
| **Total** | **279** | **92,892** |

Project guidance consulted: `CLAUDE.md`, `docs/APP_ARCHITECTURE.md`, `docs/ENGINEERING_GUIDE.md`, `docs/STORAGE_POLICY.md`, and `docs/PRODUCT_SCOPE.md`. Resource images, LUT table data, manifests, hashes, and compiled shader binaries were treated as assets rather than repeated application code.

“No production caller” means no invoking reference was found in the application sources after checking the implementation and its related types. Tests and comments are distinguished from application calls. Framework callbacks, protocol requirements, and SwiftUI/AppKit entry points are not classified as unused merely because a text search finds no direct invocation.

No build, test suite, UI session, or performance benchmark was run. The two divergent-rule examples below follow directly from the inspected arithmetic. User-visible consequences are reasoned implications, not reproduced UI failures. Performance benefits are hypotheses until measured. No product source, test, project configuration, or DispatchGraph record was changed for this review.

## Priority overview

| ID | Priority | Opportunity | Main benefit |
| --- | --- | --- | --- |
| R01 | High | One perspective geometry contract | Correctness, less duplicated math, less repeated setup |
| R02 | High | One mask-bounds contract | Correctness and consistent regional analysis |
| R03 | High | Remove the unused legacy masking panel | Delete an obsolete workflow and its maintenance surface |
| R04 | High | Retire the old subject-aware Auto engine | Remove a second policy that production does not use |
| R05 | High | Share bounded file hashing and copy primitives | Consistent cancellation, cleanup, and integrity checks |
| R06 | Medium | Share inspector slider/value/reset rows | Consistent undo, precision, accessibility, and layout |
| R07 | Medium | Centralize adjustment metadata and group membership | Eliminate repeated control lists and switch tables |
| R08 | Medium | Share Auto control access and application | Keep full and reduced candidates consistent |
| R09 | Medium | Share in-flight request bookkeeping within owners | Stabilize cancellation and completion behavior |
| R10 | Medium | Share smart-mask preflight lifecycle | Keep create/add workflows in step |
| R11 | Medium | Share cache envelope and maintenance policies | Reduce repeated cache I/O and cleanup logic |
| R12 | Medium | Consolidate in-memory LRU bookkeeping | Consistent eviction, costs, and diagnostics |
| R13 | Medium | Share perceptual-digest aggregation | Preserve one frame-comparison algorithm |
| R14 | Medium | Calculate render hashes once per immutable snapshot | Avoid repeated serialization and hashing |
| R15 | Medium | Share photo projection and metadata opening | Reduce mapping drift and repeated image-source setup |
| R16 | Medium, scope decision | Remove deferred backup/restore from the shipping code path | Reduce intentionally dormant production code |
| R17 | Low individually | Delete uncalled APIs and unused parameters | Reduce misleading entry points and stale surface area |
| R18 | Low | Use the existing finite-clamping primitive | Remove repeated numeric utility functions |
| R19 | Medium, investigate | Express shared source-transition cleanup explicitly | Make lifecycle obligations easier to audit |
| R20 | Low | Consolidate smaller repeated construction code | Reduce local maintenance overhead |

## R01 — Rendering and pointer mapping need one perspective geometry contract

**Confidence: high. Existing behavioral divergence.**

Evidence:

- [RenderPipeline.swift](../Sources/KromoraKit/Models/RenderPipeline.swift), `applyingPerspective`, line 414: constructs a quadrilateral and clamps every corner into the image extent.
- The same file, `inversePerspectivePoint`, line 557: repeats the corner construction and clamp for ROI planning, then derives a homography.
- [GeometryPointMapping.swift](../Sources/KromoraKit/Models/GeometryPointMapping.swift), `perspectiveForward` and `perspectiveInverse`, lines 121 and 130: repeat the corner construction without clamping.
- The same file, `project`, line 140: allocates and solves an 8×8 linear system on each mapping call.
- [MaskDiscoveryGeometry.swift](../Sources/KromoraKit/Models/MaskDiscoveryGeometry.swift), line 26: maps four corners through that mapper and derives projective coefficients again for the shader.
- [RetouchCanvasOverlay.swift](../Sources/KromoraKit/Views/RetouchCanvasOverlay.swift), lines 125 and 132: uses the mapper for handles, brush radii, and incoming pointer events.

For a unit frame with vertical perspective `1` and horizontal perspective `0`, the renderer's bottom edge spans normalized x coordinates `0...1`. The point mapper's bottom edge spans `-0.45...1.45`. In upper-left coordinates, the point mapper's inverse of the output bottom-left corner therefore targets `(-0.45, 1)` instead of the renderer's `(0, 1)`. This difference exists at smaller nonzero values too; the extreme value makes it easy to see.

Consequently, a mapper can round-trip its own points perfectly while disagreeing with the displayed pixels. Existing `GeometryPointMappingTests.testGeometryMappingsRoundTripThroughQuarterTurnsAndGeometry` checks that internal round trip; it does not establish agreement with the rendering quadrilateral.

**Recommendation:** Introduce one value-only geometry plan that owns the validated/clamped quadrilateral, coordinate convention, forward transform, inverse transform, and output extent. Have Core Image rendering, ROI planning, retouch mapping, and mask discovery consume it. Precompute the matrices when geometry inputs change rather than solve the system for each point. Keep Core Image objects inside the renderer.

**Verification:** Add renderer-to-mapper parity coverage using known image landmarks, both perspective signs, combined axes, flips, quarter turns, and non-square images. Check ROI coverage as well as pointer placement. Preserve existing round-trip tests, but do not use them as the only evidence.

## R02 — Mask bounds have two incompatible implementations

**Confidence: high. Existing behavioral divergence.**

Evidence:

- [VisionSemanticMaskProvider.swift](../Sources/KromoraKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift), `bounds(of:)`, line 699: includes pixels with value greater than zero, divides by width/height, and uses inclusive dimensions `(max - min + 1)`.
- [PhotoAnalysisCoordinator.swift](../Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift), `normalizedBounds(of:)`, line 395: includes values greater than `0.001`, divides by `(width - 1)/(height - 1)`, and uses `(max - min)`.
- The coordinator uses its version when constructing composed background masks, at lines 364 and 373.

For one active pixel in a 2×2 mask, the provider returns bounds with width and height `0.5`; the coordinator returns zero width and height. Thin masks and soft edge pixels also produce different results. These are different meanings of “bounds,” not formatting differences.

Bounds flow into analyzed regions, spatial overlap, subject relationships, and Auto evaluation targets. A provider-produced mask and a coordinator-composed mask should not acquire different spatial semantics solely because of which path created them.

**Recommendation:** Put raster bounds calculation on `NormalizedMask` or in `MaskOperations`. Choose one pixel-area convention, document it, and make the inclusion threshold an explicit policy if different thresholds are actually needed. Consumers should call the same implementation.

**Verification:** Cover empty, full, 1×1, single-pixel, single-row, single-column, and soft-edge masks. Assert provider/composed-path parity for identical pixels, including the background complement path.

## R03 — Delete the disconnected legacy masking panel

**Confidence: high. No production entry point found.**

Evidence:

- [MaskingPanel.swift](../Sources/KromoraKit/Views/MaskingPanel.swift), line 55: `MaskingPanel` has no construction site in application code.
- [MaskingPanelModel.swift](../Sources/KromoraKit/ViewModels/MaskingPanelModel.swift), line 9: explicitly describes itself as the legacy compatibility surface. Production construction occurs only inside the unused panel; other callers are tests.
- The panel never supplies the model's `onApply` hook. Its Apply button therefore cannot become enabled through this initializer.
- [AppChromeState.swift](../Sources/KromoraKit/ViewModels/AppChromeState.swift), line 35: `isMaskingPanelPresented` has no presentation consumer. Its only other source reference resets it during shutdown.
- The active editor uses `MaskingWorkspace` and `MaskingWorkflowCoordinator`.

**Recommendation:** Remove the unused panel, `MaskOverlayView`, its model, and the unused presentation flag. Move or retain `MaskGridView`: [AnalysisDebugPanel.swift](../Sources/KromoraKit/Views/AnalysisDebugPanel.swift), line 202, still uses it. Update or retire tests specifically preserving the obsolete panel; transfer any valuable provider/inversion behavior checks to the active boundaries.

This is approximately **380 lines of directly removable view/model code**, before test cleanup and the unused flag. The reusable debug mask grid must be excluded from that deletion.

**Verification:** Confirm the debug analysis overlay still renders; exercise active mask creation, inversion, apply, cancellation, and retry through the workspace. Update observation inventory tests that name the retired model.

## R04 — Retire the older subject-aware Auto policy

**Confidence: high for the unused engine; shared result types require follow-through.**

Evidence:

- [AutoLightEngine.swift](../Sources/KromoraKit/Models/PhotoAnalysis/AutoLightEngine.swift) contains 455 lines: an older six-control engine, proposals, evaluators, tuning, and rationale types.
- `AutoLightEngine.evaluate` is called by tests, including the older real-corpus tests, but no application invocation was found. Source references elsewhere describe it in comments.
- [AutoWorkflowCoordinator.swift](../Sources/KromoraKit/Models/PhotoAnalysis/AutoWorkflowCoordinator.swift), line 146: production content-aware Auto runs `ContentAwareAutoEngine`.
- [AutoEnhancementPolicy.swift](../Sources/KromoraKit/Models/PhotoAnalysis/AutoEnhancementPolicy.swift), line 37: owns the current coordinated proposal policy.
- [AutoAdjustment.swift](../Sources/KromoraKit/Models/AutoAdjustment.swift), line 115: the older `AutoRationale` survives through `AutoAdjustmentResult.rationale`. No application reader of that property was found; the histogram fallback defaults it to neutral.

**Recommendation:** Remove the uninvoked engine and its exclusively supporting policy types. Simplify the fallback result by removing obsolete rationale data if no active diagnostics require it. Retarget useful corpus expectations to the active Auto policy and end-to-end result.

Do **not** delete `AutoAdjustmentAnalyzer` merely because it is older: `ProductionAutoWorkflow` still calls it in its explicit degraded path, around line 193. That path has a different status from the unused `AutoLightEngine`.

**Verification:** Run current Auto policy, workflow, candidate evaluation, regional correction, and corpus tests. Preserve the intended photographic expectations while retiring assertions tied only to an engine the product does not invoke.

## R05 — Share bounded file hashing and copy primitives

**Confidence: high. Multiple independent implementations of the same I/O mechanics.**

Streaming SHA-256 loops appear in:

- [PortablePhotoIdentity.swift](../Sources/KromoraKit/Models/PortablePhotoIdentity.swift), `contentHash(ofFileAt:)`, line 146.
- [LibraryMembershipMatcher.swift](../Sources/KromoraKit/Models/LibraryMembershipMatcher.swift), `contentHash(of:)`, line 50.
- [PortablePackageTransaction.swift](../Sources/KromoraKit/Models/PortablePackageTransaction.swift), `hashFile`, line 1339, and staged file copying around line 894.
- [PortableLibraryValidation.swift](../Sources/KromoraKit/Models/PortableLibraryValidation.swift), `hashFile`, line 796.
- [PortableLibraryBackup.swift](../Sources/KromoraKit/Models/PortableLibraryBackup.swift), `hashFile`, line 604, and `copyFile`, line 535.
- [PortableLibraryRestore.swift](../Sources/KromoraKit/Models/PortableLibraryRestore.swift), `copy`, line 330, repeats bounded copy/close/cleanup mechanics.

The loops differ in chunk sizing, task-versus-callback cancellation, cancellation return conventions, and handle cleanup. For example, validation checks callback cancellation and `Task.isCancelled`; identity hashing has no cancellation check. Some differences belong to their callers, but the underlying read/hash mechanics do not need separate implementations.

**Recommendation:** Introduce narrow streaming primitives that can return byte count plus digest, copy while hashing, report progress, and honor an injected cancellation check. Keep domain errors and transaction/backup publication policy in their owners. Keep hashing in the copy pass rather than adding a second read to simplify the API.

If R16 removes deferred backup/restore, reduce those callers first; still consolidate the surviving identity, membership, transaction, and validation loops.

**Verification:** Use small injected chunk sizes, empty files, partial final chunks, read/write failure, cancellation, and source mutation. Verify handle cleanup and digest equivalence. Preserve clonefile verification, transaction fault-injection boundaries, and each owner's required sync/atomic publication behavior.

## R06 — Share the inspector's slider/value/reset row mechanics

**Confidence: high. Repeated interaction and accessibility behavior.**

Evidence:

- [LightInspectorView.swift](../Sources/KromoraKit/Views/LightInspectorView.swift), `controlRow`, line 74.
- [ColorInspectorView.swift](../Sources/KromoraKit/Views/ColorInspectorView.swift), `ColorValueRow`, line 443.
- [EffectsInspectorView.swift](../Sources/KromoraKit/Views/EffectsInspectorView.swift), `EffectsValueRow`, line 409.
- [DevelopInspectorView.swift](../Sources/KromoraKit/Views/DevelopInspectorView.swift), `controlRow`, line 122.
- [MaskingWorkspace.swift](../Sources/KromoraKit/Views/MaskingWorkspace.swift), `LocalAdjustmentValueRow`, line 997.
- [CropInspectorView.swift](../Sources/KromoraKit/Views/CropInspectorView.swift), straighten and perspective rows, around lines 247 and 319.

These repeatedly assemble a resettable label, numeric entry, slider, readout, interaction begin/end callbacks, accessibility ordering, and reset action. Temperature branches duplicate that interaction wiring again. This is the kind of code where a fix to undo grouping, keyboard precision, or VoiceOver can otherwise land in only some panels.

**Recommendation:** Build a small shared adjustment-row component around an explicit binding and display/entry policy. Support a slider slot or limited slider kind, an optional accessory, contextual accessibility title, and the existing interaction callbacks. Keep group-specific state and document mutation in the feature owner.

Preserve differences deliberately: local controls use hundredth precision, Color rounds whole values, exposure uses EV, and temperature has nonlinear slider mapping. Neutral values must remain explicit and must never be inferred from a range midpoint.

**Verification:** Reuse the current inspector, reset, slider entry, neutral-fill, and undo tests. Check one gesture equals one undo step, numeric entry agrees with slider entry, and contextual accessibility labels survive extraction.

## R07 — Centralize adjustment metadata and group membership

**Confidence: high. Repeated knowledge across model, binding, and view.**

Evidence:

- [LightControl.swift](../Sources/KromoraKit/Models/LightControl.swift) maintains separate title, range, getter, and setter switches over the same six fields.
- [LocalAdjustmentControl.swift](../Sources/KromoraKit/Models/LocalAdjustmentControl.swift) repeats the same Light titles/ranges, then more control access switches.
- [AppViewModel+Color.swift](../Sources/KromoraKit/ViewModels/AppViewModel+Color.swift), around lines 411–617: repeated channel/zone lookup, binding, reset, and write switches for mixer and grading.
- [EffectsInspectorView.swift](../Sources/KromoraKit/Views/EffectsInspectorView.swift), lines 20–23: defines advanced-control membership arrays.
- [AppViewModel+Effects.swift](../Sources/KromoraKit/ViewModels/AppViewModel+Effects.swift), lines 35–70 and 176 onward: separately repeats those lists for reset and modified-state detection.

**Recommendation:** Give each control one authoritative descriptor or key-path lookup for its model field, range, neutral, and presentation metadata. Give each Effects group one authoritative control list used for rendering its rows, resetting, and determining whether it is modified. Share equivalent Light metadata with local controls while retaining their distinct precision and storage scope.

This should make adding one advanced control require changing its definition and group membership once, rather than coordinating a view list, reset list, and enabled-state list.

**Verification:** Table-driven checks should assert that every displayed group member resets correctly, each neutral leaves the stage unchanged, and untouched controls retain their values. Keep model access compatible with Swift 6 isolation; do not add Sendable escape hatches to move descriptors around.

## R08 — Share Auto's control mapping without merging its policies

**Confidence: high. Repeated field-routing logic.**

Evidence:

- [AutoEnhancementCoordinator.swift](../Sources/KromoraKit/Models/PhotoAnalysis/AutoEnhancementCoordinator.swift), `currentValue` and `setValue`, lines 205 and 231: map `AutoPolicyControl` to document fields, including RAW/standard white balance and bounds.
- [AppleEnhancementReference.swift](../Sources/KromoraKit/Models/PhotoAnalysis/AppleEnhancementReference.swift), `apply`, line 1040: repeats the control-to-document routing. It intentionally rejects dehaze.
- [AutoEnhancementResult.swift](../Sources/KromoraKit/Models/AutoEnhancementResult.swift), `autoChangedControls`, line 256: repeats field comparisons for the same control set.
- The current native policy also applies its proposed field values directly.

**Recommendation:** Put source-aware reading and writing of a control behind one model-level access boundary. Use it for applying changes, producing reduced candidates, and identifying changed controls. Supply explicit RAW as-shot defaults where needed rather than hiding them in an arbitrary fallback.

The native proposal, Apple fitting policy, and reduced-strength interpolation remain separate. Preserve the Apple adapter's allowed-control gate: sharing a setter must not accidentally enable dehaze there. Preserve the existing photographic/standard temperature direction and clamping contract.

**Verification:** Compare full-strength application with a scale-1 candidate for every allowed control, RAW and standard sources, omitted RAW temperature/tint, bounds, and unchanged unrelated document fields.

## R09 — Share in-flight request bookkeeping within the existing owners

**Confidence: high. Repeated lifecycle machinery with important semantics.**

Evidence:

- [PhotoAnalysisCoordinator.swift](../Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift), `analyze` and `mask`, lines 108 and 170: repeat lookup, shared task creation, waiter accounting, completion cleanup, and cancellation handling.
- Its analysis and mask waiter-cancellation methods repeat the detach/cancel rules.
- [RenderEngine.swift](../Sources/KromoraKit/Models/RenderEngine.swift), `processingPrefix` and `postLocalProcessingPrefix`, lines 2247 and 2313: repeat cache lookup, in-flight lookup, flight token creation, await, test completion hook, token-checked removal, accounting, and insertion.

**Recommendation:** Extract the repeated memoization/flight operation within `RenderEngine`, taking the stage-specific key and graph construction separately. Use a small shared-task registry for the analysis coordinator's waiter-counted work.

These need not be one universal registry. The analysis path cancels shared work only when all waiters leave; render flights use different cancellation/publication rules. Share the mechanism appropriate to each owner and keep non-Sendable resources actor-confined.

**Verification:** Existing concurrent-cancellation and processing-prefix tests are especially important. Cover two callers for one key, one caller cancelling, all callers cancelling, invalidation during completion, failure followed by retry, and a late completion after replacement. Preserve token/generation checks.

## R10 — Share smart-mask creation and component-addition preflight

**Confidence: high. Two long, related asynchronous workflows.**

Evidence:

- [MaskingWorkflowCoordinator.swift](../Sources/KromoraKit/ViewModels/MaskingWorkflowCoordinator.swift), `createSmartMask`, line 486.
- The same file, `addSmartMaskComponent`, line 807.

Both reset discovery, replace the task, capture retry context, resolve source and asset, choose a face index, capture revision/fingerprint, warm person signals, request a preview mask, check staleness, apply presentation policy, and update discovery/status. They differ chiefly in the destination mutation and whether an existing layer must still exist.

**Recommendation:** Extract a typed semantic-mask request context and one preflight operation. Represent the commit target explicitly as new layer versus component addition. The common path should own stale-result checks and terminal discovery behavior; commit-specific validation stays explicit.

Do not force transient brush/gradient drafts into this helper: those have different commit and cancellation semantics.

**Verification:** Extend `MaskingWorkflowCoordinatorTests` to run the same cancellation, source-switch, person-signal, face-index, empty-region, retry, and error scenarios for both commit targets. Keep the layer-deleted-while-awaiting case for component addition.

## R11 — Share cache infrastructure and placeholder cleanup policies

**Confidence: high for duplication; storage formats should remain distinct.**

Evidence:

- [PhotoAnalysisCache.swift](../Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCache.swift), line 103, and [CurrentEditMeasurement.swift](../Sources/KromoraKit/Models/PhotoAnalysis/CurrentEditMeasurement.swift), `CurrentEditMeasurementCache`, line 1333: repeat keyed JSON envelopes, file naming, cancellation checks, decode-to-miss behavior, and atomic writes.
- [MaskStore.swift](../Sources/KromoraKit/Models/PhotoAnalysis/MaskStore.swift) has related metadata persistence but also owns binary sidecars and a separate publication contract.
- [LatestPreviewFrameStore.swift](../Sources/KromoraKit/Models/LatestPreviewFrameStore.swift), `schedulePlaceholderSweep`, line 505, and [ThumbnailFrameStore.swift](../Sources/KromoraKit/Models/ThumbnailFrameStore.swift), line 577: repeat scheduler admission, scheduled/completed state, bounded batches, and continuation to the next batch.
- Both frame stores repeat placeholder identity predicates and overlapping frame read/outcome logic.

**Recommendation:** Share a small keyed JSON persistence helper with caller-supplied validation and filename policy. Share placeholder identity policy on frame metadata and a bounded maintenance admission state machine. Keep preview files, packed thumbnails, and mask sidecars as separate storage owners.

**Verification:** Preserve exact-key validation, corrupt-entry-as-miss behavior, unsupported-version handling, deletion scoping, batch limits, and cancellation. Retain the mask sidecar-before-metadata ordering and each frame store's independent flushing/eviction rules.

## R12 — Consolidate in-memory LRU bookkeeping

**Confidence: high. Four implementations of the same bookkeeping family.**

Evidence:

- [BoundedCache.swift](../Sources/KromoraKit/Models/BoundedCache.swift), `BoundedLRUCache`, line 53: dictionary, recency array, costs, counters, and eviction.
- [LUTFilterCache.swift](../Sources/KromoraKit/Models/LUTFilterCache.swift), line 23: separate dictionary/usage array and eviction bookkeeping.
- [Thumbnails.swift](../Sources/KromoraKit/Models/Thumbnails.swift), `ThumbnailImageCache`, line 191: another bounded dictionary/recency implementation, protected by `OSAllocatedUnfairLock`.
- [LocalMaskRenderer.swift](../Sources/KromoraKit/Models/LocalMaskRenderer.swift), lines 33–41 and 475–534: custom linked-list recency and byte accounting for brush strokes.

There is already diagnostic drift: `LUTFilterCache.statistics`, around line 95, always reports zero evictions and zero cost, even though entries are evicted. Different capacities and ownership are legitimate; repeated bookkeeping is less useful.

**Recommendation:** Use one reusable LRU state implementation for replacement, recency, count/cost limits, removal, and counters. Put locking around that state for the global thumbnail cache and retain actor confinement for renderer caches. Extend the existing implementation where appropriate instead of introducing a dependency.

Avoid claiming a linked list is automatically faster for an eight-entry cache. Choose the representation using actual workloads; a shared simple implementation may be the better result.

**Verification:** Preserve oversize-entry rejection, replacement, targeted LUT invalidation, memory-pressure eviction accounting, saturation/overflow protection, and locked concurrent thumbnail access.

## R13 — Share the perceptual-digest aggregation algorithm

**Confidence: high. An exact repeated arithmetic block.**

Evidence:

- [RenderEngineResources.swift](../Sources/KromoraKit/Models/RenderEngineResources.swift), `perceptualDigest`, line 160; aggregation at lines 184–205.
- [ThumbnailFrameEncoding.swift](../Sources/KromoraKit/Models/ThumbnailFrameEncoding.swift), `digest`, line 99; aggregation at lines 118–139.

Both compute the same 8×8 RGB block-mean digest from a 64×64 RGBA buffer, including integer rounding. The aggregation contains a 22-line exact repeated block after ignoring whitespace and comments.

**Recommendation:** Put the byte-buffer-to-digest reduction beside `PerceptualDigest` with explicit dimensions/stride. Retain separate Core Image and Core Graphics rasterization adapters: their color-space, scaling, and orientation behavior must remain explicit.

**Verification:** Give the shared reduction deterministic golden buffers for solid colors, gradients, orientation, and rounding boundaries. Verify adapter behavior separately. Do not promise bitwise CI/CG raster equivalence merely because the reduction is shared, and version the persisted digest if its pixel meaning changes.

## R14 — Calculate render identities once per immutable snapshot

**Confidence: high for repeated work; performance impact is unmeasured.**

Evidence:

- [EditDocument.swift](../Sources/KromoraKit/Models/EditDocument.swift), `renderingHash`, line 124: copies the document, clears Auto metadata, and calls `RenderCacheHash.digest`.
- [RenderCacheKey.swift](../Sources/KromoraKit/Models/RenderCacheKey.swift), line 157: the generic digest creates a sorted-key JSON encoder, serializes the value, then hashes the bytes.
- [AppViewModel.swift](../Sources/KromoraKit/ViewModels/AppViewModel.swift), `updateDocument`, line 3434: calls the manual-edit path, then publishes/persists/schedules work that derives related identities.
- [PreviewPresentationCoordinator.swift](../Sources/KromoraKit/ViewModels/PreviewPresentationCoordinator.swift), [EditedThumbnailCoordinator.swift](../Sources/KromoraKit/ViewModels/EditedThumbnailCoordinator.swift), and [IdleFrameWarmerCoordinator.swift](../Sources/KromoraKit/ViewModels/IdleFrameWarmerCoordinator.swift) independently construct document hashes and frame signatures.

**Recommendation:** Make a revision-bound immutable render snapshot carry the document, its rendering hash, resolved Look signature, source identity, and working-space/pixel epoch inputs. Derive it once when the inputs are frozen and pass it to preview/thumbnail/cache operations that describe that same snapshot.

Do not add a mutable hidden hash cache to `EditDocument`: nested mutations would make invalidation fragile. Source, Look content, working space, and pipeline version must still participate where they currently do.

**Verification:** Count encodes/hash computations during deterministic slider bursts and assert snapshot invalidation for document, source, Look-content, and space changes. Preserve the exclusion of Auto provenance and fail-safe behavior for unencodable values. Measure before making performance claims.

## R15 — Share photo projection and avoid opening metadata sources twice

**Confidence: high. Repeated value mapping and setup.**

Evidence:

- [PortableLibrarySession.swift](../Sources/KromoraKit/Models/PortableLibrarySession.swift), `browsingAsset`, line 1677; `browsingAssetForLaunchHint`, line 1717; and `materialize`, line 1739: repeatedly map membership summaries into metadata, rating/flag state, filenames, and aspect ratios.
- The browsing/launch-hint variants intentionally resolve different amounts of source data. That distinction is important for startup I/O.
- [ImageCollection.swift](../Sources/KromoraKit/Models/ImageCollection.swift), `readMetadata`, line 1188: opens an ImageIO source and checks its count, then calls `ImageMetadata.read(from:)` for the same URL/data, which opens another ImageIO source.
- [ImageMetadata.swift](../Sources/KromoraKit/Models/ImageMetadata.swift) also owns the metadata-to-value conversion used by these consumers.

**Recommendation:** Extract the common summary-to-presentation mapping while passing in the already-chosen source/locator. Keep cheap browsing and launch hints free of asset-record reads. Add a metadata reading boundary that can return a validated result from one `CGImageSource`, allowing collection metadata loading to avoid the preliminary open followed by another open.

**Verification:** Preserve launch-hint asset-record read budgets, virtual-copy source naming, culling-state defaults, dimensions, and aspect ratios. Test corrupt/empty sources and URL/data equivalence. Opening an ImageIO source twice is repeated setup; this review does not claim it necessarily decodes the full image twice.

## R16 — Decide whether deferred backup/restore belongs in the shipping target

**Confidence: high that this is deliberately unwired; removal is a product-scope choice.**

Evidence:

- [PortableLibraryBackup.swift](../Sources/KromoraKit/Models/PortableLibraryBackup.swift): 738 lines.
- [PortableLibraryRestore.swift](../Sources/KromoraKit/Models/PortableLibraryRestore.swift): 480 lines.
- [PRODUCT_SCOPE.md](../docs/PRODUCT_SCOPE.md), “Post-MVP boundaries”: explicitly states that these implementations remain tested but unwired and that the supported workflow is quit-and-copy.
- The application has no invocation path into these operations. Their extensions and tests retain them.

**Recommendation:** Given the stated preference to cut unused code, remove this **1,218-line deferred subsystem** from the production target unless there is a concrete commitment to ship it. Git history can preserve the implementation and its design. Alternatively, retain it in a clearly separate development-only target, accepting that this still carries maintenance cost.

This is not evidence that backup functionality is broken or accidental. It is an intentional future-feature investment. Make that retention decision explicitly instead of treating its tests as proof that the current application needs the code.

**Verification:** Confirm no active package-opening, validation, import, or transaction helper depends on the deferred subsystem. Retain the currently used durable primitives and the supported quit-and-copy/reopen tests. Do not remove package validation or recovery merely because backup uses them too.

## R17 — Remove uncalled helpers and parameters that have no consumer

**Confidence: high for the directly checked symbols below. These are internal APIs, not dynamic framework callbacks.**

| Candidate | Location | Observation |
| --- | --- | --- |
| `ResolvedSemanticMask` | [LocalMaskRendering.swift](../Sources/KromoraKit/Models/LocalMaskRendering.swift), line 413 | No construction or other source/test reference; active semantic resolution uses another resolver. |
| `RenderBoundarySourceResolver` | [RenderBoundarySourceResolver.swift](../Sources/KromoraKit/Models/RenderBoundarySourceResolver.swift), line 7 | Used only by tests; wraps the already-used `PackagePath` boundary. Move useful assertions to that boundary. |
| `loadManifestOnly` | [BundledLookLibrary.swift](../Sources/KromoraKit/Models/BundledLookLibrary.swift), line 65 | No caller. Its About-window motivation is stale. |
| `forwardRadiusScale` | [GeometryPointMapping.swift](../Sources/KromoraKit/Models/GeometryPointMapping.swift), line 59 | No caller; the retouch overlay computes its screen radius using other mapping calls. |
| `applicationSupportRoot` | [KromoraStorage.swift](../Sources/KromoraKit/Models/KromoraStorage.swift), line 19 | No caller. Do not expand this into deletion of the separate storage migration helpers without tracing them. |
| `cancelPendingWrites` | [LatestPreviewFrameStore.swift](../Sources/KromoraKit/Models/LatestPreviewFrameStore.swift), line 233 | No caller; keep the active flush/shutdown behavior. |
| `clearPortableSelection` | [PortableLibrarySession.swift](../Sources/KromoraKit/Models/PortableLibrarySession.swift), line 891 | No caller. |
| `resultIfFinished` | [PortablePackageImport.swift](../Sources/KromoraKit/Models/PortablePackageImport.swift), line 288 | No caller; active code awaits the operation result. |
| `presentationMetallibData` | [KromoraKitResourceBundle.swift](../Sources/KromoraKit/Support/KromoraKitResourceBundle.swift), line 51 | No caller; active loading uses the metallib URL. |
| `selectCollectionItem` | [AppViewModel.swift](../Sources/KromoraKit/ViewModels/AppViewModel.swift), line 2053 | Private and uncalled. |
| `cancelEditedThumbnailDebounce` | [AppViewModel.swift](../Sources/KromoraKit/ViewModels/AppViewModel.swift), line 3142 | Private and uncalled forwarding helper. |
| `recordSkipped` | [PhotosImportCoordinator.swift](../Sources/KromoraKit/ViewModels/PhotosImportCoordinator.swift), line 398 | No caller; trace the current accounting path rather than preserve two entry points. |
| `resetAllDetail`, `resetAllTextureClarityDehaze` | [AppViewModel+Effects.swift](../Sources/KromoraKit/ViewModels/AppViewModel+Effects.swift), lines 21 and 81 | No callers; the UI uses other group reset actions. |
| `ColorValueRow.fieldFormat` | [ColorInspectorView.swift](../Sources/KromoraKit/Views/ColorInspectorView.swift), line 451 | Passed through multiple callers and stored, but never read by the row. Remove the parameter chain or implement one actual formatting policy. |
| `AppChromeState.isMaskingPanelPresented` | [AppChromeState.swift](../Sources/KromoraKit/ViewModels/AppChromeState.swift), line 35 | Written during shutdown but never used to present a panel; included in R03. |

Two additional cleanup targets need a slightly wider check:

- `ImageCollection.isScanning` is initialized/reset to false and never assigned true in application code. The grid's Scanning overlay and the warmer's corresponding admission check therefore describe a state the current package-backed collection does not enter. Replace or remove this leftover folder-scan state after checking the empty/unbound startup path.
- Several root façade properties now exist only for tests after views began observing coordinators directly. Prefer tests against the actual owner, then retire obsolete forwards. Do not remove test synchronization or diagnostics simply because the UI does not read them.

**Verification:** Re-run reference searches after each deletion and compile all targets. Move meaningful behavior checks to surviving boundaries. Keep AppKit delegate methods, SwiftUI protocol witnesses, and other framework entry points regardless of direct textual caller counts.

## R18 — Use the existing finite-clamping helper

**Confidence: high. Small but pervasive repetition.**

[NumericClamping.swift](../Sources/KromoraKit/Models/NumericClamping.swift) already defines a generic finite `clamped(to:default:)`. The source scan found **29 functions named `unit`**, concentrated in analysis values/policies, plus repeated `bounded` and `finiteClamp` functions implementing the same finite-check/min/max pattern.

**Recommendation:** Replace equivalent helpers with the existing primitive, preserving each field's fallback explicitly. Consider a small named unit-interval convenience only if it makes the many value initializers clearer.

Do not normalize all fallbacks to zero: some fields use a model neutral, target median, or other nonzero default. Likewise, share `smoothstep` only where its degenerate-edge convention is intentionally the same; the linear and radial mask helpers currently repeat the same implementation.

**Verification:** Preserve existing value-type tests for NaN, infinity, endpoints, and nonzero defaults. This is primarily a maintainability improvement, not a meaningful standalone performance optimization.

## R19 — Make shared source-transition cleanup explicit

**Confidence: medium. Lifecycle review target, not a recommendation to merge every teardown.**

Evidence:

- [AppViewModel.swift](../Sources/KromoraKit/ViewModels/AppViewModel.swift), `beginLoad`, line 2167: cancels and resets many preview, Auto, masking, histogram, comparison, canvas, metadata, and document-related values.
- The same file, `clearActiveSourceAfterLibraryDeletion`, line 3049: repeats a substantial subset of the cancellation and clearing responsibilities.
- Shutdown contains another related set of resource and task obligations.

The current overlap makes it hard to answer whether a new source-scoped feature was added to every required transition. However, the paths intentionally differ: navigation retains some presentation, deletion clears it, and shutdown must await durable writes and release the package lease in order.

**Recommendation:** Define a small shared transition context and named source-scoped reset operations, with explicit reasons such as replacement, deletion, and shutdown. Have feature owners expose their source-transition obligations. Keep durability barriers and presentation retention choices visible at the composition root.

Avoid a single giant reset method with many Boolean flags. That would hide the existing contracts rather than improve them.

**Verification:** Use the existing source-switch, stale-publication, deletion, first-frame, comparison, and shutdown tests. Add a transition matrix asserting which work is cancelled, which state is cleared/retained, and which accepted writes must be drained.

## R20 — Smaller local extractions worth doing after the above

These are genuine repeated code, but they have less impact than removing obsolete workflows or consolidating inconsistent rules:

1. **Renderer resource initialization.** [RenderEngineResources.swift](../Sources/KromoraKit/Models/RenderEngineResources.swift), cache initialization around lines 218–240 and 249–271, repeats the full cache-construction list for production and injected contexts. Delegate both initializers through one resource setup path while preserving the explicit injected-context device/queue semantics.
2. **White-balance change recording.** [AppleEnhancementReference.swift](../Sources/KromoraKit/Models/PhotoAnalysis/AppleEnhancementReference.swift), `recordWBRaw` and `recordWBStandard`, lines 864 and 888, have identical operational bodies. Share the recorder while keeping source-specific calculation and restraint in the fitter.
3. **Lazy share providers.** [ExportWorkflowCoordinator.swift](../Sources/KromoraKit/ViewModels/ExportWorkflowCoordinator.swift), selected/current sharing around lines 286 and 366, repeats provider registration, task-to-Progress cancellation, job admission, and completion handling. Use one provider factory taking a frozen render closure. Keep batch filename collision handling outside it.
4. **Import-selection tiles.** [PhotosImportReviewView.swift](../Sources/KromoraKit/Views/PhotosImportReviewView.swift), line 81, and [RemovableMediaSelectorView.swift](../Sources/KromoraKit/Views/RemovableMediaSelectorView.swift), around line 160, repeat selection checkmarks, in-library badges, borders, and accessibility wording. Share the tile decoration with slots for thumbnail and warning content, keeping Photos/file loading separate.
5. **LUT grid/probe buffers.** [LookLUTConverter.swift](../Sources/KromoraKit/Models/LookLUTConverter.swift), `makeGridInput` and `makeProbeInput`, lines 279 and 309, repeat float-buffer-to-CIImage construction. A private raster builder is sufficient; no general image abstraction is needed.

Keep validation proportional: initializer/cache tests, existing white-balance fitting tests, share cancellation tests, import selection tests, and LUT conversion verification cover the respective behavior.

## Additional correctness observation

[ImportOutcomeSummary.swift](../Sources/KromoraKit/ViewModels/ImportOutcomeSummary.swift), around line 51, creates failure reasons using the literal string `"(failure.source.name): (failure.reason)"`, without Swift interpolation. The shared summary therefore loses the actual source name and failure reason on that path. This is outside the DRY findings, but it is a concrete reporting defect noticed while tracing import code. A focused future fix should assert the actual filename and reason in the resulting status, not merely failure counts.

## Boundaries to preserve

Some repetition is an intentional expression of different contracts. Do not remove it merely to reduce a line count:

- **One rendering pipeline:** `RenderPipeline` and `CubeLUT` already share core stage and LUT-blend behavior. Continue using these boundaries for preview/export parity.
- **Different raster adapters:** ImageIO thumbnails, Core Image processing, and Metal presentation have different ownership and pixel semantics. Share pure arithmetic and policies beneath them, not their framework objects.
- **Different durable storage contracts:** Transactions, disposable JSON caches, packed thumbnails, and mask sidecars cannot all use one simplistic write helper. Share safe primitives while preserving each owner's ordering, recovery, and synchronization requirements.
- **Persisted migrations:** The macOS 26+/Apple Silicon-only policy is not a reason to drop support for already-written user edits. Remove runtime compatibility surface where unused; retain required decoding/migration at the persistence boundary.
- **Independent source/revision fences:** Repeated checks at asynchronous publication boundaries are safety obligations. A refactor must preserve them at every suspension/publication boundary, even if request context construction becomes shared.
- **CPU/Metal test seams:** Injected/software contexts and deterministic fake engines are not automatically obsolete hardware fallbacks. Keep meaningful testability while isolating it from unnecessary shipping policy.
- **Swift/Metal reference math:** Some mask equations must exist in both languages. Reduce same-language duplication and use parity/golden tests for the cross-language contract instead of adding runtime code generation.
- **Coordinator ownership:** Small protocol adapters and thin forwards are sometimes useful boundaries. Delete confirmed obsolete ones; do not collapse feature coordinators back into `AppViewModel` to make the directory smaller.

## Recommended execution order

1. Unify perspective geometry and raster mask bounds, adding independent parity tests for the currently divergent answers.
2. Remove the legacy masking panel, unused Auto engine, and directly uncalled APIs. Decide explicitly whether to retain the deferred backup/restore subsystem.
3. Consolidate bounded file I/O, cache bookkeeping, and in-flight task mechanics while retaining owner-specific semantics.
4. Introduce shared inspector rows, control/group metadata, and Auto field access.
5. Consolidate render snapshots and repeated pixel/statistics setup, then measure the hot paths affected.
6. Finish smaller construction/view extractions and stale migration comments that no longer describe current behavior.

For implementation work, follow the repository's relevant deterministic and serial lanes, with `swift build`, focused tests, and `git diff --check` as applicable. No display-bound release benchmark is needed to validate these structural refactors. Run it only for an explicitly supervised performance task under the repository's documented rules.

Avoid a single sweeping rewrite: quality is best served by independently reviewable changes that establish one shared rule at a time and remove the obsolete implementation immediately after its replacement is verified.
