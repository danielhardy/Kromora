---
id: LUMO-230
title: Remove unused LumoMaskOverlayCapture executable
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Remove the LumoMaskOverlayCapture executable product and target
      result: pass
    - criterion: Remove the standalone capture entry point and retire its wrapper/documented commands
      result: pass
    - criterion: Update package-settings tests and references
      result: pass
    - criterion: Preserve in-app mask overlay implementation and reusable performance tests
      result: pass
    - criterion: swift run launches Lumo without multiple executable products; build checks pass
      result: pass
  checks_run:
    - "swift package dump-package: products are Lumo executable and LumoKit library only"
    - "swift build: passes"
    - "swift build -c release: passes"
    - "swift run: Lumo built and launched without the multiple-products error"
    - "swift test --filter PackageSettingsTests: 3 tests, 0 failures"
    - "swift test --filter PackageSettingsTests|CanvasNavigationTests|CanvasObservationTests|MaskOverlayPerformanceBenchmark: 20 tests, 1 expected benchmark skip, 0 failures"
    - "dg validate: OK"
    - "git diff --check: passes"
  findings:
    - The full swift test run completed with 881 tests, 42 skips, and 23 failures in unrelated pre-existing asynchronous AppViewModel/comparison/persistence/navigation tests; issue-specific and masking/package checks pass.
  fixes: []
  verification_commits:
    - da64900
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-05T15:35:58.120Z
  session: 01MTOJFSQK9BNMRV7Q
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - tooling
  - cleanup
  - masking
created: 2026-09-05T12:06:59.891Z
updated: 2026-09-07T04:02:47.973Z
order: iad8xelv
board: product
commits:
  - da64900
---

## Objective

Remove the standalone `LumoMaskOverlayCapture` executable now that normal Lumo development does
not require the dedicated mask-overlay capture host.

## Context

`Package.swift` currently declares two executable products, so a bare `swift run` fails with
“multiple executable products available.” `LumoMaskOverlayCapture` was added for the LUMO-227
Instruments/pointer-capture workflow and is not part of the normal Lumo app. Keeping the obsolete
product adds build and maintenance surface and makes the documented quick-start command
ambiguous.

## Acceptance criteria

- [ ] Remove the `LumoMaskOverlayCapture` executable product and target from `Package.swift`.
- [ ] Remove the standalone capture entry point and retire or update
      `scripts/run-lumo-227-capture.sh` and any README/docs instructions that invoke it.
- [ ] Update package-settings tests and other references so they no longer require the removed
      executable target.
- [ ] Preserve the in-app mask-overlay implementation and reusable performance tests unless a
      reference is exclusively capture-host-specific.
- [ ] `swift run` launches the `Lumo` executable without the multiple-products error, and
      `swift build` plus `swift test` pass.

## Implementation notes

Historical LUMO-217/LUMO-227 measurements may retain their factual references to the capture host,
but should clearly indicate when the workflow is no longer available if those docs remain.

Out of scope: changing mask-overlay behavior or revisiting the overlay rendering architecture.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-05T15:35:58.122Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Remove the LumoMaskOverlayCapture executable product and target (pass)
- [x] Remove the standalone capture entry point and retire its wrapper/documented commands (pass)
- [x] Update package-settings tests and references (pass)
- [x] Preserve in-app mask overlay implementation and reusable performance tests (pass)
- [x] swift run launches Lumo without multiple executable products; build checks pass (pass)
Checks run:
- swift package dump-package: products are Lumo executable and LumoKit library only
- swift build: passes
- swift build -c release: passes
- swift run: Lumo built and launched without the multiple-products error
- swift test --filter PackageSettingsTests: 3 tests, 0 failures
- swift test --filter PackageSettingsTests|CanvasNavigationTests|CanvasObservationTests|MaskOverlayPerformanceBenchmark: 20 tests, 1 expected benchmark skip, 0 failures
- dg validate: OK
- git diff --check: passes
Findings:
- The full swift test run completed with 881 tests, 42 skips, and 23 failures in unrelated pre-existing asynchronous AppViewModel/comparison/persistence/navigation tests; issue-specific and masking/package checks pass.
Fixes:
- None
Verification commits:
- da64900
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTOJFSQK9BNMRV7Q
Summary: Removed the obsolete LumoMaskOverlayCapture product, target, capture-only sources, and LUMO-227 wrapper; updated package-settings coverage and marked historical capture documentation as retired while preserving the in-app mask overlay and reusable benchmark.
