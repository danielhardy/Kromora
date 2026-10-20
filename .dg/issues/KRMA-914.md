---
id: KRMA-914
title: "Smart Mask Discovery: develop a signature visual experience beyond the initial prototype"
type: feature
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The revised experience is reviewed in motion and addresses the user's "pretty underwhelming" assessment with a distinctive, coherent discovery-and-reveal treatment. Record the visual review outcome; technical checks alone do not complete this criterion.
      result: pass
      notes: The user accepted the current Darkroom Development treatment in motion on 2026-10-19, including whole-image waiting flowing into the reveal and the completed mask becoming visible after overlays were hidden with O.
    - criterion: The original photograph retains its integrity and remains readable across bright/dark scenes, portraits, landscapes, and detailed backgrounds. Review at representative canvas sizes and zoom levels.
      result: pass
      notes: The recorded human review accepted the current rendering. The offscreen Metal test confirms a transparent photo perimeter, bounded waiting overlay alpha below 90/255, and mask-shaped lift from actual coverage; geometry tests cover portrait/landscape placement, crop, pan, zoom, Retina scale, flips, rotation, and perspective. The review record does not enumerate a separate full image-by-canvas matrix.
    - criterion: A request produces immediate visual acknowledgement, with no runtime shader compilation or heavy preparation on the request path.
      result: pass
      notes: The workflow begins presentation state before starting analysis; the canvas prewarms its pipeline from the bundled metallib. The runtime shader-source compilation gate passed.
    - criterion: Millisecond/cached results, approximately 30-second operations, and waits exceeding one minute all have intentional choreography without a manufactured delay or fake progress.
      result: pass
      notes: Cached results enter reveal immediately; waiting exposure settles without progress or a deadline. Focused timing tests cover immediate, 30-second, 90-second, and longer elapsed values.
    - criterion: Successful reveal uses the actual admitted mask pixels and remains aligned through all supported document and canvas geometry.
      result: pass
      notes: The overlay loads pixels through the returned mask reference and maps them with the inverse document/canvas transform. Shader coverage and geometry tests passed.
    - criterion: Success commits the durable mask immediately; discovery never triggers extra inference, changes provider behavior, or delays mask availability.
      result: pass
      notes: The masking coordinator commits the result before resolving presentation state; the overlay only reads stored pixels. Workflow tests cover immediate durable creation and component insertion.
    - criterion: Failure, cancellation, empty/unavailable masks, source changes, and superseded requests never reveal fabricated or stale geometry.
      result: pass
      notes: Request IDs, cancellation, source revision/fingerprint admission, and empty/error exits gate the reveal. Focused lifecycle tests passed.
    - criterion: Discovery remains independently owned and swappable, with narrow integration into the existing canvas and workflow.
      result: pass
      notes: Discovery state and the transparent Metal surface are separate from PreviewSurface and mask analysis; canvas integration injects only the stored-pixel reader.
    - criterion: Fragment work, drawable resolution, frame cadence, allocations, and queued GPU work remain bounded. Waiting frames do not evaluate the photo's Core Image graph. Hidden/inactive windows suspend animation, and Reduce Motion has an intentional still treatment.
      result: pass
      notes: Structural limits are a 512-pixel mask raster, 960-pixel drawable, 24/12 fps cadence, one command buffer in flight, fixed shader loops, hidden/inactive suspension, and a still Reduce Motion path. Raster-cap and shader/resource tests passed.
    - criterion: Record evidence appropriate to the final design for resource use and interference with analysis. Clearly distinguish structural limits from measured performance; near-zero contention is not yet established.
      result: pass
      notes: Structural bounds are recorded in docs/ENGINEERING_GUIDE.md and confirmed by code/tests. No GPU-contention measurement was run, and no near-zero interference claim is made.
    - criterion: Focused lifecycle, geometry, shader/resource, and relevant workflow tests pass; the application builds and the production package verifies.
      result: pass
      notes: The declared strict build, focused 76-test suite, shader freshness check, and production package verification all passed.
  checks_run:
    - swift build -Xswiftc -warnings-as-errors — exit 0, no compiler diagnostics
    - swift test --no-parallel --filter 'MaskDiscoveryTests|MaskingWorkflowCoordinatorTests|MetalKernelParityTests|GeometryPointMappingTests|CanvasNavigationTests|PackageSettingsTests|XcodeProjectInvariantTests' — exit 0, 76 tests passed
    - scripts/build-metal-libraries.sh --check — exit 0
    - scripts/app-store-build.sh — exit 0; arm64 app, signature, entitlements, and resources verified; emitted the existing AppIntents metadata-extraction notice
    - git diff --check — exit 0
    - dg validate — exit 0; KRMA-914 absolute-path warning cleared, unrelated project/model-name and historical-event warnings remain
    - Human in-motion review recorded 2026-10-19 — current interaction accepted, including hidden-overlay restoration
  findings:
    - GPU contention/interference was not measured. Structural limits are confirmed, and no near-zero contention claim is made.
  fixes:
    - Changed the KRMA-914 source-context header to say paths are relative to the project root, removing its absolute local filesystem path.
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-19T22:21:19.577Z
  session: local session omitted
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - masking
  - metal
  - ux
  - design
  - performance
