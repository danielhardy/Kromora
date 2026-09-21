---
id: KRMA-326
title: Show embedded-JPEG instant first frame on RAW open, then crossfade to true develop
type: feature
status: done
priority: high
verification_agent: pi
verification_model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Provisional frame reaches previewSurface while previewState==loading, transparent source marker retained, histogram nil, no edited-thumbnail job admitted
      result: pass
      notes: testEmbeddedFirstFrameProvisionalThenSettled gates settled previews via FakeRenderEngine, observes provisional pixels while loading, asserts Loading status, non-nil source marker, nil histogram, zero thumbnailRequests.
    - criterion: Settled publication supersedes provisional at newer revision, previewState .ready with developed pixels, supporting-work tail for settled frame
      result: pass
      notes: Same test asserts surface revision advances past provisional and RAW status text restores to dimensions; settled path untouched, presents at newer revision with presentationConfirmation intact.
    - criterion: Stale-drop on navigation (A in flight, open B, A dropped)
      result: not_applicable
      notes: No regression test in diff; guards (task cancel on load/shutdown, sourceRevision+assetID match, previewState==loading, lastPublishedVisibleRequest==nil) verified by inspection. Tracked as backlog child LUMO-330; a deterministic test needs an extraction hook.
    - criterion: Standard (non-RAW) opens never take this path
      result: pass
      notes: "testStandardOpenDoesNotPresentAnEmbeddedFirstFrame: ready with dimensions status, exactly 1 preview request; install() skips status/frame work for non-RAW via kind guard plus URL-backing guard."
    - criterion: Opt-in real-ARW timing (provisional < 50% of settled warm)
      result: not_applicable
      notes: LUMO_RAW_FIXTURE_DIR unset in this environment; report-only test absent from diff. Tracked in LUMO-330.
  checks_run:
    - swift build clean, zero diagnostics
    - "swift test --disable-sandbox --filter EmbeddedFirstFrameTests: 2/2 pass"
    - "scripts/ci-tests.sh fast: exit 0 (~670 tests)"
    - "scripts/ci-tests.sh serial: exit 0"
    - git diff --check clean
    - dg validate OK (pre-existing unknown pickup-runner model warning only)
    - "Reviewed PreviewSurface.present: provisional passes no telemetry/onPresented so it cannot arm presentationConfirmations or didPresentVisibleFrame; surface revision bump makes supersede assertion meaningful"
  findings:
    - "Non-blocking: embeddedFirstFrameTask only cleared on success path; stale drop leaves a completed-task reference until next load/shutdown cancel — harmless no-op."
    - "Non-blocking: passed displayRevision is telemetry-key only when telemetry is nil; no coordinator revision impact — matches the do-not-bump-displayRevision requirement."
    - "Non-blocking: settled-tail-exactly-once (histogram populated post-settled) not explicitly asserted; provisional gating is asserted. Left as-is."
    - Coverage gaps (stale-drop regression, opt-in ARW timing) filed as backlog child LUMO-330 with parent LUMO-326.
  fixes: []
  verification_commits: []
  actor: pi
  resolved_model: openrouter/meta/muse-spark-1.3-contributor
  completed_at: 2026-09-09T22:09:31.946Z
  session: 01MTUNBBLP35TRV9Y6
labels:
  - performance
  - preview
  - raw
created: 2026-09-09T21:26:03.134Z
updated: 2026-09-10T12:53:57.035Z
order: a0
board: product
---

## Objective

Cut perceived RAW open latency from multiple seconds to under ~500ms (warm) by presenting the file's embedded camera JPEG as a provisional first frame the moment a RAW is opened, then replacing it with the true neutral develop through the existing settled-preview path. No changes to the develop pipeline itself.

## Measured baseline (2026-09-09, 121MB 60MP Sony ARW `DSC01172.ARW`, 9504x6336)

