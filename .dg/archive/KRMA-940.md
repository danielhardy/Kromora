---
id: KRMA-940
title: Plan the AppViewModel @Observable migration into small child tickets
type: task
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Plan inventories every AppViewModel @Published property and every @ObservedObject/@EnvironmentObject AppViewModel consumer, grouped by readers.
      result: pass
      notes: "The plan contains the 30 root @Published properties plus InspectorState's two properties and groups their view readers. Source inventory remains consistent: 30 declarations; no @EnvironmentObject AppViewModel consumer was found."
    - criterion: Create 6–12 actionable child tickets, one per migration step, with Objective, file/line Context, step-specific Acceptance criteria, the required labels, and a chained dependency order.
      result: pass
      notes: KRMA-972 through KRMA-981 each have concrete Objective, Context, Acceptance criteria, and Implementation notes; all carry release-readiness, should-fix, and swiftui labels. The step 1–10 dependency chain matches the plan ticket map.
    - criterion: Plan describes a non-display-bound way to measure view re-evaluation per step.
      result: pass
      notes: The plan specifies a window-independent NSHostingView body probe, withObservationTracking checks, structural assertions, and explicitly excludes display-bound capture.
    - criterion: No production code changes; swift build remains green.
      result: pass
      notes: No product source files were changed during verification. swift build completed successfully (exit 0).
  checks_run:
    - dg validate — pass (exit 0; existing model-name warnings only)
    - git diff --check — pass (exit 0)
    - swift build — pass (exit 0)
    - Child-ticket structural audit — pass (10 tickets; required sections, labels, plan map, and dependency chain verified)
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T20:40:09.679Z
  session: 01MV7590TI9B531TFG
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - performance
  - swiftui
  - needs-decomposition
created: 2026-10-13T14:47:50.106Z
updated: 2026-10-13T20:40:09.682Z
parent: KRMA-922
blockers: []
order: n
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T19:37:21.028Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Produce a staged, low-risk plan (and the child tickets) for moving `AppViewModel` and its child state
objects from `ObservableObject` to `@Observable` so a slider tick re-evaluates only the views that
read the changed property.

> **Sizing note:** this ticket is a planning/investigation step. It is deliberately NOT an implementation ticket; its deliverable is a written plan plus child tickets small enough for a lower-capability agent. Label `needs-decomposition`.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding S1.

- `Sources/KromoraKit/ViewModels/AppViewModel.swift` is an `ObservableObject` with 41 `@Published`
  properties and synchronous `objectWillChange` forwarding from seven child objects (~L1393).
- About 20 views hold it with `@ObservedObject` (inspectors, status bar, culling bar, grid rows,
  masking workspace). Every `document` publish (each slider tick) re-evaluates all of them.
- The file is 5,111 lines (6,511 with extensions) against a 5,120-line structural guard (see the test
  that enforces it: `grep -rn 5120 Tests`). Stay under it.
- Prior art: KRMA-907/908/909/910 (backlog) already propose observing feature state directly in the
  consuming views; read them, and prefer to fold them into this plan rather than duplicate.
- Constraints: macOS 26+, Swift 6 mode, zero escape hatches, no `#available`. `@Observable` (Observation
  framework) and `@MainActor` isolation are the target idiom.

## Acceptance criteria

- [ ] `docs/APP_VIEWMODEL_OBSERVATION_PLAN.md` (new) lists every `@Published` property on
      `AppViewModel` and every `@ObservedObject var viewModel`/`@EnvironmentObject` consumer
      (generate with `grep`, do not guess), and groups properties by who reads them.
- [ ] The plan picks a migration order that keeps `swift build` + tests green after each step (e.g.
      leaf child objects first, then root). Each step is one child ticket (6-12 total), each with
      Objective, Context (files/lines), Acceptance criteria (including a structural or re-evaluation
      test where practical), created with `dg issue create` and labelled
      `release-readiness,should-fix,swiftui`, `depends_on` chained in order.
- [ ] Plan states how re-evaluation will be MEASURED per step without display-bound benchmarks (e.g. a
      counting `body` probe in a serial test, not `scripts/run-kromora-capture.sh`).
- [ ] No production code changes in this ticket except, optionally, test probes.
- [ ] `swift build` stays green; this ticket does not touch behavior.