created: 2026-10-12T21:56:49.211Z
updated: 2026-10-19T22:21:19.581Z
blockers:
  - id: evt_mv6x4j4h_ul6zvn
    type: human
    reason: Remaining acceptance needs a live, in-motion visual review of the 'Darkroom Development' treatment (5a090b2c) across bright/dark/portrait/landscape/busy photos, canvas sizes and zoom. The ticket's prior feedback was 'underwhelming', and I cannot see motion in a non-interactive run.
    action: Run 'swift run', request a Smart Mask on several photos, and record accept / what to change. Say whether to build the optional extras (cursor-as-safelight, haptic at edge lock-in, sound, longer-wait choreography). A supervised GPU-contention measurement per CLAUDE.md is also needed if near-zero interference is to be claimed.
    created_at: 2026-10-13T16:51:38.321Z
    resolved_at: 2026-10-14T12:23:35.454Z
    resolved_by: web
order: z
board: product
blocked_reason: Remaining acceptance needs a live, in-motion visual review of the 'Darkroom Development' treatment (5a090b2c) across bright/dark/portrait/landscape/busy photos, canvas sizes and zoom. The ticket's prior feedback was 'underwhelming', and I cannot see motion in a non-interactive run.
blocked_action: Run 'swift run', request a Smart Mask on several photos, and record accept / what to change. Say whether to build the optional extras (cursor-as-safelight, haptic at edge lock-in, sound, longer-wait choreography). A supervised GPU-contention measurement per CLAUDE.md is also needed if near-zero interference is to be claimed.
blocked_from_status: ready
context:
  files:
    - Sources/KromoraKit/Models/MaskDiscoveryState.swift
    - Sources/KromoraKit/Models/MaskDiscoveryGeometry.swift
    - Sources/KromoraKit/Views/MaskDiscoveryOverlay.swift
    - Sources/KromoraKit/Resources/MaskDiscovery.metal
    - Sources/KromoraKit/ViewModels/MaskingWorkflowCoordinator.swift
    - Sources/KromoraKit/Views/PreviewView.swift
    - Sources/KromoraKit/Views/PreviewSurface.swift
    - Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift
    - Sources/KromoraKit/Models/PhotoAnalysis/RegionMask.swift
    - Sources/KromoraKit/Models/PhotoAnalysis/MaskStore.swift
    - Sources/KromoraKit/Models/GeometryPointMapping.swift
    - Sources/KromoraKit/Models/CanvasNavigation.swift
    - Tests/KromoraKitTests/MaskDiscoveryTests.swift
    - Tests/KromoraKitTests/MaskingWorkflowCoordinatorTests.swift
    - Tests/KromoraKitTests/MetalKernelParityTests.swift
    - scripts/build-metal-libraries.sh
  docs:
    - CLAUDE.md
    - .dg/AGENTS.md
    - docs/ENGINEERING_GUIDE.md
    - docs/APP_ARCHITECTURE.md
    - docs/TESTING.md
  issues: []
  commands:
    - swift build -Xswiftc -warnings-as-errors
    - swift test --no-parallel --filter 'MaskDiscoveryTests|MaskingWorkflowCoordinatorTests|MetalKernelParityTests|GeometryPointMappingTests|CanvasNavigationTests|PackageSettingsTests|XcodeProjectInvariantTests'
    - scripts/build-metal-libraries.sh --check
    - scripts/app-store-build.sh
    - git diff --check
    - dg validate
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T13:12:54.371Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Create Kromora's signature Smart Mask Discovery interaction: **a photograph → a photograph that Kromora understands**. Build a visually extraordinary but restrained experience around the existing asynchronous intelligent-mask operation, culminating in a reveal of the actual returned mask.

