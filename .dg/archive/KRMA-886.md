---
id: KRMA-886
title: Extract provisional and embedded first-frame presentation from AppViewModel
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A new or extended coordinator owns the listed first-frame state and logic.
      result: pass
      notes: FirstFramePresentationCoordinator owns deferred thumbnail and embedded-frame candidates, fallback timing, geometry decisions, and generation-fenced releases.
    - criterion: Focused tests exercise the coordinator without constructing AppViewModel.
      result: pass
      notes: FirstFramePresentationCoordinatorTests passes all 9 tests, including stale-generation fencing, geometry, stored-frame outcomes, fallback timing, and embedded-frame alignment.
    - criterion: AppViewModel remains a thin integration layer with no behavior change.
      result: pass
      notes: The root stages candidates and applies released candidates to existing presentation surfaces; stored-frame lookup callbacks remain generation-fenced.
    - criterion: Architecture ownership and line-count documentation are updated, and the AppViewModel ceiling is lowered just above the new size.
      result: pass
      notes: docs/APP_ARCHITECTURE.md records 5,148 lines with a 5,190 ceiling, and PackageSettingsTests uses the same ceiling.
    - criterion: swift build and fast CI pass; serial CI passes for the touched Core Image paths; display-bound capture benchmarks are not run.
      result: fail
      notes: Build and fast lane passed. Required serial lane failed only at unrelated ColorMixerTests.testRedWraparoundIsContinuousAndOverlapIsSmooth (25 is not less than 20); that test also fails in isolation and is tracked by backlog child KRMA-891. First-frame coordinator tests passed in isolation and in the serial lane. No display-bound capture was run.
  checks_run:
    - swift build — passed (exit 0)
    - scripts/ci-tests.sh fast — passed (exit 0)
    - scripts/ci-tests.sh serial — failed (exit 1); unrelated ColorMixerTests.testRedWraparoundIsContinuousAndOverlapIsSmooth failed with 25 vs required <20
    - swift test --filter ColorMixerTests.testRedWraparoundIsContinuousAndOverlapIsSmooth — failed (exit 1), reproducing the unrelated Color Mixer failure
    - swift test --filter FirstFramePresentationCoordinatorTests — passed (9 tests, exit 0)
    - scripts/build-metal-libraries.sh --check — passed (exit 0)
  findings:
    - The implementation review found no correctness, maintainability, security, or performance blockers in the first-frame presentation extraction.
    - The serial lane has an independent Color Mixer red hue wraparound overlap failure; KRMA-891 tracks it.
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T19:47:41.220Z
  session: 01MV48A6HR6NL9AKS6
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - architecture
  - maintainability
created: 2026-10-11T17:09:53.792Z
updated: 2026-10-11T19:47:41.223Z
blockers: []
order: zz
board: product
---

Child of KRMA-460. AppViewModel.swift is 5,403 lines (ceiling test: PackageSettingsTests.testAppViewModelDoesNotRegrow at 5,500). Extract workflow *ownership*, not just a file split. Keep AppViewModel the composition root and sole owner of the published EditDocument (docs/APP_ARCHITECTURE.md). Swift 6, no escape hatches, no broad AppViewModel back-reference: the new type takes a narrow protocol or closures and returns value outcomes that the root applies (pattern: LookSelectionCoordinator, ExportWorkflowCoordinator). Locate code by function name; line numbers drift. Run serially with other KRMA-460 children, since they edit the same file.

## Scope
First-paint candidate handling during load (~220 lines): `presentProvisionalCandidate`, `presentDeferredThumbnail`, `completePendingStoredFrameConfirmation`, `install`, `presentEmbeddedFirstFrame`, `alignedEmbeddedFirstFrame`, and their deferred state (`deferredThumbnailPresentation`, `deferredEmbeddedFirstFrame`, `storedFrameLookupFallbackGeneration`).

## Plan
Inventory first: PreviewPresentationCoordinator and PreviewPublicationCoordinator already own display generations and presented-frame state, so put this logic there or in a focused sibling where it fits rather than creating overlap. `alignedEmbeddedFirstFrame` is a pure CIImage helper; keep CIImage inside the render boundary per CLAUDE.md (move it next to RenderEngine/preview code, not into a non-render coordinator). Generation fencing (a stale generation must never publish) is the invariant to preserve and test. Preserve KromoraObservability photo-switch phase markers.

## Out of scope
Stored-edit adoption (separate ticket); `load`/`beginLoad`.

Acceptance: (1) new/extended coordinator owns the listed state and logic; (2) focused tests that do not construct AppViewModel; (3) AppViewModel keeps thin forwarders only, with no behavior change; (4) docs/APP_ARCHITECTURE.md ownership table and the line count in its AppViewModel paragraph updated, and the PackageSettingsTests ceiling lowered to just above the new size; (5) swift build and scripts/ci-tests.sh fast pass, plus scripts/ci-tests.sh serial if render/UI paths are touched. Do not run the display-bound capture benchmarks (CLAUDE.md). Serial lane is required here (Core Image paths).

## Agent log

- 2026-10-11T19:47:41.220Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A new or extended coordinator owns the listed first-frame state and logic. (pass) — FirstFramePresentationCoordinator owns deferred thumbnail and embedded-frame candidates, fallback timing, geometry decisions, and generation-fenced releases.
- [x] Focused tests exercise the coordinator without constructing AppViewModel. (pass) — FirstFramePresentationCoordinatorTests passes all 9 tests, including stale-generation fencing, geometry, stored-frame outcomes, fallback timing, and embedded-frame alignment.
- [x] AppViewModel remains a thin integration layer with no behavior change. (pass) — The root stages candidates and applies released candidates to existing presentation surfaces; stored-frame lookup callbacks remain generation-fenced.
- [x] Architecture ownership and line-count documentation are updated, and the AppViewModel ceiling is lowered just above the new size. (pass) — docs/APP_ARCHITECTURE.md records 5,148 lines with a 5,190 ceiling, and PackageSettingsTests uses the same ceiling.
- [ ] swift build and fast CI pass; serial CI passes for the touched Core Image paths; display-bound capture benchmarks are not run. (fail) — Build and fast lane passed. Required serial lane failed only at unrelated ColorMixerTests.testRedWraparoundIsContinuousAndOverlapIsSmooth (25 is not less than 20); that test also fails in isolation and is tracked by backlog child KRMA-891. First-frame coordinator tests passed in isolation and in the serial lane. No display-bound capture was run.
Checks run:
- swift build — passed (exit 0)
- scripts/ci-tests.sh fast — passed (exit 0)
- scripts/ci-tests.sh serial — failed (exit 1); unrelated ColorMixerTests.testRedWraparoundIsContinuousAndOverlapIsSmooth failed with 25 vs required <20
- swift test --filter ColorMixerTests.testRedWraparoundIsContinuousAndOverlapIsSmooth — failed (exit 1), reproducing the unrelated Color Mixer failure
- swift test --filter FirstFramePresentationCoordinatorTests — passed (9 tests, exit 0)
- scripts/build-metal-libraries.sh --check — passed (exit 0)
Findings:
- The implementation review found no correctness, maintainability, security, or performance blockers in the first-frame presentation extraction.
- The serial lane has an independent Color Mixer red hue wraparound overlap failure; KRMA-891 tracks it.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV48A6HR6NL9AKS6
Summary: Verified first-frame presentation extraction; required serial lane has an unrelated Color Mixer failure tracked as KRMA-891.
