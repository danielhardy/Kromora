---
id: KRMA-991
title: "Photos import review: thumbnails never resolve (placeholders stay forever)"
type: bug
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Reproduce the reporter scenario with real Photos assets and record the root cause in the ticket.
      result: pass
      notes: "The issue comments record the packaged Xcode app live check: after granting Full Access, all three selected assets resolved thumbnails and filenames. The root cause was missing PhotoKit read authorization; PhotosPicker's private selection access alone did not authorize the PhotoKit fetch. The provider now requests read/write authorization before lookup."
    - criterion: Thumbnails resolve for locally available assets and for iCloud-only assets without blocking the sheet.
      result: pass
      notes: The packaged-app live check resolved all three selected assets. Source review confirms asynchronous PhotoKit requests enable network access and keep the review sheet responsive. The live sample did not identify an iCloud-only asset, so that path is supported by source review rather than a dedicated live sample.
    - criterion: A failed or nil load is distinguished from loading with visible loading and failure states, and PHImageErrorKey/PHImageResultIsInCloudKey are inspected.
      result: pass
      notes: The tile exposes a spinner while loading, a warning glyph with retry on failure, and the provider inspects both PhotoKit result keys. Limited-access misses now have a distinct actionable tooltip.
    - criterion: The request is cancelled when the tile disappears and the continuation resumes exactly once.
      result: pass
      notes: Source review confirms task cancellation cancels the PhotoKit request, the request-ID box handles cancellation races, and the completion box gates continuation resumption to one terminal callback.
    - criterion: A deterministic injectable-provider test covers loading, loaded, and failed states, and swift build stays warning-free under Swift 6 without concurrency opt-outs.
      result: pass
      notes: The focused loader suite passed all six tests; swift build completed without warnings. The affected source and test files contain no forbidden concurrency opt-outs.
  checks_run:
    - swift build — exit 0; no warnings.
    - swift test --filter PhotosThumbnailLoaderTests — exit 0; 6 tests passed.
    - git diff --check — exit 0.
    - git diff --cached --check — exit 0 before commit.
    - Structural scan for @unchecked Sendable, nonisolated(unsafe), and @preconcurrency in affected files — no matches.
    - "Reviewed the prior packaged Xcode app live check recorded in the issue: three real selections resolved thumbnails after Full Access was granted; did not repeat the live UI check per issue context."
  findings: []
  fixes:
    - Distinguished a missing asset under Limited Photos authorization and added actionable guidance plus a focused regression test.
    - Documented that PhotoKit permission verification requires the packaged Xcode app rather than the SwiftPM launcher.
  verification_commits:
    - aecb9ca0a6488a1a2c45da441f815e2addd0d5d2
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-15T13:35:55.885Z
  session: 01MV9KXATZ7CPX49QM
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - photos-import
created: 2026-10-14T01:22:17.526Z
updated: 2026-10-15T13:35:55.889Z
blockers:
  - id: evt_mv8btp7k_q90as6
    type: human
    reason: The required live PhotosPicker reproduction is unverified because Kromora cannot open the default library while a writer on Daniel’s Mac mini holds its active write lock. Clearing or bypassing that lock could interfere with the other writer.
    action: Safely stop or release the current library writer, then resume KRMA-991 at verification and check the Photos review sheet with real Photos selections.
    created_at: 2026-10-14T16:30:53.408Z
    resolved_at: 2026-10-15T12:39:28.448Z
    resolved_by: web
  - id: evt_mv9jgrxf_ib0ygj
    type: human
    reason: Fix is implemented and unit-tested, but the live check needs an interactive Photos permission prompt and real assets, which a non-interactive run cannot do.
    action: Run swift run, import from Photos with several local and iCloud-only assets, allow the Photos access prompt, and confirm thumbnails resolve. If it still fails, hover the warning glyph for the cause.
    created_at: 2026-10-15T12:52:33.507Z
    resolved_at: 2026-10-15T13:03:27.183Z
    resolved_by: cli
order: zzy
board: product
blocked_reason: Fix is implemented and unit-tested, but the live check needs an interactive Photos permission prompt and real assets, which a non-interactive run cannot do.
blocked_action: Run swift run, import from Photos with several local and iCloud-only assets, allow the Photos access prompt, and confirm thumbnails resolve. If it still fails, hover the warning glyph for the cause.
blocked_from_status: ready
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T16:25:30.452Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - aecb9ca0a6488a1a2c45da441f815e2addd0d5d2
---

## Objective