This ticket is intentionally in **backlog**. The first implementation is a technical and visual starting point, not an accepted final design. The user's assessment after that implementation: **"Overall this is a start but pretty underwhelming."** Carry that feedback into the next iteration; passing tests and a working transition do not establish that the visual brief has been met. The visual direction needs further exploration and review in motion.

## Current implementation baseline

The initial prototype is committed on `main` as **`239e6b80aa13c36c35697aae635888246cca4339`** — `KRMA-914: add initial Smart Mask Discovery prototype`. The commit contains 13 implementation, shader/resource, test, and engineering-guide files (782 insertions, 3 deletions, plus the rebuilt presentation library). The detailed implementation and verification comment below remains the historical record of the initial work; the later commit comment supersedes its statement that the prototype is uncommitted.

The ticket remains **backlog**. Committing this starting point does not establish visual acceptance or completion. The user's underwhelming assessment, the remaining visual-direction work, and the unmeasured live GPU contention still apply.

## Original mission and full product brief

Kromora already supports intelligent masking using Apple's existing on-device vision and segmentation frameworks. Mask analysis is functional and typically takes approximately 30 seconds. **Do not rebuild, replace, or modify the underlying mask-analysis implementation.** The mission is exclusively to create an exceptional visual experience around that existing asynchronous operation.

Think of this as creating a signature transition between two states: **a photograph → a photograph that Kromora understands**.

The available events are:

1. The user requests an intelligent mask.
2. Apple's analysis finishes, fails, or is canceled.
3. Kromora receives the resulting mask geometry.

There is no reliable intermediate analysis progress or partial segmentation information. The experience must not pretend to represent Apple's real computational steps. It is an artistic expression of discovery, not a visualization of internal processing.

Build an independently owned, swappable Metal-based visual experience that operates during the waiting period and culminates in a beautiful reveal using the actual returned mask. Explore original procedural effects inspired by optical phenomena, subtle luminous structures, organic movement, and the photographic image itself.

The experience should be:

- Visually extraordinary but not over the top.
- Instantaneously responsive.
- Extremely lightweight while Apple's processing is running.
- Independent of the mask-generation engine.
- Encapsulated as a replaceable animation subsystem.
- Compatible with the existing Metal canvas without deeply modifying its renderer's behavior (outside of this moment).
- Capable of adapting to operations lasting anywhere from milliseconds to more than a minute.
- Polished enough that the actual mask appears as the natural conclusion of the preceding animation.
- Could have a "finally" when the mask is ready
- Could playfully interact with the mouse to make it more interesting (not a must but an idea)
- Bonus points for things that feel magical, technical, photographically familar/adjacent, fun
- could even have sound if we thought it made sense

Prioritize the beauty of the interaction, the integrity of the photograph, and near-zero interference with Apple's processing. **The intelligence is already there. Give it a sense of wonder.**

## Refinement against the existing code

- `MaskingWorkflowCoordinator.createSmartMask` and `addSmartMaskComponent` already own request invocation, cancellation/supersession, result admission, and durable recipe insertion. Add or retain presentation events at those boundaries; preserve existing inference, validation, caching, retry, and document-commit behavior.
- Successful analysis returns a `RegionMask` with a `RegionMaskReference`. Actual pixels are available through the existing `PhotoAnalysisCoordinator.pixels(for:)` / `MaskStore` read boundary. Use those pixels for the reveal; no extra inference is needed.
- A successful mask must commit immediately. Animation timing and display-raster preparation must not delay creating the mask or adding its component.
- The first pass adds `MaskDiscoveryState`, `MaskDiscoveryOverlay`, `MaskDiscoveryGeometry`, a disposable display raster, and precompiled `MaskDiscovery.metal` shaders. The overlay consumes request/completion/dismissal events plus an injected asynchronous stored-pixel reader. See the separate implementation comment for the exact work and verification already completed.
- `PreviewSurface` remains responsible for the photograph and stays independent of discovery scheduling. The first pass places a transparent Metal surface over it from `PreviewView`.
- Document rotation, flips, straighten, perspective, crop, pan, zoom, and Retina scaling must remain aligned with the true returned mask. The current prototype has an inverse geometry mapping and focused tests for this.
- Discovery state, imagery, and timers are presentation-only. They must not affect persisted edits, undo/history, export output, or mask-overlay preferences.

