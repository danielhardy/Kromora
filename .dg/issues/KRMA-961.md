---
id: KRMA-961
title: "Logging hygiene: no print(), release-safe levels, lazy detail strings"
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
  - observability
  - cleanup
parent: KRMA-922
created: 2026-10-13T14:48:11.390Z
updated: 2026-10-13T14:48:23.584Z
blockers: []
order: zzx
board: product
---

## Objective

Make logging production-quality: no `print()`, no persisted noise at `.notice` in release, and no
eager string building outside `os_log` interpolation.

## Context

Review `.context/2026-10-13-release-readiness-review.md` "Nice to have: Logging". Note: the subsystem mismatch (`com.kromora.app` vs bundle ID
`com.last8.kromora.photo`) is already ticket KRMA-892; do not do it here.

- `print()` calls: `Sources/KromoraKit/Models/LUTLibrary.swift:283` ("Failed to save bookmark") and
  `:580` ("Skipping … error"). (`grep -rn "print(" Sources` also matches `*Fingerprint(`; filter for
  real calls.)
- `Sources/KromoraKit/Models/Observability.swift` ~L317/329/337: `thumbnailLog.notice`,
  `photoSwitchLog.notice`, `maskLog.notice` persist to the log store in release builds.
- Detail strings are built eagerly before logging, e.g. `ImageSource.swift` builds
  `String(format: "hashMs=%.1f …")` in a `defer` even when logging is disabled
  (`KromoraObservability.photoSwitchPhase(…, detail:)`).

## Acceptance criteria

- [ ] The two `print` calls become `Logger` calls (category matching the file's domain, error level for
      failures, `privacy: .public` only for non-sensitive values, file names `.private`).
- [ ] The three `.notice` logs become `.debug` (or `.info` where the data helps field diagnosis and is
      small); performance signposts are untouched (they are not persisted).
- [ ] `detail` is an `@autoclosure () -> String` (or equivalent) so the string is built only when the
      log level is enabled; update the call sites mechanically. Add a unit test that the closure is not
      evaluated when disabled (use a test seam; if none exists, make the level check injectable).
- [ ] `docs/TESTING.md` log-stream examples still apply (levels documented where they are described;
      note that `.debug` needs `log stream --level debug`).
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).
