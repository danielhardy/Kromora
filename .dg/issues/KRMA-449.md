---
id: KRMA-449
title: Accept Photos file-promise and bitmap drops into the library
type: feature
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Dragging photos from Apple Photos onto the edit preview imports promised originals into the library with correct extensions
      result: pass
      notes: ImageDrop.receive redeems NSFilePromiseReceiver files into a temp dir and routes them through AppViewModel.openImages -> portableLibrary.importURLs, preserving the promised filename/extension. Automated coverage stops at classification/round-trip; direct receivePromisedFiles exercise is a documented manual check (see notes).
    - criterion: A Photos drag that also carries a library file-url prefers the promise and does not open the derivative URL
      result: pass
      notes: ImageDrop.payload(from:) checks NSFilePromiseReceiver first and returns early; covered by testPromisesWinOverURLAndBitmapPayloads.
    - criterion: Finder file and folder drops continue to work unchanged
      result: pass
      notes: FileDropActionPolicy path unchanged; testFileURLsRemainURLPayloads and testWebURLsAreNotAcceptedAsFileDrops pass.
    - criterion: Dropped/pasted bitmap pasteboard data (tiff/png) imports through a data-backed path with a stable display name
      result: pass
      notes: openImage(data:name:) reuses the Photos-picker data-import path; fixed a wrong test expectation (stripped extension) in testBitmapDropUsesTheExistingDataImportPath.
    - criterion: Promise receivers are redeemed on the main queue; no private OperationQueue
      result: pass
      notes: "ImageDrop.receive passes operationQueue: .main to receivePromisedFiles."
    - criterion: Multi-item drops import successfully redeemed items and surface per-item failures without aborting the batch
      result: pass
      notes: ImageDrop.receive collects per-file failures into PromiseReceiveResult.failures and still imports result.urls; AppViewModel.handleDrop surfaces failure count in statusMessage.
    - criterion: Temp drop directories are cleaned up after import adoption and do not accumulate
      result: pass
      notes: purgeDropDirectories() runs before allocating a new directory and again after import via defer; testDropDirectoriesArePurgedAfterAdoption passes.
    - criterion: Automated tests cover pasteboard classification priority, URL/folder policy, and promise-receive/main-queue contract where injectable
      result: pass
      notes: "8 ImageDropTests cover classification priority, URL/folder passthrough, bitmap import, and directory purge. testPromiseReceiveKeepsPromisedFilenameAndReportsSuccess was removed: it called receivePromisedFiles on an NSFilePromiseReceiver round-tripped through a plain (non-drag) NSPasteboard, which deterministically aborts the whole xctest process with SIGABRT (NSFilePromiseReceiver.m:300, 'freed pointer was not the last allocation') rather than failing cleanly -- a process crash that would break the entire CI run, not just this test. This is exactly the 'XCTest cannot synthesize NSFilePromiseReceiver' case the issue's own acceptance criteria anticipated as a documented manual check."
  checks_run:
    - swift build (initially failed on 3 pre-existing, unrelated compile errors; fixed, now clean)
    - swift test --filter ImageDropTests (8/8 pass after fixing 2 broken test assertions and removing 1 process-crashing test)
    - swift test --filter ModelDependencyTests (passes after relocating ImageDrop.swift out of Models/)
    - swift test --filter NeutralOriginSliderTests (14/14 pass after fixing a missing import that blocked the whole file)
    - scripts/ci-tests.sh fast (1065/1066 pass; 1 pre-existing, unrelated failure filed as KRMA-457)
    - git diff --check
  findings:
    - "[correctness] ResolutionPlanner.plan called Self.roi, which does not exist on ResolutionPlanner (roi is a static method on the sibling ResolutionPlan struct) (Sources/KromoraKit/Models/ResolutionPlanner.swift) Scenario: swift build fails entirely; pre-existing from KRMA-443 (fb2c2d4), unrelated to KRMA-449 Outcome: fixed"
    - "[correctness] BundledLookLibrary.categories passed the @MainActor-isolated LUTLibrary.starterCategoryPrecedes as a plain comparator, a Swift 6 actor-isolation compile error (Sources/KromoraKit/Models/LUTLibrary.swift) Scenario: swift build fails entirely; pre-existing, unrelated to KRMA-449 Outcome: fixed"
    - "[correctness] EffectsInspectorView's NeutralOriginSlider call listed step before neutral, no longer matching the initializer's parameter order (Sources/KromoraKit/Views/EffectsInspectorView.swift) Scenario: swift build fails entirely; pre-existing, unrelated to KRMA-449 Outcome: fixed"
    - "[test-coverage] NeutralOriginSliderTests.swift was missing import SwiftUI, blocking the whole file (and everything compiled alongside it) from building (Tests/KromoraKitTests/NeutralOriginSliderTests.swift) Scenario: swift test fails to compile the KromoraKitTests target Outcome: fixed"
    - "[correctness] testPromiseReceiveKeepsPromisedFilenameAndReportsSuccess called receivePromisedFiles on an NSFilePromiseReceiver obtained from a plain pasteboard (no real drag session), which deterministically SIGABRTs the whole xctest process (Tests/KromoraKitTests/ImageDropTests.swift) Scenario: Any swift test run that includes ImageDropTests aborts the entire process rather than reporting one failing test, which would break CI-wide test reporting Outcome: fixed"
    - "[test-coverage] testAcceptedTypesIncludeFilesImagesAndPromiseIdentifiers hard-failed via XCTFail because UTType(_:) returns nil for com.apple.NSFilePromiseItemMetaData, a real pasteboard identifier AppKit reports that has no UTType (Tests/KromoraKitTests/ImageDropTests.swift) Scenario: Test fails on every run despite ImageDrop.acceptedTypes behaving correctly (it already tolerates unmappable identifiers via compactMap) Outcome: fixed"
    - '[correctness] testBitmapDropUsesTheExistingDataImportPath asserted a stripped-extension display name ("Dropped Image") instead of the correct extension-preserving one ("Dropped Image.png") (Tests/KromoraKitTests/ImageDropTests.swift) Scenario: Test fails even though the production code correctly preserves the extension per acceptance criteria (needed for RAW/type detection) Outcome: fixed'
    - "[maintainability] ImageDrop.swift was placed under Sources/KromoraKit/Models/ but imports AppKit, violating the ModelDependencyTests architecture guardrail that only allows UI imports in Models/ for explicitly named presentation owners (Sources/KromoraKit/Presentation/ImageDrop.swift) Scenario: swift test fails ModelDependencyTests.testModelsDirectoryAllowsUIImportsOnlyForNamedPresentationOwners Outcome: fixed"
    - "[correctness] EffectsInspectorTests.testBindingsRoundTripAndIndividualResetsPreserveOtherEffects fails (41.0 vs 40.0) in vignette midpoint reset logic, unrelated to KRMA-449's own diff and pre-existing (Sources/KromoraKit/ViewModels/AppViewModel.swift) Scenario: Resetting the vignette after setting midpoint to a fractional value leaves it at 41 instead of the expected neutral value; needs its own root-cause investigation Outcome: skipped"
  fixes:
    - Fixed ResolutionPlanner.plan to call ResolutionPlan.roi instead of the nonexistent Self.roi
    - Marked LUTLibrary.starterCategoryPrecedes nonisolated so it can be used as a plain comparator
    - Reordered the NeutralOriginSlider call site in EffectsInspectorView.swift to match its initializer
    - Added the missing import SwiftUI to NeutralOriginSliderTests.swift
    - Removed the process-crashing testPromiseReceiveKeepsPromisedFilenameAndReportsSuccess and documented why (real Photos-drag manual check per acceptance criteria)
    - Made testAcceptedTypesIncludeFilesImagesAndPromiseIdentifiers tolerate promise identifiers with no UTType, mirroring ImageDrop.acceptedTypes' own compactMap
    - Fixed testBitmapDropUsesTheExistingDataImportPath's expected display name to keep the extension
    - Moved ImageDrop.swift from Sources/KromoraKit/Models/ to Sources/KromoraKit/Presentation/ to satisfy the AppKit-import architecture boundary
    - Filed KRMA-457 (parent KRMA-449, label verification) for the unrelated pre-existing vignette midpoint reset bug uncovered once EffectsInspectorView.swift compiled
  verification_commits:
    - b26624f4a9ce115dd8750452d2173f45bc87114a
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-18T23:29:25.486Z
  session: 01MU7KWP3FJTT2MFG5
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - import
  - photos
  - ux
  - library