## Design work remaining

The current treatment uses faint drifting interference ribbons, a restrained color wash, and a brief boundary glint. It is functional, but the user found the result underwhelming. Revisit the visual concept and choreography; the existing shader is replaceable and does not prescribe the final aesthetic.

Explore optical/organic structure and photographic coherence that make the interaction distinctive and legible while preserving the image. Investigate the waiting treatment, the transition from indeterminate waiting into actual geometry, and the final reveal as one continuous composition. Judge the work in motion across different photographs and actual canvas sizes. Increased brightness alone is not an acceptance criterion.

A quick cached result should enter the reveal without an artificial wait. A long analysis should remain calm and intentional, with no implied deadline, growing percentage, invented regions, or fabricated partial results. Failure, empty/unavailable results, cancellation, supersession, and source changes need a graceful and truthful exit.

## Acceptance criteria

- [ ] The revised experience is reviewed in motion and addresses the user's "pretty underwhelming" assessment with a distinctive, coherent discovery-and-reveal treatment. Record the visual review outcome; technical checks alone do not complete this criterion.
- [ ] The original photograph retains its integrity and remains readable across bright/dark scenes, portraits, landscapes, and detailed backgrounds. Review at representative canvas sizes and zoom levels.
- [ ] A request produces immediate visual acknowledgement, with no runtime shader compilation or heavy preparation on the request path.
- [ ] Millisecond/cached results, approximately 30-second operations, and waits exceeding one minute all have intentional choreography without a manufactured delay or fake progress.
- [ ] Successful reveal uses the actual admitted mask pixels and remains aligned through all supported document and canvas geometry.
- [ ] Success commits the durable mask immediately; discovery never triggers extra inference, changes provider behavior, or delays mask availability.
- [ ] Failure, cancellation, empty/unavailable masks, source changes, and superseded requests never reveal fabricated or stale geometry.
- [ ] Discovery remains independently owned and swappable, with narrow integration into the existing canvas and workflow.
- [ ] Fragment work, drawable resolution, frame cadence, allocations, and queued GPU work remain bounded. Waiting frames do not evaluate the photo's Core Image graph. Hidden/inactive windows suspend animation, and Reduce Motion has an intentional still treatment.
- [ ] Record evidence appropriate to the final design for resource use and interference with analysis. Clearly distinguish structural limits from measured performance; near-zero contention is not yet established.
- [ ] Focused lifecycle, geometry, shader/resource, and relevant workflow tests pass; the application builds and the production package verifies.

## Source and documentation context

Paths are relative to the project root:

- `Sources/KromoraKit/Models/MaskDiscoveryState.swift`
- `Sources/KromoraKit/Models/MaskDiscoveryGeometry.swift`
- `Sources/KromoraKit/Views/MaskDiscoveryOverlay.swift`
- `Sources/KromoraKit/Resources/MaskDiscovery.metal`
- `Sources/KromoraKit/ViewModels/MaskingWorkflowCoordinator.swift`
- `Sources/KromoraKit/Views/PreviewView.swift`
- `Sources/KromoraKit/Views/PreviewSurface.swift` — existing renderer; preserve its ownership.
- `Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift`, `RegionMask.swift`, and `MaskStore.swift` — existing analysis/store contracts; read for context, leave analysis implementation unchanged.
- `Sources/KromoraKit/Models/GeometryPointMapping.swift` and `CanvasNavigation.swift`
- `Tests/KromoraKitTests/MaskDiscoveryTests.swift`
- `Tests/KromoraKitTests/MaskingWorkflowCoordinatorTests.swift`
- `Tests/KromoraKitTests/MetalKernelParityTests.swift`
- `scripts/build-metal-libraries.sh`
- `CLAUDE.md`, `.dg/AGENTS.md`, `docs/ENGINEERING_GUIDE.md`, `docs/APP_ARCHITECTURE.md`, and `docs/TESTING.md`