## Implementation notes

Use the AppViewModel size guard as a design constraint: each step should shrink or hold the file.
Do not start migrating in this ticket.

## Verification blocker (2026-10-13)

The staged plan and child issue records do not yet meet acceptance criterion 2. KRMA-972 through
KRMA-981 have only generated boilerplate bodies: each has a generic Objective, placeholder Context,
and an empty Acceptance criteria list. The plan's ticket map therefore points to ten tickets that
are not actionable by a lower-capability implementation agent.

Before this issue can pass, replace each child body with its step-specific Objective, concrete
Context naming the relevant source/test/doc files and key symbols or line locations, Acceptance
criteria that define behavior and a structural or re-evaluation check where practical, and
Implementation notes that preserve the migration constraints and `AppViewModel.swift` size ceiling.
Keep the existing labels and dependency chain. Ensure the probe/baseline ticket defines its
measurement output and later tickets identify how that probe will verify their step.

Verify by reading all ten child issue bodies and confirming no placeholder sections or empty
criteria remain; confirm the `depends_on` chain matches steps 1–10 and the plan's ticket map; run
`dg validate` and `git diff --check`. No product source change is required for this correction.

## Agent log

- 2026-10-13T19:39:00.090Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] Plan inventories every AppViewModel @Published property and every @ObservedObject/@EnvironmentObject AppViewModel consumer, grouped by readers. (pass) — The plan lists 30 root properties plus the two InspectorState properties and the consuming view groups; source grep confirms the property count.
- [ ] Create 6–12 actionable child tickets, one per migration step, with Objective, file/line Context, step-specific Acceptance criteria, the required labels, and a chained dependency order. (fail) — KRMA-972 through KRMA-981 exist and have the labels/dependency chain, but each has a placeholder Context and empty Acceptance criteria. They are not actionable tickets.
- [x] Plan describes a non-display-bound way to measure view re-evaluation per step. (pass) — The plan describes body/observation probes and structural assertions, and excludes display-bound capture.
- [x] No production code changes; swift build remains green. (pass) — No product source changes were made; swift build succeeded.
Checks run:
- swift build — pass (exit 0)
- dg validate — pass (exit 0; existing model-name warnings only)
- git diff --check — pass (exit 0)
- grep inventory — 30 AppViewModel @Published declarations plus 2 InspectorState declarations, matching the plan
Findings:
- Blocking: all ten child issues have boilerplate-only bodies with placeholder Context and no acceptance criteria; this defeats the ticket's primary deliverable of small, actionable implementation steps.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV731TRDBX8KLDE5
Summary: Blocked: KRMA-972 through KRMA-981 need concrete context and acceptance criteria before the staged plan is actionable.

- 2026-10-13T20:40:09.679Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Plan inventories every AppViewModel @Published property and every @ObservedObject/@EnvironmentObject AppViewModel consumer, grouped by readers. (pass) — The plan contains the 30 root @Published properties plus InspectorState's two properties and groups their view readers. Source inventory remains consistent: 30 declarations; no @EnvironmentObject AppViewModel consumer was found.
- [x] Create 6–12 actionable child tickets, one per migration step, with Objective, file/line Context, step-specific Acceptance criteria, the required labels, and a chained dependency order. (pass) — KRMA-972 through KRMA-981 each have concrete Objective, Context, Acceptance criteria, and Implementation notes; all carry release-readiness, should-fix, and swiftui labels. The step 1–10 dependency chain matches the plan ticket map.
- [x] Plan describes a non-display-bound way to measure view re-evaluation per step. (pass) — The plan specifies a window-independent NSHostingView body probe, withObservationTracking checks, structural assertions, and explicitly excludes display-bound capture.
- [x] No production code changes; swift build remains green. (pass) — No product source files were changed during verification. swift build completed successfully (exit 0).
Checks run:
- dg validate — pass (exit 0; existing model-name warnings only)
- git diff --check — pass (exit 0)
- swift build — pass (exit 0)
- Child-ticket structural audit — pass (10 tickets; required sections, labels, plan map, and dependency chain verified)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV7590TI9B531TFG
Summary: Pass: all ten observation migration tickets are actionable, correctly labeled, and chained; plan inventory and measurement approach verified.
