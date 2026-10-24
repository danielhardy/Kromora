---
id: KRMA-929
title: Make the zero-warning gate pass (fix ColorMixerTests interpolation bug)
type: task
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: 'The ColorMixerTests assertion message uses real interpolation: "\(name) should visibly desaturate a 210° sky".'
      result: pass
      notes: The requested message is present in the test source; the implementation commit also fixes adjacent interpolations.
    - criterion: scripts/ci-tests.sh warning-gate exits 0; additional warnings are fixed at root cause without suppressions.
      result: pass
      notes: Exit 0 with -warnings-as-errors. The changed notification observer counters use Synchronization.Mutex; no warning suppressions or -Wno flags were added.
    - criterion: swift test --filter ColorMixerTests passes.
      result: pass
      notes: 10 tests passed, 0 failures.
    - criterion: The requested grep sanity scan is run; true positives are fixed and findings are reported.
      result: pass
      notes: Scan output contains the intentional (space) phrase, intentional photo(s) wording, and strings with escaped interpolation; no remaining unescaped variable-name assertion messages were found.
    - criterion: swift build is warning-free and Swift 6 mode remains clean without new forbidden escape hatches or availability branches.
      result: pass
      notes: "swift build exited 0 without diagnostics. KRMA-929 changes introduce no @unchecked Sendable, nonisolated(unsafe), @preconcurrency, or #available usage."
    - criterion: scripts/ci-tests.sh fast exits 0.
      result: pass
      notes: Exit 0; lane audit covered 2,401 tests (1,807 required fast, 541 required serial, 53 optional), and all 1,807 required fast tests passed.
  checks_run:
    - scripts/ci-tests.sh warning-gate (exit 0; warnings treated as errors)
    - swift test --filter ColorMixerTests (10 passed)
    - Requested grep sanity scan of Tests/KromoraKitTests (no true positive typo remains)
    - swift build (exit 0; no diagnostics)
    - scripts/ci-tests.sh fast (exit 0; 1,807 required fast tests passed)
    - Reviewed KRMA-929 implementation commit b154a26f
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T18:43:15.245Z
  session: 01MV70Z6RBDGXC74FW
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - must-fix
  - tests
  - warnings
created: 2026-10-13T14:47:39.934Z
updated: 2026-10-13T18:43:15.248Z
parent: KRMA-922
blockers: []
order: zj
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T18:33:35.147Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

`scripts/ci-tests.sh warning-gate` (`swift build --build-tests -Xswiftc -warnings-as-errors`) exits 0.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding M4 (third bullet). The gate fails on a real test bug:
`Tests/KromoraKitTests/ColorMixerTests.swift` ~L199 passes the literal string
`"(name) should visibly desaturate a 210° sky"` as an assertion message. It is missing the
interpolation backslash, so it prints the text "(name)" instead of the channel name (the loop above
binds `name` from `[("cyan", ...), ("blue", ...)]`). KRMA-920 also reported the gate failing; there
may be more than this one diagnostic.

## Acceptance criteria

- [ ] The message is `"\(name) should visibly desaturate a 210° sky"` (real interpolation).
- [ ] `scripts/ci-tests.sh warning-gate` exits 0. If it reports additional warnings, fix each at its
      root cause (do not add `// swiftlint:disable`-style suppressions or `-Wno-` flags) and list them
      in the review comment.
- [ ] `swift test --filter ColorMixerTests` passes.
- [ ] Run `grep -rnE '"[^"\\]*\((name|[a-z][A-Za-z]*)\)[^"]*"' Tests/KromoraKitTests | head` as a
      sanity scan for the same typo elsewhere and report what you found (fix any true positives).
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).


### Comment — claude @ 2026-10-13T18:33:30.924Z

ColorMixerTests L199 was already fixed upstream. Warning gate now exits 0 (was failing on KeyboardSurfaceWindowTests L184/185: mutation of captured vars in a Sendable observer closure; fixed with Mutex from Synchronization). Typo scan found true positives, fixed: ColorMixerTests L151/153 (channelIndex), EffectsPipelineTests L323 (value), PhotosDeliveryTests L45 (description). False positive left alone: CurrentEditMeasurementTests L564 ('(space)' is not a binding in scope). Others in the scan were intentional literals. ColorMixerTests pass; ci-tests.sh fast exits 0.

## Agent log

- 2026-10-13T18:43:15.245Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The ColorMixerTests assertion message uses real interpolation: "\(name) should visibly desaturate a 210° sky". (pass) — The requested message is present in the test source; the implementation commit also fixes adjacent interpolations.
- [x] scripts/ci-tests.sh warning-gate exits 0; additional warnings are fixed at root cause without suppressions. (pass) — Exit 0 with -warnings-as-errors. The changed notification observer counters use Synchronization.Mutex; no warning suppressions or -Wno flags were added.
- [x] swift test --filter ColorMixerTests passes. (pass) — 10 tests passed, 0 failures.
- [x] The requested grep sanity scan is run; true positives are fixed and findings are reported. (pass) — Scan output contains the intentional (space) phrase, intentional photo(s) wording, and strings with escaped interpolation; no remaining unescaped variable-name assertion messages were found.
- [x] swift build is warning-free and Swift 6 mode remains clean without new forbidden escape hatches or availability branches. (pass) — swift build exited 0 without diagnostics. KRMA-929 changes introduce no @unchecked Sendable, nonisolated(unsafe), @preconcurrency, or #available usage.
- [x] scripts/ci-tests.sh fast exits 0. (pass) — Exit 0; lane audit covered 2,401 tests (1,807 required fast, 541 required serial, 53 optional), and all 1,807 required fast tests passed.
Checks run:
- scripts/ci-tests.sh warning-gate (exit 0; warnings treated as errors)
- swift test --filter ColorMixerTests (10 passed)
- Requested grep sanity scan of Tests/KromoraKitTests (no true positive typo remains)
- swift build (exit 0; no diagnostics)
- scripts/ci-tests.sh fast (exit 0; 1,807 required fast tests passed)
- Reviewed KRMA-929 implementation commit b154a26f
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV70Z6RBDGXC74FW
Summary: Verification passed: warning gate, focused ColorMixer tests, warning-free build, typo scan, and fast CI lane all passed.