## Verification and workflow

Rebuild checked-in shader libraries after changing Metal sources with `scripts/build-metal-libraries.sh`, and verify freshness with `scripts/build-metal-libraries.sh --check`.

Relevant checks:

```sh
swift build -Xswiftc -warnings-as-errors
swift test --no-parallel --filter 'MaskDiscoveryTests|MaskingWorkflowCoordinatorTests|MetalKernelParityTests|GeometryPointMappingTests|CanvasNavigationTests|PackageSettingsTests|XcodeProjectInvariantTests'
scripts/app-store-build.sh
git diff --check
dg validate
```

Follow `CLAUDE.md` for any profiling. Display-bound release capture harnesses require an explicitly supervised performance task; they are not routine per-ticket checks. Do not substitute repeated release captures for targeted validation or visual review.

Kromora targets macOS 26+ on Apple Silicon, uses Swift 6, Apple frameworks only, and precompiled Metal shaders. Preserve unrelated working-tree changes. The initial prototype is committed as `239e6b80aa13c36c35697aae635888246cca4339` (`KRMA-914: add initial Smart Mask Discovery prototype`); inspect the working tree before picking up this backlog item and preserve the work described in the comments. This ticket does not authorize publishing, pushing, or promoting the work out of backlog.


### Comment — codex @ 2026-10-12T21:58:28.224Z

Initial prototype implemented in the originating chat on 2026-10-12. This is a starting point, not a completed or visually accepted feature. The user has described it as "a start but pretty underwhelming," and requested that the work be captured in the backlog.

What is already implemented:

- `Models/MaskDiscoveryState.swift`: a separate observable presentation boundary with request IDs and waiting, resolved-reference, and ending states. Stale completions and teardown cannot overwrite a newer request. Timing envelopes handle immediate results and indefinite waits without reporting analysis progress.
- `ViewModels/MaskingWorkflowCoordinator.swift`: narrow presentation hooks for both `createSmartMask` and `addSmartMaskComponent`, plus reset on cancellation/source switch, supersession, shutdown, and the existing Info-inspector handoff. Successful mask recipes still commit immediately; the animation does not gate that commit.
- `Views/MaskDiscoveryOverlay.swift`: a separate transparent `MTKView` over the existing canvas. It consumes the state and an injected asynchronous stored-pixel reader, rather than depending on the mask-generation engine. The GPU device is shared with presentation, but the animation owns its pipeline, command queue, textures, timers, and explicit teardown.
- `Resources/MaskDiscovery.metal`: faint, slowly drifting interference ribbons while waiting; a color wash and moving boundary glint reveal the returned coverage, then recede. Current reveal duration is 1.65 seconds. These visual choices are provisional and should be revisited.
- `Models/MaskDiscoveryGeometry.swift`: an inverse projective mapping for rotation, flips, straighten, perspective, crop, pan/zoom, and backing scale; a disposable 8-bit display mask capped at 512 pixels on the longest edge. Original analysis pixels retain their existing precision and ownership.
- Rendering is bounded to a 960-pixel drawable longest edge, 24 fps normally / 12 under power or thermal constraints, and one frame in flight. Waiting frames use the transparent shader only and do not rerender the photograph. Hidden/inactive windows pause animation. Reduce Motion uses a still treatment. Power/thermal notifications explicitly hop to the main actor; observers/timers are removed during teardown.
- `Views/PreviewView.swift`: mounts the overlay in the edited masking canvas, excludes original comparison/crop/loading presentations, and injects the existing stored-pixel reader. Discovery is discarded on presentation teardown.
- `scripts/build-metal-libraries.sh`, `KromoraPresentation.metallib`, and its checksum: include and precompile the new shader. No runtime shader-source compilation was added.
- `docs/ENGINEERING_GUIDE.md`: documents discovery ownership, resource limits, and separation from analysis/edit/export state.

The underlying files in `Models/PhotoAnalysis` and the existing `Views/PreviewSurface.swift` renderer were not changed for this prototype. Existing analysis, provider, segmentation, caching, and render implementation were preserved. Unrelated retouch, preview-admission, and DispatchGraph changes were left untouched.

Verification already completed:

