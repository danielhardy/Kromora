---
id: KRMA-901
title: Run dust analysis off the main actor and coalesce threshold requests
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: An injected worker check proves synchronous detection runs off MainActor; a main-actor sentinel progresses while worker analysis is gated.
      result: pass
      notes: Deterministic worker observer and gated analysis test confirm worker execution while the main actor progresses.
    - criterion: A burst of threshold requests produces bounded active and pending work and ultimately publishes the final threshold result.
      result: pass
      notes: Burst test confirms one proxy arrival, one analysis, one selection, and final-threshold output.
    - criterion: Repeated thresholds for one source reuse expensive source analysis; a source change invalidates it. Assert call counts rather than wall-clock speed.
      result: pass
      notes: Call-count test confirms reuse and reanalysis after a source fingerprint change.
    - criterion: Generated-image detector tests preserve output, thresholds, stable IDs and seeds, and precision/recall contracts across representative thresholds and result caps.
      result: pass
      notes: Detector precision/recall and determinism tests pass; threshold selection matches direct detection for representative thresholds and caps.
    - criterion: Source switch, feature disable, cancellation and shutdown retain all prerequisite race protections.
      result: pass
      notes: Existing gated source-switch, disable, supersession, and shutdown regressions pass.
    - criterion: No display capture, real camera fixture, huge-file stress run, or machine-specific timing threshold is required.
      result: pass
  checks_run:
    - swift build — passed
    - swift test --no-parallel with RetouchDustDetectorTests, RetouchWorkflowCoordinatorTests, and PackageSettingsTests — passed; 28 tests, 0 failures
    - dg validate — passed; existing agent model-name warnings
    - git diff --check — passed
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-12T21:42:25.960Z
  session: 01MV5S17C0YTJ4MM4J
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - swift
  - app-view-model
  - maintainability
  - concurrency
created: 2026-10-12T17:11:38.491Z
updated: 2026-10-24T13:05:01.244Z
blockers: []
order: zzy
board: product
context:
  files:
    - Sources/KromoraKit/ViewModels/RetouchWorkflowCoordinator.swift
    - Sources/KromoraKit/Models/RetouchAnalysis/RetouchDustDetector.swift
    - Tests/KromoraKitTests/RetouchDustDetectorTests.swift
    - Tests/KromoraKitTests/RetouchWorkflowCoordinatorTests.swift
    - Sources/KromoraKit/Models/RetouchAnalysis/RetouchAnalysisProxy.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
  docs:
    - CLAUDE.md
    - AGENTS.md
    - docs/APP_ARCHITECTURE.md
    - docs/ENGINEERING_GUIDE.md
  issues:
    - KRMA-900
  commands:
    - swift build
    - swift test --no-parallel --filter 'RetouchDustDetectorTests|RetouchWorkflowCoordinatorTests|PackageSettingsTests'
    - dg validate
    - git diff --check
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/ViewModels/AppViewModel.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/ViewModels/RetouchWorkflowCoordinator.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/Models/RetouchAnalysis/RetouchDustDetector.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/RetouchDustDetectorTests.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/RetouchWorkflowCoordinatorTests.swift
      access: write
      confidence: 1
  observed:
    paths: []
    captured_at: 2026-10-12T21:40:15.746Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Keep retouch controls responsive by moving synchronous dust detection off MainActor, bounding active/pending analysis, and reusing source-dependent analysis across threshold changes.

## Evidence

`AppViewModel.detectRetouchDust()` executes `RetouchDustDetector.detect` at approximately line 3475 inside an explicitly main-actor task. `refreshRetouchVisualization` calls the same synchronous detector at 3488 and inherits MainActor from AppViewModel. The asynchronous engine proxy request does not move the later synchronous detector off-main. Every threshold slider value starts another unstructured task (3461-3464).

