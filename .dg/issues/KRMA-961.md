---
id: KRMA-961
title: "Logging hygiene: no print(), release-safe levels, lazy detail strings"
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The two source print calls become Logger error calls with a domain category and private file names and errors.
      result: pass
      notes: Both LUTLibrary failure paths use the lut-library Logger category; the filename and error values are private. No source print() calls remain.
    - criterion: The three diagnostic notice mirrors use debug or info, and signposts remain unchanged.
      result: pass
      notes: Thumbnail, photo-switch, and mask mirrors use .debug; the performance signpost paths are unchanged.
    - criterion: Diagnostic detail strings are lazy, with a unit test proving disabled logging does not evaluate the closure.
      result: pass
      notes: The diagnostic APIs use @autoclosure and gate detail evaluation on debug logging or signpost enablement. ObservabilityTests exercise the disabled and enabled paths.
    - criterion: docs/TESTING.md documents the log stream level needed to see debug diagnostics.
      result: pass
      notes: The stream example uses --level debug and explains release persistence and lazy details.
    - criterion: swift build is warning-free and Swift 6 mode has no forbidden concurrency escape hatches or availability branches.
      result: pass
      notes: swift build completed without diagnostics. The fast lane passed PackageSettingsTests for Swift 6 mode and concurrency escape hatches.
    - criterion: scripts/ci-tests.sh fast exits 0.
      result: pass
      notes: The lane completed all 1,978 selected tests with exit 0 and no failures.
  checks_run:
    - swift build — exit 0; no warnings or diagnostics
    - scripts/ci-tests.sh fast — exit 0; 1,978 selected tests passed
    - Structural review — no print() calls in Sources and no .notice calls in Observability.swift
    - git diff --exit-code HEAD -- reviewed implementation, test, and documentation files — passed
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-15T00:13:42.088Z
  session: 01MV8S6Y5LU40WJ8CT
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - nice-to-have
  - observability
  - cleanup
created: 2026-10-13T14:48:11.390Z
updated: 2026-10-15T00:13:42.092Z
parent: KRMA-922
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-15T00:08:56.328Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
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


### Comment — claude @ 2026-10-15T00:08:59.226Z

Implemented in a43e1b99: both print calls -> Logger.error (lut-library category, file name/error .private); mask/thumbnail/photo-switch mirrors now .debug through KromoraDiagnosticLog; detail is @autoclosure and evaluated only when the log or signpost stream is enabled; two ObservabilityTests prove the closure is not evaluated when disabled (injectable isEnabled/emit); TESTING.md notes --level debug. swift build warning-free; scripts/ci-tests.sh fast exit 0 (no failures).

## Agent log

- 2026-10-15T00:13:42.088Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The two source print calls become Logger error calls with a domain category and private file names and errors. (pass) — Both LUTLibrary failure paths use the lut-library Logger category; the filename and error values are private. No source print() calls remain.
- [x] The three diagnostic notice mirrors use debug or info, and signposts remain unchanged. (pass) — Thumbnail, photo-switch, and mask mirrors use .debug; the performance signpost paths are unchanged.
- [x] Diagnostic detail strings are lazy, with a unit test proving disabled logging does not evaluate the closure. (pass) — The diagnostic APIs use @autoclosure and gate detail evaluation on debug logging or signpost enablement. ObservabilityTests exercise the disabled and enabled paths.
- [x] docs/TESTING.md documents the log stream level needed to see debug diagnostics. (pass) — The stream example uses --level debug and explains release persistence and lazy details.
- [x] swift build is warning-free and Swift 6 mode has no forbidden concurrency escape hatches or availability branches. (pass) — swift build completed without diagnostics. The fast lane passed PackageSettingsTests for Swift 6 mode and concurrency escape hatches.
- [x] scripts/ci-tests.sh fast exits 0. (pass) — The lane completed all 1,978 selected tests with exit 0 and no failures.
Checks run:
- swift build — exit 0; no warnings or diagnostics
- scripts/ci-tests.sh fast — exit 0; 1,978 selected tests passed
- Structural review — no print() calls in Sources and no .notice calls in Observability.swift
- git diff --exit-code HEAD -- reviewed implementation, test, and documentation files — passed
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV8S6Y5LU40WJ8CT
Summary: Counterpoint verification passed; build and full fast lane succeeded with no findings or verification fixes.