- Final strict application build: `swift build --scratch-path /tmp/kromora-discovery-build -Xswiftc -warnings-as-errors` — passed, zero application compiler warnings.
- Final selected test run: `swift test --scratch-path /tmp/kromora-discovery-build --no-parallel --filter 'MaskDiscoveryTests|MaskingWorkflowCoordinatorTests|MetalKernelParityTests|GeometryPointMappingTests|CanvasNavigationTests|PackageSettingsTests|XcodeProjectInvariantTests'` — 70 tests passed, zero failures.
- Coverage includes request supersession/cancellation, empty/failure exits, immediate commit and component insertion, short/long timing envelopes, geometry mapping, raster orientation/memory cap, resource freshness and shader loading, plus real offscreen GPU checks proving asymmetric actual coverage, transparent photo perimeter, bounded waiting opacity, and complete reveal fade-out.
- `scripts/build-metal-libraries.sh --check` and `git diff --check` — passed.
- Final `scripts/app-store-build.sh` — passed; packaged app resources, arm64 executable, signature, and entitlements verified. Build emits the existing AppIntents metadata-extraction notice because there is no AppIntents dependency.
- Offscreen waiting frames were inspected over the repository's golden-hour landscape fixture. This only establishes a basic static visual check; it does not establish exceptional motion/choreography or user acceptance.
- `swift build --build-tests -Xswiftc -warnings-as-errors` encountered an unrelated pre-existing unused `name` variable in `Tests/KromoraKitTests/ColorMixerTests.swift:193`. That file was not modified. The normal selected tests and strict application-only build passed.

Open work and limitations:

- The user has not accepted the visual result; their underwhelming assessment is the principal remaining issue. Treat the current effect as replaceable scaffolding and develop the visual direction further.
- There has been no supervised live GPU-contention benchmark during Apple's analysis, no quantified near-zero-interference result, and no completed live visual review across diverse photographs/canvas sizes.
- The prototype is still uncommitted in the shared working tree. No branch, commit, push, PR, or distribution was created for this work. This backlog ticket records it without claiming implementation completion or moving it to review.


### Comment — codex @ 2026-10-12T22:09:00.689Z

Committed the initial Smart Mask Discovery prototype at the user's request.

- Commit: `239e6b80aa13c36c35697aae635888246cca4339`
- Subject: `KRMA-914: add initial Smart Mask Discovery prototype`
- Branch: `main` (existing branch)
- Scope: 13 files; 782 insertions, 3 deletions, and rebuilt `KromoraPresentation.metallib`.
- Includes the independently owned discovery state, geometry/display-raster mapping, transparent Metal overlay, procedural shader, request/result lifecycle hooks, canvas integration, shader build/checksum updates, focused tests, and engineering-guide documentation.
- Underlying mask-analysis implementation and `PreviewSurface.swift` remain unchanged. Unrelated preview-admission and other ticket changes were excluded from the commit.

Validation recorded for the committed implementation: strict application build passed; the selected 70 tests passed with zero failures; production package verification passed; shader freshness and whitespace checks passed. This was a commit/bookkeeping action, so the already-completed build and test runs were not repeated. The pre-existing `ColorMixerTests.swift:193` warning still prevents the strict all-test warning gate from passing; live GPU contention and the final motion/visual-quality review remain unverified.

KRMA-914 stays in **backlog**. The prototype remains a starting point that the user found underwhelming; no completion or visual acceptance is implied. No push, PR, merge, or distribution was performed. This comment and the current-baseline section supersede the earlier historical note that the prototype was uncommitted.


### Comment — claude @ 2026-10-13T01:11:53.310Z

Second iteration committed on main as 5a090b2c8763e1c2ca0de8347e994a7ef81ab2c1 (KRMA-914: replace discovery visuals with darkroom development treatment). Answers the 'pretty underwhelming' assessment of the ribbon prototype (239e6b80); the ticket stays in backlog and is NOT visually accepted.

Design: 'Darkroom Development'. Waiting = amber safelight, radial vignette, faint drifting developer-tray light, breathing silver grain; no progress, deadline, or invented regions. Reveal (actual admitted mask pixels) = silver grain nucleates where returned coverage is strongest and sparkles, then coalesces; warm halation blooms just outside the true boundary; a crisp pearl 'fixer' edge locks in; lights come up. Reduce Motion keeps the still coverage tint. Reveal duration 1.65s -> 2.4s. Uniform ABI and overlay Swift unchanged; MaskDiscovery.metal rewritten and KromoraPresentation.metallib rebuilt (--check passes).