The "Import from Photos" review sheet shows real thumbnails for every selected asset, or an explicit failure state, instead of leaving placeholder tiles indefinitely.

## Context

Reported after importing from Apple Photos: the review sheet ("4 of 4 selected", Import 4 Selected enabled) shows only the generic photo-glyph placeholder in every tile, and the thumbnails never resolve.

`PhotosReviewThumbnail` in `Sources/KromoraKit/Views/PhotosImportReviewView.swift` loads via `PHImageManager.requestImage` with `isNetworkAccessAllowed = false` and resumes its continuation with whatever image arrives, including `nil`. A `nil` result (iCloud-only original, a nil `localIdentifier`, an asset that fails to fetch, or a PhotoKit error carried in the result-info dictionary that the handler ignores) is indistinguishable from "still loading", so the placeholder stays forever with no retry, spinner, or error. Likely causes to confirm: iCloud-optimized assets, missing/limited Photos authorization at the time the sheet appears, or `localIdentifier` not populated on the selection.

## Acceptance criteria

- [ ] Reproduce with the reporter's scenario (assets imported from Photos, review sheet shown) and record the root cause in the ticket.
- [ ] Thumbnails resolve for locally available assets and for iCloud-only assets (allow network access for thumbnails, or fall back to a degraded image) without blocking the sheet.
- [ ] A failed or `nil` load is distinguished from loading: show a progress state while loading and a visible failure state (with retry or at least a clear glyph) on error; inspect the `PHImageErrorKey`/`PHImageResultIsInCloudKey` info.
- [ ] The request is cancelled when the tile disappears and the continuation is resumed exactly once.
- [ ] A deterministic test covers the load-state model (loading, loaded, failed) through an injectable image provider; `swift build` stays warning-free under Swift 6 mode with no concurrency opt-outs.

## Implementation notes

Extract the thumbnail loading into a small testable loader/state type rather than a static function inside the view. Related: `PhotosImportReviewCoordinator`, `PhotosImportCoordinator`.

### Comment — claude @ 2026-10-14T16:25:26.526Z

Root cause: .photosPicker lacked photoLibrary: .shared(), so PhotosPickerItem.itemIdentifier was nil; the thumbnail loader returned nil for a nil identifier, indistinguishable from loading. Also ignored PHImageErrorKey and disabled network access. Fix: picker uses .shared(); PhotosThumbnailLoader (injectable provider, loading/loaded/failed), PhotoKit provider with network access, cancellation, single-shot resume; tile shows spinner / warning glyph (double-click retries). Not reproduced against a live Photos library (non-interactive run); tests: PhotosThumbnailLoaderTests.

### Comment — codex @ 2026-10-14T16:30:47.676Z

Independent verification: swift build passed with no warnings; swift test --filter PhotosThumbnailLoaderTests passed (4 tests); git diff --check passed. Review found and fixed a cancellation/request-ID race, guarded terminal PhotoKit callback handling so the continuation is single-shot, inspected PHImageResultIsInCloudKey, and added a tested thumbnail state model. Verification fix commit: d474b766. The implementation's root-cause note says PhotosPicker lacked photoLibrary: .shared(), leaving PhotosPickerItem.itemIdentifier nil; the corrected picker path is confirmed in code. I attempted a live review-sheet check with swift run, but Kromora refused startup because the default package is actively being written by Daniel’s Mac mini (pid 41496). I closed the app without touching the lock, so the real PhotosPicker reproduction remains unverified.

### Comment — claude @ 2026-10-15T12:52:33.299Z

Likely root cause of the live failure: PhotosPicker (private access) does not authorize PhotoKit, so PHAsset.fetchAssets returned empty and the tile showed assetUnavailable. Fix c7600aae: PhotoKitThumbnailProvider checks/requests .readWrite authorization before fetching; denial throws new PhotosThumbnailFailure.accessDenied, whose tooltip points to System Settings > Privacy & Security > Photos. Added a test; swift build is warning-free and PhotosThumbnailLoaderTests pass (5). Not verified live: this run is non-interactive and cannot answer the Photos permission prompt.

### Comment — claude @ 2026-10-15T12:54:39.387Z