The detector computes three separable Gaussian blurs, difference buffers, peak search, and sorting over a proxy with a 1024-pixel long-edge cap. A 2026-10-12 window-independent `swiftc -O` probe over uniform Lab pixels measured about 25.6 ms at 512x512 and 101.5 ms at 1024x1024, excluding proxy generation. These single-machine observations establish meaningful CPU work; they are not portable acceptance thresholds. Apple discusses inherited main-actor task execution in https://developer.apple.com/documentation/xcode/improving-app-responsiveness.

## Context to read

- KRMA-900: implement and retain its source/request fences first.
- `Sources/KromoraKit/Models/RetouchAnalysis/RetouchDustDetector.swift`: blur, local maxima, smooth-region gate, sort and deduplication.
- `Sources/KromoraKit/Models/RetouchAnalysis/RetouchAnalysisProxy.swift`: Sendable Lab buffer boundary.
- `Sources/KromoraKit/Models/RenderEngine.swift`: `retouchAnalysisProxy`, `retouchProxy`, cached neutral source proxy.
- `Sources/KromoraKit/ViewModels/RetouchWorkflowCoordinator.swift`, `AppViewModel.swift`, and `Views/RetouchInspectorView.swift` threshold binding.
- `RetouchDustDetectorTests`, `RetouchWorkflowCoordinatorTests`, and `docs/RETOUCH.md` if detector behavior is documented there.

## Implementation steps

1. Run detector work through an explicit worker actor or an owned off-main task that accepts only Sendable proxy/settings values. An inherited `Task {}` around the synchronous call is insufficient. MainActor continues to own interaction-state publication.
2. Make analysis latest-request-wins with at most one active calculation and one replaceable pending request. Repeated slider events must not create an unbounded queue of full-image detections or engine proxy requests. Capture the requested threshold rather than reading mutable UI state halfway through work.
3. Cache the source-dependent blur/response products or threshold-independent candidate analysis, keyed by source identity and detector configuration. Apply threshold-specific selection without redoing three blurs on every slider tick. Preserve existing selection order, maximum-result semantics, confidence, seeds and source-normalized coordinates. Separate threshold-independent stages carefully because confidence and acceptance depend on the gate.
4. Add cooperative cancellation checks at bounded stages/rows when useful; preserve the publication fences from the prerequisite even if work ignores cancellation. Explicitly cancel and await owned worker work on source replacement and shutdown.
5. Keep renderer/Core Image objects inside RenderEngine. Do not move CPU detection into the interactive render actor where it could delay preview rendering, and do not add concurrency opt-outs.

## Acceptance criteria

- [ ] An injected worker/executor check proves synchronous detection runs off MainActor; a main-actor sentinel progresses while worker analysis is gated.
- [ ] A burst of threshold requests produces bounded active/pending work and ultimately publishes the final threshold's result.
- [ ] Repeated thresholds for one source reuse expensive source analysis; a source change invalidates it. Assert call counts rather than wall-clock speed.
- [ ] Existing generated-image detector tests preserve output, thresholds, stable IDs/seeds, and precision/recall contracts across representative thresholds and result caps.
- [ ] Source switch, feature disable, cancellation and shutdown retain all prerequisite race protections.
- [ ] No display capture, real camera fixture, huge-file stress run, or machine-specific timing threshold is required.

## Coordination

Depends on KRMA-900. Keep this ticket focused on scheduling and reusable analysis; do not alter the Heal solver, brush behavior, or introduce a new document owner. If an algorithmic change changes outputs, separate it into a justified follow-up rather than silently weakening quality assertions.

## Reading the source context

Source and test paths above are relative to the repository root, `/Users/dhardy/Dev/Kromora`. The installed `dg context` reader currently resolves file/doc contents inside the `.dg` space, so it can list existing repository sources as missing. Read those paths directly from the checkout; their existence was verified when this ticket was written. Keep the repository-relative context hints for planning. Do not copy product source into `.dg` or weaken DispatchGraph path validation to work around this reader limitation.