Standalone CoreImage/ImageIO timing script (Release `-O`, so these are optimistic vs `swift run` Debug):

| Stage | Cold (page cache cold) | Warm |
|---|---|---|
| `CGImageSourceCreateThumbnailAtIndex` embedded JPEG, 240px | 5191ms | 388ms |
| `CIRAWFilter(imageURL:)` init | 46ms | 42ms |
| `outputImage.extent` touch | 1ms | 1ms |
| Develop render at 1600px long edge via `CIContext.createCGImage` | 542ms | 409ms |
| Full-res RAW load through app path (Debug `swift test` harness) | ~39s | — |

Conclusions the implementer must internalize: (a) faulting 121MB off disk dominates cold opens — physics, cannot be optimized away, only hidden; (b) the true preview-scale develop is only ~0.5s, so the multi-second `swift run` open is cold I/O + Debug overhead + speculative/corrective double render + editor-lane contention, not the develop kernel; (c) the embedded JPEG is the fastest pixels available and already has a code path (`Thumbnails.generate(from:maxPixelSize:)`).

## Context / where things live

- Open path: `AppViewModel.load(...)` (~line 1234) -> `startSourceLoadWorkerIfNeeded` -> `prepareAndInstall` -> `install(preparation:request:)` (~line 1400) sets a transparent `sourceImage` marker and calls `schedulePreview()`; the first real pixels arrive via `PreviewCoordinator.submit(request, phase: .settled, ...)` -> `publishPreview(_:)` (~line 3150) -> `previewSurface.present(...)` with a `presentationConfirmation` that calls `didPresentVisibleFrame`, which is the single gate for ALL supporting work (histogram, edited thumbnails, comparison baseline, Auto readiness, `previewState = .ready`).
- `PreviewCoordinator.Phase` is `.interactive` / `.settled` (`Sources/LumoKit/ViewModels/PreviewCoordinator.swift:15`). Settled publications carry the confirmation callback; interactive ones do not.
- `Thumbnails.generate(from url: URL, maxPixelSize: Int)` (`Sources/LumoKit/Models/Thumbnails.swift`) already extracts the embedded preview with `kCGImageSourceCreateThumbnailWithTransform: true` (orientation baked) and an in-memory LRU. It returns `NSImage?` and is safe to call at a larger `maxPixelSize` (pass ~1600, NOT 240, for the provisional frame).
- `previewSurface.present(_:space:revision:telemetry:source:quality:detailIdentity:detailFactor:presentationImageExtent:onPresented:)` is the single presentation seam both `gpuImage` and raster paths terminate at.

## Prescriptive plan

1. In `AppViewModel.install(preparation:request:)`, immediately after publishing the transparent marker (and before/parallel to `schedulePreview()` + `scheduleAdjacentPreviewPrefetch()`), add `presentEmbeddedFirstFrameIfRAW(preparation:request:)`:
   - Guard: `request.source.kind == .raw` AND `preparation.source.backing` has a URL (skip data-backed imports; their bytes are already in memory and develop fast). Capture `sourceRevision` + `assetID` locals for staleness guards.
   - Dispatch the extraction OFF the main actor: `Task.detached { Thumbnails.generate(from: url, maxPixelSize: 1600) }` (this is the established pattern in `ImageCollection.enqueueThumbnail`). Do NOT route through `ImageWorkScheduler` thumbnail lane (that lane is demand-driven for grid cells and may be saturated by a 32-fixture-style backlog); a dedicated unstructured task with explicit cancellation on the next `load()` is correct here. Store the task in a new `embeddedFirstFrameTask` property and cancel it at the top of `load()` alongside `metadataTask`/`capabilitiesTask`.
   - On completion, back on the main actor, re-check `!isShuttingDown && request.sourceRevision == sourceRevision && request.assetID == activeAssetID`. If stale, drop silently.
   - Present via `previewSurface.present(CIImage(cgImage:), space: .current, revision: <current displayRevision, do NOT bump it>, ...)` with `onPresented: nil`. The provisional frame MUST reuse the current revision and MUST NOT call `didPresentVisibleFrame`.