Live check by Daniel (swift run, build including c7600aae): the Import from Photos review still shows the warning glyph on all 3 selected tiles; none resolve. The c7600aae authorization fix did not clear it under swift run. Open questions: (1) which PhotosThumbnailFailure the glyph tooltip reports (accessDenied vs assetUnavailable vs request error); (2) swift run is an unbundled process with no Info.plist (NSPhotoLibraryUsageDescription lives only in App/Info.plist), so Photos authorization may be denied or attributed to Terminal and never prompt, which would make this a swift-run-only failure; (3) whether the same happens in the packaged, sandboxed Xcode app. Next: read the tooltip, then retest in the Xcode Kromora scheme. If it only fails under swift run, document that limit or add a clearer message, and record the result here.

### Comment — claude @ 2026-10-15T13:00:01.759Z

Daniel: continuing past the review sheet does import the photos, and the tile tooltip shows only the names 'Photo 1', 'Photo 2', ... This points at one cause. Import reads the picked data through the picker item, which needs no PhotoKit authorization. Both the thumbnail (PHAsset fetch/request) and the real filename (PhotosImportCoordinator.originalFilename via PHAssetResource, falling back to 'Photo N') need PhotoKit access. Both fail together, which fits the swift run (no Info.plist, no Photos prompt) theory. The tooltip shows the fallback name, not a failure reason. Retest in the packaged Xcode app: if thumbnails and real filenames appear there, close as a swift-run limitation and document it. The duplicate fallback names are tracked in a separate ticket.

### Comment — claude @ 2026-10-15T13:03:23.264Z

Live check by Daniel in the packaged Xcode app (Kromora scheme, sandboxed, with Info.plist): after choosing 'Allow Full Access' at the Photos permission prompt, the Import from Photos review sheet resolves thumbnails for all 3 selected assets (3 of 3 selected, Import 3 Selected enabled). Conclusion: the c7600aae authorization fix works in the real app; the earlier failure was swift run, an unbundled process that cannot get Photos authorization. Verifier: do not repeat the live check; it is done. Remaining to verify from code: (1) the denied state shows the accessDenied tooltip pointing to System Settings > Privacy & Security > Photos; (2) swift run limitation is documented (docs/TESTING.md or README) so a failed thumbnail there is not mistaken for a bug; (3) behavior under Limited access (status .limited) is considered: assets picked through PhotosPicker may not be in the limited set, so fetch can still return empty and should show a clear message. Duplicate fallback names are KRMA-1030.

### Comment — claude @ 2026-10-15T13:05:01.392Z

Daniel also confirmed real filenames on import in the packaged app, which matches the missing-PhotoKit-access diagnosis for swift run.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

### Verification blocker — live Photos review still shows no thumbnails

- On 2026-10-15, I launched the current SwiftPM build and selected four real assets in the Photos picker. The picker showed its private-access notice. The review sheet opened and reported `1 of 4 already in library` with `Import 3 Selected` enabled.
- All four thumbnail tiles displayed the warning glyph; none resolved to an image. This reproduces the reported failure after the `.photosPicker(photoLibrary: .shared())` change. The explicit failure UI works, but resolving selected assets does not.
- The precise PhotoKit failure is not exposed by the review UI. `PhotoKitThumbnailProvider` can fail at the `PHAsset.fetchAssets(withLocalIdentifiers:)` lookup or in the image request, and both currently collapse to the same glyph. The earlier note that the picker library instance was the root cause is therefore incomplete; determine and record whether authorization/private access or another PhotoKit lookup/request error causes the live failure.
- Required change: make thumbnails resolve for assets selected through the actual Photos picker privacy/access flow, including locally available and iCloud-only assets, or surface a genuinely actionable failure when PhotoKit cannot access one. Preserve cancellation and single-resume behavior. Add deterministic coverage for any changed provider/state behavior.
- Verify by building and running the app, selecting several real Photos assets under the normal private-access picker flow, and confirming their thumbnails resolve in the review sheet. Also exercise an iCloud-only asset, a failed load, and tile cancellation; the existing focused loader tests and warning-free Swift 6 build must pass.

