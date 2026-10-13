---
id: KRMA-942
title: "Export: encode straight to a staging file instead of NSMutableData then Data.write"
type: task
status: backlog
priority: high
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - performance
  - export
  - memory
parent: KRMA-922
created: 2026-10-13T14:47:51.998Z
updated: 2026-10-13T14:48:19.732Z
blockers: []
order: qiy3sf54
board: product
---

## Objective

Cut export peak memory: a 60 MP 16-bit TIFF currently peaks near 850 MB and 100 MP sources exceed
1.4 GB because the encoded bytes are held in memory and then written (again) via a second temp file.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding S3.

- `Sources/KromoraKit/Models/RenderEngine.swift` ~L1201 `encode(_:format:representationFormat:
  colorSpace:quality:metadata:) throws -> Data`: renders a full `CGImage` with
  `context.createCGImage`, then encodes into an `NSMutableData` via
  `CGImageDestinationCreateWithData`, and returns `Data`.
- `Sources/KromoraKit/ViewModels/ExportCoordinator.swift` ~L612 `write(_:to:scopedFileURL:)`: writes
  that `Data` with `data.write(to: temp, options: .atomic)` (a second temp file) then moves it, or for
  `scopedFileURL` (NSSavePanel selection) uses `writeSelectedFile` (O_EXCL create + FileHandle write).
- Callers of `encode`/the `Data`-returning export API: `grep -rn "func export\|\.encode(" Sources/
  KromoraKit/Models/RenderEngine.swift` and the export coordinators.
- Image I/O offers `CGImageDestinationCreateWithURL`, which streams to disk.

## Acceptance criteria

- [ ] A new engine entry point encodes to a caller-supplied staging `URL` using
      `CGImageDestinationCreateWithURL` (no `NSMutableData`, no intermediate `Data`). `Data`-returning
      callers that still need bytes (share/pasteboard if any) keep the old API or are migrated; list
      them in the review comment.
- [ ] `ExportCoordinator` stages the file next to the destination (as today's `.partial` temp name:
      `".\(name).\(uuid).partial"`), then does the same final no-replace move with the same
      cancellation checks. The `scopedFileURL` path (NSSavePanel grants only the selected file) must
      keep working: for that path encode to a temp file in the app's temp directory, then copy bytes
      into the O_EXCL-created selected file with a streaming `FileHandle` copy (chunked, not
      `Data(contentsOf:)`).
- [ ] Cancellation and failure remove the staging file; success leaves no `.partial` file (tests).
- [ ] Output bytes are unchanged: existing export tests (`grep -rln "exportData\|ExportCoordinator"
      Tests`) pass unchanged, and a new test compares pixel content and metadata of JPEG/HEIF/TIFF
      exports before/after through the real engine (`scripts/ci-tests.sh serial`).
- [ ] A test or documented measurement shows peak resident size is lower: use `proc_pid_rusage` /
      `task_info` `phys_footprint` around a synthetic 8k×6k TIFF export and record before/after in the
      review comment (not a CI assertion). Do not run the display-bound capture scripts.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).
- [ ] `scripts/ci-tests.sh serial` exits 0.

## Implementation notes

Keep `context.createCGImage` for now (a full CGImage is still needed); streaming tiles is out of scope.