Visual review so far: offscreen contact sheets (waiting + 8 reveal frames) over ai-clear-backlit-portrait with a real Vision foreground-instance mask. Iterated: first pass caustics invisible and reveal read as grey fog; second pass caustics overpowered the face; third pass restrained (current). STILL OPEN: live review in motion, other fixtures (low-key portrait, busy street, high-key), canvas sizes/zoom, and the user's acceptance.

Test change to note: testDiscoveryShaderUsesActualCoverageAndLeavesPhotoPerimeterTransparent asserted single-pixel alpha from the old design. It now asserts mean light over the covered quadrant exceeds uncovered quadrants (coverage-following), surroundings alpha < 40 (bounded burn, never filled), perimeter alpha 0, full recede at reveal=1. Waiting alpha cap raised 40 -> 90 to allow the vignette; revisit if the dimming proves too heavy in motion.

Verification: strict swift build passes; 70 focused tests pass (MaskDiscovery, MetalKernelParity, MaskingWorkflowCoordinator, PackageSettings, GeometryPointMapping, CanvasNavigation, XcodeProjectInvariant); git diff --check clean. scripts/app-store-build.sh not re-run for this iteration. No contention measurement.

Not built yet (ideas from the brief): cursor-as-safelight interaction, trackpad haptic at fixer-edge lock-in, optional sound, long-wait choreography beyond the existing 8-20s settle.


### Comment - human

The current implementation works well but is missing two critical features. 
1. When the animation is resolved the mask should alwasy be shown (even if the masks setting is hidden (o key) turn it back on) -- this is critical in showing the results so it should switch the masks back on.
2. When it is in the "discovering" phase, it would be more ideal if the entire image had a similar animation as it does right before it resolves. It would feel like a more natural transition from "discovering people" to "found someone" or discovering background to found background


### Comment — claude @ 2026-10-14T13:12:53.860Z

Addressed the two human-requested features in cfcd7c7e. (1) On resolve, both createSmartMask and addSmartMaskComponent now set interactionState.showOverlay = true, so the returned mask is shown even if overlays were hidden (new test testResolvedSmartMaskTurnsHiddenOverlayBackOn). (2) Waiting phase now carries the reveal's vocabulary across the whole frame: slow uniform waves of silver-grain nucleation and sparkle (a field, not a region; no coverage or progress implied) fading into the reveal. MaskDiscovery.metal rewritten and metallib rebuilt (--check passes). Verified: strict swift build passes; 71 focused tests pass; git diff --check clean. NOT run: app-store-build.sh, live in-motion visual review, GPU contention measurement. Visual acceptance remains the user's call.


### Comment — codex @ 2026-10-19T22:01:40.968Z

Human visual acceptance PASSED on 2026-10-19. During the review session the user was asked to hide mask overlays with O, then create a Smart Mask and check both the whole-image waiting animation flowing into the reveal and the finished mask becoming visible automatically despite the previously hidden overlay. The user replied "this works - shiop it". Record approval of the current interaction, including those two requested features; this supersedes the earlier lack of human acceptance for the current design. No additional cursor, haptic, sound or other optional effects were requested. This is approval of this feature within the ongoing ticket review, not a request to publish a release or push the repository. Resume normal technical verification with the latest implementation and resource/package checks; this review session ran no new build/tests and established no GPU-contention or near-zero-interference measurement. Preserve the distinction between the accepted visual result and any unmeasured performance claims.

## Agent log