## Required checks

```sh
swift build
swift test --no-parallel --filter 'RetouchDustDetectorTests|RetouchWorkflowCoordinatorTests|PackageSettingsTests'
dg validate
git diff --check
```

Run any newly added collaborator suite as well. These are targeted regression checks; broaden them only when the changed boundary or new failures justify it.

## Repository constraints and implementation handoff

- Read `CLAUDE.md` and `.dg/AGENTS.md`, then claim this issue before code changes. Work on the current branch and preserve unrelated working-tree changes. Execute one issue at a time; dependency tickets must be implemented before dependent work.
- Target macOS 26+ on Apple Silicon, Swift 6, Apple frameworks only. No backwards-compatibility fallback, third-party dependency, @unchecked Sendable, nonisolated(unsafe), or @preconcurrency. Keep application implementation inside KromoraKit and retain AppViewModel's existing line-count ceiling.
- Use generated temporary fixtures and deterministic continuation/event gates. Put package/index/cache paths under test-owned temporary directories. Do not run display-bound release capture scripts or use arbitrary sleeps as proof of cancellation correctness.
- Run the focused checks below plus `dg validate` and `git diff --check`. Record commands, outcomes and any environmental limitation. Existing green tests do not replace new regression coverage for this issue.
- Commit coherent issue work with this issue ID followed by a colon in the subject. Follow the implementation handoff to `review`; do not mark done or bypass independent verification. Update architecture guidance only for the final ownership/behavior.


### Comment — claude @ 2026-10-12T21:40:11.309Z

Dust analysis now runs in RetouchDustAnalysisWorker (actor), off MainActor. Each lane has one active and one replaceable pending request, with KRMA-900 generation/source fences kept. Blur/DoG products are cached per source fingerprint; thresholds only redo selection. Detector split into analyze/select, and output is asserted identical to detect(). New tests cover off-main execution with a main-actor sentinel, burst coalescing with the final threshold winning, and analysis reuse with source invalidation. The superseded-request test was rewritten for the bounded queue semantics. Checks: swift build; focused swift test (28 pass); AppViewModelTests (44 pass); dg validate; git diff --check. Commit d598965b.

## Agent log

- 2026-10-12T21:42:25.960Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] An injected worker check proves synchronous detection runs off MainActor; a main-actor sentinel progresses while worker analysis is gated. (pass) — Deterministic worker observer and gated analysis test confirm worker execution while the main actor progresses.
- [x] A burst of threshold requests produces bounded active and pending work and ultimately publishes the final threshold result. (pass) — Burst test confirms one proxy arrival, one analysis, one selection, and final-threshold output.
- [x] Repeated thresholds for one source reuse expensive source analysis; a source change invalidates it. Assert call counts rather than wall-clock speed. (pass) — Call-count test confirms reuse and reanalysis after a source fingerprint change.
- [x] Generated-image detector tests preserve output, thresholds, stable IDs and seeds, and precision/recall contracts across representative thresholds and result caps. (pass) — Detector precision/recall and determinism tests pass; threshold selection matches direct detection for representative thresholds and caps.
- [x] Source switch, feature disable, cancellation and shutdown retain all prerequisite race protections. (pass) — Existing gated source-switch, disable, supersession, and shutdown regressions pass.
- [x] No display capture, real camera fixture, huge-file stress run, or machine-specific timing threshold is required. (pass)
Checks run:
- swift build — passed
- swift test --no-parallel with RetouchDustDetectorTests, RetouchWorkflowCoordinatorTests, and PackageSettingsTests — passed; 28 tests, 0 failures
- dg validate — passed; existing agent model-name warnings
- git diff --check — passed
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV5S17C0YTJ4MM4J
Summary: Verification passed: off-main analysis, bounded threshold coalescing, analysis reuse, and prerequisite race protections are covered; all declared checks pass.