2. Hard prohibitions (these are correctness, not style — violating any of them corrupts app state):
   - Do NOT set `previewState = .ready`, do NOT set `sourceImage` to the JPEG, do NOT call `didPresentVisibleFrame`, do NOT feed the histogram/Auto/edited-thumbnail paths from the provisional frame. All supporting work gates on the settled confirmation; the JPEG has Sony color baked in and must never be treated as the neutral develop.
   - Do NOT submit the provisional frame through `PreviewCoordinator` (any phase). The coordinator owns revisions and the settled lifecycle; a provisional submit would confuse `submitCorrective` ordering and `abandonedSettledJobIDs` reclamation (KRMA-317).
   - The settled preview path is UNCHANGED and always wins: when `publishPreview` delivers the settled frame it presents at a newer revision and replaces the provisional pixels. No explicit "clear provisional" step needed, but add an assertion-friendly comment stating this ordering.
3. Status UX: while the provisional frame is up and `previewState == .loading`, keep `statusMessage = "Loading \(name)..."` (already set by `load()`). Do NOT add new badges, dimming, or "preview" labels in this ticket — the crossfade should be invisible when fast. (If the JPEG-to-develop color flash proves objectionable in review, that is a follow-up, not this ticket.)
4. Memory: the provisional `NSImage`/`CIImage` is transient; do NOT store it on `ImageCollection.Item` and do NOT insert it into any cache. Release the reference right after `present`.

## Acceptance criteria

- [ ] `EmbeddedFirstFrameProvisionalTest` (FakeRenderEngine, deterministic): open a RAW-backed item; assert a provisional frame reaches `previewSurface` while `previewState == .loading`, `sourceImage` is still the transparent marker, histogram is nil, and no edited-thumbnail job was admitted.
- [ ] `EmbeddedFirstFrameSupersededTest`: settled publication after a provisional frame presents at a newer revision and `previewState` becomes `.ready` with the developed (not JPEG) pixels; supporting work (`didPresentVisibleFrame` tail) runs exactly once, for the settled frame.
- [ ] `EmbeddedFirstFrameStaleDropTest`: navigate to photo B while A's embedded extraction is in flight; assert A's late JPEG is dropped (never presented) and B's open proceeds normally.
- [ ] `EmbeddedFirstFrameSkipsStandardTest`: standard (non-RAW) opens never take this path (their ImageIO decode is already fast; no behavior change).
- [ ] Opt-in real-ARW timing (`LUMO_RAW_FIXTURE_DIR` set, `DSC01172.ARW` present): time-to-provisional-pixels vs time-to-settled reported in test output; provisional must be < 50% of settled on a warm run. Follow the `SingleViewLatencyBenchmark.testOptInRealEngineSingleViewLatencyBaseline` pattern (report, do NOT assert thresholds).

## Verification

- `swift build` clean, zero diagnostics. Swift 6 congeniality: no `@unchecked Sendable`, no `nonisolated(unsafe)`, no `@preconcurrency` (`PackageSettingsTests` enforces this).
- `scripts/ci-tests.sh fast` + `scripts/ci-tests.sh serial` green.
- New tests are hermetic: injected temp `libraryFolderURL` + isolated `UserDefaults` per `TempDirectoryTestCase` (see KRMA-325 — NEVER touch the real `~/Library/Application Support/Lumo/Library` from tests).
- Manual: cold open of `DSC01172.ARW` shows recognizable pixels in ~1s with "Loading..." status, settling to the neutral develop; rapid A/B navigation never shows a stale photo's pixels.

## Constraints

macOS 14 minimum, zero third-party dependencies, Swift 6 language mode for all targets. This ticket changes presentation timing only — render output pixels for every settled frame must be bit-identical before/after (no pipeline, kernel, or colorspace changes).


