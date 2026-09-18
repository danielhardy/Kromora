---
id: KRMA-449
title: Accept Photos file-promise and bitmap drops into the library
type: feature
status: ready
priority: high
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
updated: 2026-09-18T22:40:12.272Z
order: a0
board: product
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