created: 2026-09-18T22:38:53.577Z
updated: 2026-09-18T23:29:25.489Z
order: a0
board: product
commits:
  - b26624f4a9ce115dd8750452d2173f45bc87114a
---

## Objective

Make drag-and-drop onto the edit preview (and any other intentional drop targets) accept Apple Photos file promises and pasted/dropped bitmap data, then import the resulting originals into the portable library through the existing import path — not through LUTzy's session-folder model.

## Context

### Current Kromora behavior

- `Sources/KromoraKit/Views/PreviewView.swift` only advertises `.fileURL` via `.onDrop(of: [.fileURL], …)` and `handleDrop` loads `public.file-url` from an `NSItemProvider`, then calls `viewModel.handleDroppedURL`.
- `LibraryMediaWorkflowCoordinator.handleDroppedURL` / `FileDropActionPolicy` only classify Finder-style file or folder URLs.
- Photos import already works through `PhotosPicker` → `PhotosImportCoordinator` (full-fidelity streaming import into the library). That path must be reused or extended; do not invent a parallel import pipeline.

### Why Finder-only drop fails for Photos

Upstream LUTzy measured (PRs #37 / #41, commits `735636c`, `406f7c8`, `93d12bc` on `upstream/main` of `tsvb/lutzy`):

1. A Photos drag writes **`NSFilePromiseReceiver`s**, not usable file URLs.
2. Photos often *also* writes a `public.file-url`, but it points at a small sandbox-inaccessible derivative inside the Photos library. Preferring that URL silently imports the wrong (or unreadable) asset.
3. **Promises must win over URLs.** Finder writes no promise, so its URLs still work.
4. Bitmap pasteboard types (`public.tiff`, `public.png`) come from browsers / image editors and should open through the data-backed import path Photos-picker already uses.
5. The promise receive completion must run on the **main queue**. Handing a private `OperationQueue` crashed under Swift 6 isolation (`dispatch_assert_queue`).

### Upstream reference (idea source only — do not merge)

- `Sources/LUTzyKit/Models/ImageDrop.swift` — pasteboard classification + promise receive
- `Sources/LUTzyKit/Views/ImageDropDelegate.swift` — reads `NSPasteboard(name: .drag)` because promises are not redeemable through `NSItemProvider`
- `Tests/LUTzyKitTests/ImageDropTests.swift`

View upstream with: `git show upstream/main:Sources/LUTzyKit/Models/ImageDrop.swift`

### Product constraints

- macOS 14 deployment floor; zero third-party dependencies; Swift 6 with no Sendable opt-outs.
- Dropped assets must become durable library package originals (managed import), not ephemeral session-only URLs.
- Preserve App Sandbox: promised files land in an app-writable temp directory, then are imported like other inbound originals.
- Multi-file Photos drops should import all redeemable items; partial failures must not discard successful ones (mirror Photos import failure isolation).

## Acceptance criteria

- [ ] Dragging one or more photos from Apple Photos onto the edit preview (or the agreed drop target) imports the **promised originals** into the library with correct extensions so RAW detection (`.dng` / `.arw` / etc.) still works.
- [ ] When a Photos drag also carries a library `file-url`, the implementation prefers the file promise and does **not** open the derivative library URL.
- [ ] Finder file and folder drops continue to work unchanged through the existing `FileDropActionPolicy` / open-folder path.
- [ ] Dropped or pasted bitmap pasteboard data (`tiff`/`png` at minimum) imports through a data-backed path equivalent to Photos-picker byte import, with a stable display name.
- [ ] Promise receivers are redeemed on the **main queue**; no private `OperationQueue` is used for the receive callback.
- [ ] Multi-item drops import successfully redeemed items and surface per-item failures without aborting the whole batch.
- [ ] Temp drop directories are cleaned up after import adoption (or on the next drop), and do not accumulate unbounded under Application Support / tmp.
- [ ] Automated tests cover pasteboard classification priority (promises > URLs > bitmap), URL/folder policy unchanged, and promise-receive / main-queue contract where injectable. Manual note: a real Photos drag may remain a documented manual check if XCTest cannot synthesize `NSFilePromiseReceiver`.

## Out of scope

- Replacing `PhotosPicker` import UI.
- Changing library package identity or edit-store schema.
- Adopting LUTzy's in-session multi-file filmstrip without library import.
- Auto-update / DMG packaging (separate tickets).

## Implementation notes

1. Introduce a Kromora-owned drop classifier (e.g. `ImageDrop` / `LibraryDropPayload`) under `Sources/KromoraKit/` — AppKit pasteboard types are fine; keep `NSFilePromiseReceiver` main-actor-bound and only pass `URL`/`Data` across isolation boundaries.
2. Prefer an `NSViewRepresentable` / AppKit drop delegate that reads `NSPasteboard(name: .drag)` for promise redemption; SwiftUI `onDrop` + `NSItemProvider` cannot redeem promises.
3. After URLs/`Data` are materialised, route through the existing library import entry points (`PhotosImportCoordinator` patterns, `SourceImportPlan`, or the coordinator that already accepts URL/data originals) — wire via `AppViewModel` / `LibraryMediaWorkflowCoordinator`, do not open files as a temporary filmstrip-only set.
4. Extend or replace `PreviewView.handleDrop`; consider Library grid as a second drop target only if product-consistent and cheap — preview is the minimum.
5. Tests: unit-test classification with constructed pasteboards; keep CI deterministic (no live Photos.app required).

## Verification

- Focused unit tests for the new drop classifier + import routing.
- `swift build`
- `git diff --check`
- Manual (document in completion comment): drag from Photos.app onto preview on a sandboxed `.app` build.

### Comment — cursor @ 2026-09-18T22:40:12.271Z

Provenance: valuable upstream LUTzy idea from Photos drop PRs #37/#41 (commits 735636c, 406f7c8, 93d12bc on tsvb/lutzy). Re-implement against Kromora library import — do not merge LUTzy session-folder drop behavior. Read `git show upstream/main:Sources/LUTzyKit/Models/ImageDrop.swift` for the classification contract (promises > URLs > bitmap; main-queue receive).

### Comment — codex @ 2026-09-18T23:17:32.825Z

Implemented in 656129a. Added main-actor AppKit pasteboard classification (promises > URLs > bitmap), Photos promise redemption into cleaned per-drop temp directories with .main callbacks, durable multi-file library routing, bitmap byte import, preserved Finder URL/folder policy, and focused ImageDrop tests. Verification: ImageDrop.swift typecheck and git diff --check pass; swift build/swift test --filter ImageDropTests are currently blocked by pre-existing unrelated Swift 6/macOS 27 SDK errors in ResolutionPlanner.swift, BundledLookLibrary.swift, and EffectsInspectorView.swift. Manual follow-up for verification: drag real RAW/JPEG items from Photos.app onto a sandboxed app preview and confirm promised original extensions/library package originals.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-18T23:29:25.487Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Dragging photos from Apple Photos onto the edit preview imports promised originals into the library with correct extensions (pass) — ImageDrop.receive redeems NSFilePromiseReceiver files into a temp dir and routes them through AppViewModel.openImages -> portableLibrary.importURLs, preserving the promised filename/extension. Automated coverage stops at classification/round-trip; direct receivePromisedFiles exercise is a documented manual check (see notes).
- [x] A Photos drag that also carries a library file-url prefers the promise and does not open the derivative URL (pass) — ImageDrop.payload(from:) checks NSFilePromiseReceiver first and returns early; covered by testPromisesWinOverURLAndBitmapPayloads.
- [x] Finder file and folder drops continue to work unchanged (pass) — FileDropActionPolicy path unchanged; testFileURLsRemainURLPayloads and testWebURLsAreNotAcceptedAsFileDrops pass.
- [x] Dropped/pasted bitmap pasteboard data (tiff/png) imports through a data-backed path with a stable display name (pass) — openImage(data:name:) reuses the Photos-picker data-import path; fixed a wrong test expectation (stripped extension) in testBitmapDropUsesTheExistingDataImportPath.
- [x] Promise receivers are redeemed on the main queue; no private OperationQueue (pass) — ImageDrop.receive passes operationQueue: .main to receivePromisedFiles.
- [x] Multi-item drops import successfully redeemed items and surface per-item failures without aborting the batch (pass) — ImageDrop.receive collects per-file failures into PromiseReceiveResult.failures and still imports result.urls; AppViewModel.handleDrop surfaces failure count in statusMessage.
- [x] Temp drop directories are cleaned up after import adoption and do not accumulate (pass) — purgeDropDirectories() runs before allocating a new directory and again after import via defer; testDropDirectoriesArePurgedAfterAdoption passes.
- [x] Automated tests cover pasteboard classification priority, URL/folder policy, and promise-receive/main-queue contract where injectable (pass) — 8 ImageDropTests cover classification priority, URL/folder passthrough, bitmap import, and directory purge. testPromiseReceiveKeepsPromisedFilenameAndReportsSuccess was removed: it called receivePromisedFiles on an NSFilePromiseReceiver round-tripped through a plain (non-drag) NSPasteboard, which deterministically aborts the whole xctest process with SIGABRT (NSFilePromiseReceiver.m:300, 'freed pointer was not the last allocation') rather than failing cleanly -- a process crash that would break the entire CI run, not just this test. This is exactly the 'XCTest cannot synthesize NSFilePromiseReceiver' case the issue's own acceptance criteria anticipated as a documented manual check.
Checks run:
- swift build (initially failed on 3 pre-existing, unrelated compile errors; fixed, now clean)
- swift test --filter ImageDropTests (8/8 pass after fixing 2 broken test assertions and removing 1 process-crashing test)
- swift test --filter ModelDependencyTests (passes after relocating ImageDrop.swift out of Models/)
- swift test --filter NeutralOriginSliderTests (14/14 pass after fixing a missing import that blocked the whole file)
- scripts/ci-tests.sh fast (1065/1066 pass; 1 pre-existing, unrelated failure filed as KRMA-457)
- git diff --check
Findings:
- [correctness] ResolutionPlanner.plan called Self.roi, which does not exist on ResolutionPlanner (roi is a static method on the sibling ResolutionPlan struct) (Sources/KromoraKit/Models/ResolutionPlanner.swift) Scenario: swift build fails entirely; pre-existing from KRMA-443 (fb2c2d4), unrelated to KRMA-449 Outcome: fixed
- [correctness] BundledLookLibrary.categories passed the @MainActor-isolated LUTLibrary.starterCategoryPrecedes as a plain comparator, a Swift 6 actor-isolation compile error (Sources/KromoraKit/Models/LUTLibrary.swift) Scenario: swift build fails entirely; pre-existing, unrelated to KRMA-449 Outcome: fixed
- [correctness] EffectsInspectorView's NeutralOriginSlider call listed step before neutral, no longer matching the initializer's parameter order (Sources/KromoraKit/Views/EffectsInspectorView.swift) Scenario: swift build fails entirely; pre-existing, unrelated to KRMA-449 Outcome: fixed
- [test-coverage] NeutralOriginSliderTests.swift was missing import SwiftUI, blocking the whole file (and everything compiled alongside it) from building (Tests/KromoraKitTests/NeutralOriginSliderTests.swift) Scenario: swift test fails to compile the KromoraKitTests target Outcome: fixed
- [correctness] testPromiseReceiveKeepsPromisedFilenameAndReportsSuccess called receivePromisedFiles on an NSFilePromiseReceiver obtained from a plain pasteboard (no real drag session), which deterministically SIGABRTs the whole xctest process (Tests/KromoraKitTests/ImageDropTests.swift) Scenario: Any swift test run that includes ImageDropTests aborts the entire process rather than reporting one failing test, which would break CI-wide test reporting Outcome: fixed
- [test-coverage] testAcceptedTypesIncludeFilesImagesAndPromiseIdentifiers hard-failed via XCTFail because UTType(_:) returns nil for com.apple.NSFilePromiseItemMetaData, a real pasteboard identifier AppKit reports that has no UTType (Tests/KromoraKitTests/ImageDropTests.swift) Scenario: Test fails on every run despite ImageDrop.acceptedTypes behaving correctly (it already tolerates unmappable identifiers via compactMap) Outcome: fixed
- [correctness] testBitmapDropUsesTheExistingDataImportPath asserted a stripped-extension display name ("Dropped Image") instead of the correct extension-preserving one ("Dropped Image.png") (Tests/KromoraKitTests/ImageDropTests.swift) Scenario: Test fails even though the production code correctly preserves the extension per acceptance criteria (needed for RAW/type detection) Outcome: fixed
- [maintainability] ImageDrop.swift was placed under Sources/KromoraKit/Models/ but imports AppKit, violating the ModelDependencyTests architecture guardrail that only allows UI imports in Models/ for explicitly named presentation owners (Sources/KromoraKit/Presentation/ImageDrop.swift) Scenario: swift test fails ModelDependencyTests.testModelsDirectoryAllowsUIImportsOnlyForNamedPresentationOwners Outcome: fixed
- [correctness] EffectsInspectorTests.testBindingsRoundTripAndIndividualResetsPreserveOtherEffects fails (41.0 vs 40.0) in vignette midpoint reset logic, unrelated to KRMA-449's own diff and pre-existing (Sources/KromoraKit/ViewModels/AppViewModel.swift) Scenario: Resetting the vignette after setting midpoint to a fractional value leaves it at 41 instead of the expected neutral value; needs its own root-cause investigation Outcome: skipped
Fixes:
- Fixed ResolutionPlanner.plan to call ResolutionPlan.roi instead of the nonexistent Self.roi
- Marked LUTLibrary.starterCategoryPrecedes nonisolated so it can be used as a plain comparator
- Reordered the NeutralOriginSlider call site in EffectsInspectorView.swift to match its initializer
- Added the missing import SwiftUI to NeutralOriginSliderTests.swift
- Removed the process-crashing testPromiseReceiveKeepsPromisedFilenameAndReportsSuccess and documented why (real Photos-drag manual check per acceptance criteria)
- Made testAcceptedTypesIncludeFilesImagesAndPromiseIdentifiers tolerate promise identifiers with no UTType, mirroring ImageDrop.acceptedTypes' own compactMap
- Fixed testBitmapDropUsesTheExistingDataImportPath's expected display name to keep the extension
- Moved ImageDrop.swift from Sources/KromoraKit/Models/ to Sources/KromoraKit/Presentation/ to satisfy the AppKit-import architecture boundary
- Filed KRMA-457 (parent KRMA-449, label verification) for the unrelated pre-existing vignette midpoint reset bug uncovered once EffectsInspectorView.swift compiled
Verification commits:
- b26624f4a9ce115dd8750452d2173f45bc87114a
Actor: claude
Resolved model: sonnet
Pickup session: 01MU7KWP3FJTT2MFG5
Summary: Verified KRMA-449's Photos promise/bitmap drop feature: functionally correct after fixing 3 broken tests in the new suite and moving ImageDrop.swift out of Models/ to satisfy the architecture boundary test. Also fixed 4 unrelated pre-existing build breaks (ResolutionPlanner, BundledLookLibrary/LUTLibrary, EffectsInspectorView, NeutralOriginSliderTests) that were blocking swift build/test entirely, and filed KRMA-457 for one unrelated pre-existing effects-reset bug uncovered along the way.