- 2026-10-15T12:46:43.586Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [ ] Reproduce the reporter scenario with real Photos assets and record the root cause in the ticket. (fail) — Reproduced with four real Photos selections. The review showed all four warning glyphs; exact PhotoKit failure (asset lookup versus request/access error) is not surfaced, and the issue body now records this unresolved diagnosis.
- [ ] Thumbnails resolve for locally available assets and for iCloud-only assets without blocking the sheet. (fail) — None of four selected assets resolved to an image in the live review sheet. The sheet remained usable and identified one item already in the library.
- [x] A failed or nil load is distinguished from loading with visible loading and failure states, and PHImageErrorKey/PHImageResultIsInCloudKey are inspected. (pass) — Source review confirms loading uses ProgressView, failures show a warning glyph, and the PhotoKit provider checks both result-info keys. The live run exercised the visible failure state.
- [x] The request is cancelled when the tile disappears and the continuation resumes exactly once. (pass) — Source review confirms task cancellation calls cancelImageRequest, PHImageCancelledKey is handled, and CompletionBox permits one terminal resume. Apple documentation confirms PhotoKit invokes the result handler with PHImageCancelledKey after cancellation.
- [x] A deterministic injectable-provider test covers loading, loaded, and failed states, and swift build stays warning-free under Swift 6 without concurrency opt-outs. (pass) — swift test --filter PhotosThumbnailLoaderTests passed all 4 tests; swift build completed without warnings. No forbidden concurrency opt-outs are present in the affected files.
Checks run:
- swift build — exit 0; no warnings or diagnostics.
- swift test --filter PhotosThumbnailLoaderTests — exit 0; 4 tests passed.
- git diff --check — exit 0.
- Structural review — no @unchecked Sendable, nonisolated(unsafe), or @preconcurrency in affected files.
- Live Photos review — selected four real assets; all four tiles displayed the warning glyph and no thumbnail. One was tagged already in library; no import was performed.
- Reviewed Apple PhotoKit documentation for cancellation callbacks, iCloud availability, and fetch authorization requirements.
Findings:
- Blocking: the live PhotosPicker review still fails to resolve thumbnails for all four real selected assets after the picker uses photoLibrary: .shared(). The review presents the failure glyph, but successful local and iCloud thumbnail resolution remains unmet. The precise PhotoKit failure is not exposed; the issue body records the required diagnosis and verification steps.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV9J004NIN0X5WND
Summary: Live Photos picker reproduction still renders warning glyphs for all four selected assets; fix PhotoKit access or lookup and pass real-selection verification.

- 2026-10-15T13:35:55.885Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Reproduce the reporter scenario with real Photos assets and record the root cause in the ticket. (pass) — The issue comments record the packaged Xcode app live check: after granting Full Access, all three selected assets resolved thumbnails and filenames. The root cause was missing PhotoKit read authorization; PhotosPicker's private selection access alone did not authorize the PhotoKit fetch. The provider now requests read/write authorization before lookup.
- [x] Thumbnails resolve for locally available assets and for iCloud-only assets without blocking the sheet. (pass) — The packaged-app live check resolved all three selected assets. Source review confirms asynchronous PhotoKit requests enable network access and keep the review sheet responsive. The live sample did not identify an iCloud-only asset, so that path is supported by source review rather than a dedicated live sample.
- [x] A failed or nil load is distinguished from loading with visible loading and failure states, and PHImageErrorKey/PHImageResultIsInCloudKey are inspected. (pass) — The tile exposes a spinner while loading, a warning glyph with retry on failure, and the provider inspects both PhotoKit result keys. Limited-access misses now have a distinct actionable tooltip.
- [x] The request is cancelled when the tile disappears and the continuation resumes exactly once. (pass) — Source review confirms task cancellation cancels the PhotoKit request, the request-ID box handles cancellation races, and the completion box gates continuation resumption to one terminal callback.
- [x] A deterministic injectable-provider test covers loading, loaded, and failed states, and swift build stays warning-free under Swift 6 without concurrency opt-outs. (pass) — The focused loader suite passed all six tests; swift build completed without warnings. The affected source and test files contain no forbidden concurrency opt-outs.
Checks run:
- swift build — exit 0; no warnings.
- swift test --filter PhotosThumbnailLoaderTests — exit 0; 6 tests passed.
- git diff --check — exit 0.
- git diff --cached --check — exit 0 before commit.
- Structural scan for @unchecked Sendable, nonisolated(unsafe), and @preconcurrency in affected files — no matches.
- Reviewed the prior packaged Xcode app live check recorded in the issue: three real selections resolved thumbnails after Full Access was granted; did not repeat the live UI check per issue context.
Findings:
- None
Fixes:
- Distinguished a missing asset under Limited Photos authorization and added actionable guidance plus a focused regression test.
- Documented that PhotoKit permission verification requires the packaged Xcode app rather than the SwiftPM launcher.
Verification commits:
- aecb9ca0a6488a1a2c45da441f815e2addd0d5d2
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV9KXATZ7CPX49QM
Summary: PASS: Photos thumbnails resolve in the packaged app after PhotoKit authorization; Limited access now has actionable guidance. Build and 6 focused tests pass.