- 2026-10-19T22:21:19.577Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The revised experience is reviewed in motion and addresses the user's "pretty underwhelming" assessment with a distinctive, coherent discovery-and-reveal treatment. Record the visual review outcome; technical checks alone do not complete this criterion. (pass) — The user accepted the current Darkroom Development treatment in motion on 2026-10-19, including whole-image waiting flowing into the reveal and the completed mask becoming visible after overlays were hidden with O.
- [x] The original photograph retains its integrity and remains readable across bright/dark scenes, portraits, landscapes, and detailed backgrounds. Review at representative canvas sizes and zoom levels. (pass) — The recorded human review accepted the current rendering. The offscreen Metal test confirms a transparent photo perimeter, bounded waiting overlay alpha below 90/255, and mask-shaped lift from actual coverage; geometry tests cover portrait/landscape placement, crop, pan, zoom, Retina scale, flips, rotation, and perspective. The review record does not enumerate a separate full image-by-canvas matrix.
- [x] A request produces immediate visual acknowledgement, with no runtime shader compilation or heavy preparation on the request path. (pass) — The workflow begins presentation state before starting analysis; the canvas prewarms its pipeline from the bundled metallib. The runtime shader-source compilation gate passed.
- [x] Millisecond/cached results, approximately 30-second operations, and waits exceeding one minute all have intentional choreography without a manufactured delay or fake progress. (pass) — Cached results enter reveal immediately; waiting exposure settles without progress or a deadline. Focused timing tests cover immediate, 30-second, 90-second, and longer elapsed values.
- [x] Successful reveal uses the actual admitted mask pixels and remains aligned through all supported document and canvas geometry. (pass) — The overlay loads pixels through the returned mask reference and maps them with the inverse document/canvas transform. Shader coverage and geometry tests passed.
- [x] Success commits the durable mask immediately; discovery never triggers extra inference, changes provider behavior, or delays mask availability. (pass) — The masking coordinator commits the result before resolving presentation state; the overlay only reads stored pixels. Workflow tests cover immediate durable creation and component insertion.
- [x] Failure, cancellation, empty/unavailable masks, source changes, and superseded requests never reveal fabricated or stale geometry. (pass) — Request IDs, cancellation, source revision/fingerprint admission, and empty/error exits gate the reveal. Focused lifecycle tests passed.
- [x] Discovery remains independently owned and swappable, with narrow integration into the existing canvas and workflow. (pass) — Discovery state and the transparent Metal surface are separate from PreviewSurface and mask analysis; canvas integration injects only the stored-pixel reader.
- [x] Fragment work, drawable resolution, frame cadence, allocations, and queued GPU work remain bounded. Waiting frames do not evaluate the photo's Core Image graph. Hidden/inactive windows suspend animation, and Reduce Motion has an intentional still treatment. (pass) — Structural limits are a 512-pixel mask raster, 960-pixel drawable, 24/12 fps cadence, one command buffer in flight, fixed shader loops, hidden/inactive suspension, and a still Reduce Motion path. Raster-cap and shader/resource tests passed.
- [x] Record evidence appropriate to the final design for resource use and interference with analysis. Clearly distinguish structural limits from measured performance; near-zero contention is not yet established. (pass) — Structural bounds are recorded in docs/ENGINEERING_GUIDE.md and confirmed by code/tests. No GPU-contention measurement was run, and no near-zero interference claim is made.
- [x] Focused lifecycle, geometry, shader/resource, and relevant workflow tests pass; the application builds and the production package verifies. (pass) — The declared strict build, focused 76-test suite, shader freshness check, and production package verification all passed.
Checks run:
- swift build -Xswiftc -warnings-as-errors — exit 0, no compiler diagnostics
- swift test --no-parallel --filter 'MaskDiscoveryTests|MaskingWorkflowCoordinatorTests|MetalKernelParityTests|GeometryPointMappingTests|CanvasNavigationTests|PackageSettingsTests|XcodeProjectInvariantTests' — exit 0, 76 tests passed
- scripts/build-metal-libraries.sh --check — exit 0
- scripts/app-store-build.sh — exit 0; arm64 app, signature, entitlements, and resources verified; emitted the existing AppIntents metadata-extraction notice
- git diff --check — exit 0
- dg validate — exit 0; KRMA-914 absolute-path warning cleared, unrelated project/model-name and historical-event warnings remain
- Human in-motion review recorded 2026-10-19 — current interaction accepted, including hidden-overlay restoration
Findings:
- GPU contention/interference was not measured. Structural limits are confirmed, and no near-zero contention claim is made.
Fixes:
- Changed the KRMA-914 source-context header to say paths are relative to the project root, removing its absolute local filesystem path.
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: local session omitted
Summary: Verification passed: human in-motion acceptance and all declared technical checks passed; GPU contention remains unmeasured and no near-zero claim is made.
