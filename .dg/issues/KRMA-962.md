---
id: KRMA-962
title: "Small code cleanups: try! in package paths, dead #if os(macOS), test-only seam in PreviewSurface"
type: task
status: backlog
priority: low
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - nice-to-have
  - cleanup
parent: KRMA-922
created: 2026-10-13T14:48:12.335Z
updated: 2026-10-13T14:48:23.784Z
blockers: []
order: zzy
board: product
---

## Objective

Remove three small non-idiomatic bits flagged in review.

## Context

Review `.context/2026-10-13-release-readiness-review.md` "Nice to have: Code cleanups".

1. `Sources/KromoraKit/Models/PortableLibraryPackage.swift:641-655`: four `try! packageURL(for: …)`
   helpers (membership shard URL, asset record URL, asset directory, quarantine directory). They are
   safe today because inputs are validated, but `try!` crashes the app on a regression. Make the
   helpers `throws` and propagate (callers already `throws`) or return a non-optional URL built with
   `appending(path:)` if `packageURL(for:)` cannot fail for those inputs.
2. Dead `#if os(macOS)` branches (the product is macOS-only): `Sources/KromoraKit/Models/
   PortablePackageTransaction.swift` ~L1141, L1151, L1201 (`fullSync`), `PortableLibraryBackup.swift`
   ~L655, L685, `PortableLibraryRestore.swift` ~L344. Delete the conditional and keep the macOS body.
3. `Sources/KromoraKit/Views/PreviewSurface.swift` ~L1949 `commandBuffer.waitUntilCompleted()` is a
   test-only seam inside production code. Find who sets it (`grep -rn "waitUntilCompleted" Sources
   Tests`) and move the synchronization into the test target (e.g. inject a completion closure), so
   production code never blocks on GPU completion.

## Acceptance criteria

- [ ] `grep -n "try!" Sources/KromoraKit/Models/PortableLibraryPackage.swift` is empty.
- [ ] `grep -rn "#if os(macOS)" Sources` is empty (or each remaining one is justified in a comment in
      the review reply).
- [ ] Production `PreviewSurface` no longer contains `waitUntilCompleted`; the affected tests still
      pass without it (`scripts/ci-tests.sh serial`).
- [ ] No behavior change.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).
- [ ] `scripts/ci-tests.sh serial` exits 0.