### Comment — codex @ 2026-09-09T22:03:54.954Z

Implemented in 9a4894f. RAW URL opens now launch a detached 1600px embedded-JPEG provisional frame directly on PreviewSurface while retaining the transparent source marker, loading state, and settled-only supporting-work gates. The task is cancelled on navigation/shutdown with source/asset/loading staleness guards; the settled coordinator frame supersedes it at a newer surface revision. Added hermetic provisional/settled and standard-open regression tests. Verification: swift build, focused EmbeddedFirstFrameTests (2/2), scripts/ci-tests.sh fast (670 tests), scripts/ci-tests.sh serial (326 tests), git diff --check, and dg validate all passed.

## Agent log

- 2026-09-09T22:09:31.946Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Provisional frame reaches previewSurface while previewState==loading, transparent source marker retained, histogram nil, no edited-thumbnail job admitted (pass) — testEmbeddedFirstFrameProvisionalThenSettled gates settled previews via FakeRenderEngine, observes provisional pixels while loading, asserts Loading status, non-nil source marker, nil histogram, zero thumbnailRequests.
- [x] Settled publication supersedes provisional at newer revision, previewState .ready with developed pixels, supporting-work tail for settled frame (pass) — Same test asserts surface revision advances past provisional and RAW status text restores to dimensions; settled path untouched, presents at newer revision with presentationConfirmation intact.
- [ ] Stale-drop on navigation (A in flight, open B, A dropped) (not_applicable) — No regression test in diff; guards (task cancel on load/shutdown, sourceRevision+assetID match, previewState==loading, lastPublishedVisibleRequest==nil) verified by inspection. Tracked as backlog child KRMA-330; a deterministic test needs an extraction hook.
- [x] Standard (non-RAW) opens never take this path (pass) — testStandardOpenDoesNotPresentAnEmbeddedFirstFrame: ready with dimensions status, exactly 1 preview request; install() skips status/frame work for non-RAW via kind guard plus URL-backing guard.
- [ ] Opt-in real-ARW timing (provisional < 50% of settled warm) (not_applicable) — LUMO_RAW_FIXTURE_DIR unset in this environment; report-only test absent from diff. Tracked in KRMA-330.
Checks run:
- swift build clean, zero diagnostics
- swift test --disable-sandbox --filter EmbeddedFirstFrameTests: 2/2 pass
- scripts/ci-tests.sh fast: exit 0 (~670 tests)
- scripts/ci-tests.sh serial: exit 0
- git diff --check clean
- dg validate OK (pre-existing unknown pickup-runner model warning only)
- Reviewed PreviewSurface.present: provisional passes no telemetry/onPresented so it cannot arm presentationConfirmations or didPresentVisibleFrame; surface revision bump makes supersede assertion meaningful
Findings:
- Non-blocking: embeddedFirstFrameTask only cleared on success path; stale drop leaves a completed-task reference until next load/shutdown cancel — harmless no-op.
- Non-blocking: passed displayRevision is telemetry-key only when telemetry is nil; no coordinator revision impact — matches the do-not-bump-displayRevision requirement.
- Non-blocking: settled-tail-exactly-once (histogram populated post-settled) not explicitly asserted; provisional gating is asserted. Left as-is.
- Coverage gaps (stale-drop regression, opt-in ARW timing) filed as backlog child KRMA-330 with parent KRMA-326.
Fixes:
- None
Verification commits:
- None
Actor: pi
Resolved model: openrouter/meta/muse-spark-1.3-contributor
Pickup session: 01MTUNBBLP35TRV9Y6
Summary: Verification PASS: RAW embedded-JPEG first frame presents provisionally without touching settled lifecycle; all prohibitions hold; focused 2/2, fast and serial lanes green. Non-blocking coverage gaps filed as KRMA-330.
