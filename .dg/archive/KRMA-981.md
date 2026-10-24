---
id: KRMA-981
title: "Observation step 10: Narrow document readers and close out docs"
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: On a real InfoInspectorView with a photo open and the Light tab selected, Light, Color, and Effects document mutations re-evaluate the shell 0 times.
      result: pass
      notes: testInspectorShellDoesNotReadDocumentWithAPhotoOpen passed for all three mutations.
    - criterion: The revised document-reader contract evaluates the Light, Color, Effects, and Preview read-set mirrors once per document mutation, while StatusBar and the Info shell evaluate zero times.
      result: pass
      notes: testDocumentMutationEvaluatesEachDocumentReaderOnce passed with the expected 1/0 counts; per-row and per-section isolation remains deferred under option A.
    - criterion: No stored EditDocument or section copy is added on the slider path, and slider throughput and navigation p95 tests pass.
      result: pass
      notes: "Both named p95 tests passed: slider p95 0.000 ms and navigation p95 0.003 ms."
    - criterion: Slider, undo/redo, reset, and commit tests pass unchanged.
      result: pass
      notes: Fast and serial CI lanes passed with zero failures.
    - criterion: Documentation is updated and the stale Observation wrapper search only finds deliberate historical mentions in the plan.
      result: pass
      notes: Search results were confined to deliberate migration history in APP_VIEWMODEL_OBSERVATION_PLAN.md.
    - criterion: The plan is marked completed with the final before/after table, and the ticket map names KRMA-972 through KRMA-981 as done.
      result: pass
      notes: Confirmed in the plan and ticket map.
    - criterion: AppViewModel.swift line count is not larger.
      result: pass
      notes: The parent and implementation commit each contain 4,992 lines.
  checks_run:
    - "swift build: pass (exit 0)"
    - "scripts/ci-tests.sh fast: pass (1,908 tests, zero failures)"
    - "scripts/ci-tests.sh serial: pass (561 tests, zero failures)"
    - "swift test --no-parallel --filter 'ObservationInvalidationTests/(testSliderValueThroughputP95StaysWithinBudget|testNavigationP95StaysWithinBudget)': pass; slider p95 0.000 ms, navigation p95 0.003 ms"
    - "git diff --check f48b5218^ f48b5218: pass"
    - "Stale ObservableObject/@Published/@ObservedObject/@StateObject search in docs and CLAUDE.md: only deliberate historical mentions in APP_VIEWMODEL_OBSERVATION_PLAN.md"
    - "AppViewModel.swift line counts in parent and implementation commit: 4,992 and 4,992"
    - "Manual smoke in isolated temporary app/package: Light exposure changed to +0.52 EV and histogram reported 3,244 clipped highlights; Color Grading wheel changed to hue 31 degrees/saturation 31 percent, undo returned it to neutral, and redo restored the adjustment; Info/Light/Color/Effects tab navigation and metadata/histogram display worked."
    - Temporary smoke app, package, and isolated preference domain were cleaned up; no smoke app process remains.
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T13:44:23.313Z
  session: 01MV855EO3B2QTXS18
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - swiftui
created: 2026-10-13T19:37:04.033Z
updated: 2026-10-24T13:05:22.981Z
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T12:41:11.552Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Make a slider tick re-evaluate only the views that display the changed value, by narrowing what the mounted inspector, the inspector shell and the preview read from `document`. Then close out the migration: final baseline table, docs, and stale `ObservableObject`/`@Published` guidance.

## Context

Part of `docs/APP_VIEWMODEL_OBSERVATION_PLAN.md` (read it, "Additions from ticket review" and "Common rules"). Depends on KRMA-980 (root is `@Observable`). Read the final baseline table that step 9 produced before changing anything; this step is driven by those numbers.

**Premise correction.** The original wording ("a Light tick must not re-evaluate Color, Effects, Look") is mostly moot in the app. `InfoInspectorView.swift:44-66` mounts exactly one inspector at a time with `switch inspectorState.tab.content`, so Color/Effects/Look are not alive while Light is active. The Light/Color/Effects *mirrors* in the KRMA-972 table are mounted together only to measure read sets. What can still be wasted after the root flip:

1. **The inspector shell.** `InfoInspectorView` (the parent of every tab: histogram section, tab switcher, the switch above) reads `viewModel.document` (for example `crop: viewModel.document.crop` at ~L221). Any `document` change then re-evaluates the shell, which rebuilds the tab switcher and re-creates the child `LightInspectorView(viewModel:)` value. Keep the shell from reading `document`; push that read down into the Info tab's own subview.
2. **Whole-inspector re-evaluation per tick.** Each inspector reads `viewModel.document.<section>` in many places (`LightInspectorView.swift:40, 261, 289, 355, 464, 474`; `EffectsInspectorView.swift:47, 236-248`; `DevelopInspectorView.swift:55`; ColorInspector via `AppViewModel+Light.swift`-style helpers). `document` is one `EditDocument` struct on the root (`Models/EditDocument.swift:13`, sections `light`, `color`, `effects`, `crop`, `retouch`, `lut`, `localAdjustments`, ...), so tracking is per property `document`, not per section: any slider change re-evaluates every view that reads any part of it. For a slider list that means every row rebuilds on each tick, not just the dragged one.
3. **PreviewView, MaskingWorkspace, RetouchCanvasOverlay, RetouchInspectorView** read `document` for sections they do not own.
4. **`.onChange(of: viewModel.document.effects, initial: true)`** (`EffectsInspectorView.swift:47`) compares the whole effects section each tick; confirm it is not on a hot path after narrowing.

Prefer small seams over restructuring `EditDocument`: per-row subviews that take a value or `Binding` (`viewModel.lightBinding(for:)` already exists at `ViewModels/AppViewModel+Light.swift:8`), computed accessors such as `hasLightAdjustments` (L36) evaluated in a subview, and, only if rows still over-invalidate, a small `@Observable` per-section projection that the root updates from `document` with equality checks so unchanged sections do not notify. Do not copy `document` per tick (the ticket's third criterion).

Docs to update (verified stale references): `docs/APP_ARCHITECTURE.md:244` (says `MaskInteractionState` is an `ObservableObject`) and any `ObservableObject`/`@Published`/`@ObservedObject` wording; `docs/ENGINEERING_GUIDE.md` (add a short "Observation" section describing the final model: `@Observable` everywhere, wrapper mapping, `@ObservationIgnored` rule, no Combine forwarding); `docs/TESTING.md:536` (mentions a skipped `@ObservedObject` -> plain reference measurement; point it at the finished plan); `CLAUDE.md` Layout section if it mentions `ObservableObject` (currently it does not; add one line only if useful). Leave `docs/MODEL_ARCHITECTURE.md` alone (its `Combine` line is about model files).

## Approach

1. Run the probe against the post-step-9 build and write the real numbers in the plan table's "after" column. Identify, per row, the views that still re-evaluate more than the view that displays the value.
2. Fix in this order, re-measuring after each: (a) `InfoInspectorView` shell stops reading `document`; (b) the mounted inspectors split into row subviews so one slider re-evaluates its own row (plus anything that displays a derived summary, such as a "reset" button's enabled state); (c) PreviewView/Masking/Retouch reads; (d) the `.onChange` in Effects.
3. Slider commit, undo grouping and debounced document updates (`updateDocument(debounced:)`, `beginPreviewInteraction`/`endPreviewInteraction`) are untouched; this step changes where `document` is *read*, not how it is written.
4. Update docs and mark the plan doc "Status: completed (KRMA-981)" with the final table, and move the "Additions" text into the history of the plan so it reads correctly after the fact.

## Acceptance criteria

- [ ] Shell probe (KRMA-972 helpers): on a real `InfoInspectorView` with a photo open and the Light tab selected, Light, Color and Effects document mutations re-evaluate the shell **0** times (`testInspectorShellDoesNotReadDocumentWithAPhotoOpen`).
- [ ] Document-reader contract (revised 2026-10-14, option A): `document` is one observed property, so a document mutation re-evaluates each view that reads any part of it exactly **1** time (Light, Color, Effects and Preview read-set mirrors) and the StatusBar and Info shell **0** times, pinned by `testDocumentMutationEvaluatesEachDocumentReaderOnce`. Per-row and per-section isolation is deferred (see Decision).
- [ ] No new copies of `EditDocument` on the per-tick path: the change adds no stored `EditDocument` or section copy in a view or model on the slider path, and `testSliderValueThroughputP95StaysWithinBudget` and `testNavigationP95StaysWithinBudget` still pass.
- [ ] Slider, undo/redo, reset and commit tests pass unchanged (inspector tests such as `DevelopInspectorTests`, `NeutralOriginSliderTests`, `LookInspectorViewTests`, and the serial lane in general).
- [ ] Docs updated as listed; `grep -rn "ObservableObject\|@Published\|@ObservedObject\|@StateObject" docs CLAUDE.md` only matches deliberate historical mentions inside the plan doc.
- [ ] The plan doc is marked completed with the final before/after table; the ticket map names KRMA-972 through KRMA-981 as done.
- [ ] `AppViewModel.swift` line count is not larger.

## Verification

```
swift build
scripts/ci-tests.sh fast
scripts/ci-tests.sh serial
```

Manual smoke with `swift run`: drag a Light slider and a Color wheel, confirm the preview and histogram update smoothly, switch inspector tabs, undo/redo.

## Out of scope

Restructuring `EditDocument`, changing render or persistence behavior, and display-bound captures (`scripts/run-kromora-capture.sh`). If the measured gain from (b) is negligible, stop after (a) and (c), record the numbers, and say so in the ticket.

### Comment — claude @ 2026-10-14T12:41:16.162Z

Commit f48b5218. Shell no longer reads document: HistogramSourceBadge and InfoAnalysisSection are leaf subviews. New probe testInspectorShellDoesNotReadDocumentWithAPhotoOpen: shell 0 re-evals (was 1) on Light/Color/Effects edits. fast and serial lanes pass; AppViewModel.swift unchanged at 4994 lines. Not done: (b) row splitting gains nothing because document is one observed property, so every row still re-evaluates; needs a per-section projection (out of scope). Mirror rows for Color/Effects therefore stay at 1 on a document change (criterion 2 as worded cannot hold). (c)/(d) left as-is, reasons in the plan doc. Docs updated; plan marked completed. Not run: manual swift run smoke test.

## Verification blocker — acceptance criteria conflict (2026-10-14)

The serial body probe confirms that a `document` mutation re-evaluates each Light, Color, and Effects
read-set mirror once, and the Preview mirror once; the real `InfoInspectorView` shell remains at 0.
The new real-view probe checks only the shell. It does not establish row-level invalidation in mounted
inspectors, nor does it demonstrate the requested zero invalidations for Color/Effects mirrors.

`AppViewModel.document` is one stored `EditDocument` property on an `@Observable` root. A nested read
such as `document.light.exposure` tracks that same root property, so splitting rows or passing a
`Binding` cannot make untouched rows or section mirrors independent. Meeting the row/mirror criteria
requires a section-granular observation boundary, while another acceptance criterion forbids storing
a section copy or `EditDocument` on the slider path. Resolve this contract before implementation:
either revise the expected deltas to accept per-document invalidation while retaining the shell's 0,
or authorize a concrete section-granular model design that satisfies the no-per-tick-copy constraint.

After that decision, add real mounted Light, Color, and Effects probes with explicit expected counts
for the shell, changed inspector rows/summary readers, and preview; then rerun the two p95 tests and
the fast/serial lanes. The required `swift build`, fast, serial, and named p95 checks pass. The manual
`swift run` smoke was attempted twice, but startup reported that the default package was already being
written by the current SwiftPM process and disabled sample import. No photos were imported or edited;
repeat the smoke against a dedicated temporary library once the launch lock issue is cleared.

## Decision (2026-10-14): option A

Per-row and zero-mirror invalidation cannot hold with `AppViewModel.document` as one stored observable
property while the no-section-copy criterion stands. Measured cost does not justify a fix: slider p95 is
0.000 ms and navigation p95 is 0.002 ms, and the render pipeline, not body re-evaluation, dominates a
tick. Accepted: per-document invalidation, shell at 0, readers at 1. Rejected: a section-granular
projection (a second source of truth with per-tick equality checks) and splitting `EditDocument` into
stored sections (rewrites write paths, undo, persistence and render hand-off; out of scope).
Revisit only if an Instruments trace of a real drag shows inspector body time, as a separate ticket.

Remaining: repeat the manual `swift run` edit/undo smoke against a temporary library once the
writer-lease launch issue is cleared (tracked separately from this contract).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-14T12:54:10.713Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [ ] On a real InfoInspectorView, mutations in each mounted tab update only the affected row and summary readers, with explicit expected shell and preview counts (fail) — The new real-view test checks only the shell at 0 for Light, Color, and Effects document mutations. The serial read-set probe reports one evaluation for the Light, Color, and Effects mirrors and Preview mirror on a document mutation; no production row-level counts are measured.
- [ ] Color, Effects, Look, and Info mirrors stay at 0 re-evaluations on a Light mutation (fail) — The existing read-set mirrors each read the root document property. The serial probe records one evaluation for each inspector mirror that reads document on a document mutation; the final table records those counts as 1.
- [x] No stored EditDocument or section copy is added on the slider path, and slider throughput and navigation p95 tests pass (pass) — No such copies were added. Both named tests pass; measured navigation p95 was 0.002 ms and slider p95 was 0.000 ms. AppViewModel.swift has 4992 lines in both the parent and implementation commit.
- [x] Slider, undo/redo, reset, and commit tests pass (pass) — scripts/ci-tests.sh fast and serial both pass with zero failures; the serial lane executes 560 tests.
- [x] Documentation updates and stale-reference search meet the stated requirements (pass) — The docs are updated; the stale-reference search only finds deliberate migration history in APP_VIEWMODEL_OBSERVATION_PLAN.md.
- [x] The plan is marked completed with the final baseline table and the ticket map lists KRMA-972 through KRMA-981 as done (pass) — The plan status, table, and ticket map are updated.
- [x] AppViewModel.swift line count is not larger (pass) — The file is 4992 lines in the parent and implementation commit.
Checks run:
- swift build: pass
- scripts/ci-tests.sh fast: pass (1902 tests, zero failures)
- scripts/ci-tests.sh serial: pass (560 tests, zero failures)
- swift test --no-parallel --filter ObservationInvalidationTests/(testSliderValueThroughputP95StaysWithinBudget|testNavigationP95StaysWithinBudget): pass; navigation p95 0.002 ms, slider p95 0.000 ms
- Stale ObservableObject/@Published/@ObservedObject/@StateObject search in docs and CLAUDE.md: only deliberate historical mentions in APP_VIEWMODEL_OBSERVATION_PLAN.md
- git diff --check f48b5218^ f48b5218: pass
- AppViewModel.swift line count in parent and implementation commit: 4992 and 4992
- Manual swift run smoke: blocked after two launches reported the default library was already being written by the current SwiftPM process; sample import was disabled; no photo imports or edits were made
Findings:
- blocker: The active-inspector row and zero-mirror criteria conflict with AppViewModel.document being one stored observable EditDocument property and with the no-section-copy criterion. Splitting rows or passing Bindings does not change the tracked root property. The acceptance contract must either accept per-document invalidation while keeping the shell at zero, or authorize a concrete section-granular state design and corresponding production probes.
- verification limitation: The manual edit/undo smoke could not proceed because both swift run launches failed to open the default package due to the writer lease. Repeat against a dedicated temporary library after the launch lock is resolved.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV83ML42KKF48WPM
Summary: Blocked: row and mirror invalidation criteria conflict with the single observable document property and no-section-copy requirement; the live smoke could not open the default library.

- 2026-10-14T13:44:23.313Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] On a real InfoInspectorView with a photo open and the Light tab selected, Light, Color, and Effects document mutations re-evaluate the shell 0 times. (pass) — testInspectorShellDoesNotReadDocumentWithAPhotoOpen passed for all three mutations.
- [x] The revised document-reader contract evaluates the Light, Color, Effects, and Preview read-set mirrors once per document mutation, while StatusBar and the Info shell evaluate zero times. (pass) — testDocumentMutationEvaluatesEachDocumentReaderOnce passed with the expected 1/0 counts; per-row and per-section isolation remains deferred under option A.
- [x] No stored EditDocument or section copy is added on the slider path, and slider throughput and navigation p95 tests pass. (pass) — Both named p95 tests passed: slider p95 0.000 ms and navigation p95 0.003 ms.
- [x] Slider, undo/redo, reset, and commit tests pass unchanged. (pass) — Fast and serial CI lanes passed with zero failures.
- [x] Documentation is updated and the stale Observation wrapper search only finds deliberate historical mentions in the plan. (pass) — Search results were confined to deliberate migration history in APP_VIEWMODEL_OBSERVATION_PLAN.md.
- [x] The plan is marked completed with the final before/after table, and the ticket map names KRMA-972 through KRMA-981 as done. (pass) — Confirmed in the plan and ticket map.
- [x] AppViewModel.swift line count is not larger. (pass) — The parent and implementation commit each contain 4,992 lines.
Checks run:
- swift build: pass (exit 0)
- scripts/ci-tests.sh fast: pass (1,908 tests, zero failures)
- scripts/ci-tests.sh serial: pass (561 tests, zero failures)
- swift test --no-parallel --filter 'ObservationInvalidationTests/(testSliderValueThroughputP95StaysWithinBudget|testNavigationP95StaysWithinBudget)': pass; slider p95 0.000 ms, navigation p95 0.003 ms
- git diff --check f48b5218^ f48b5218: pass
- Stale ObservableObject/@Published/@ObservedObject/@StateObject search in docs and CLAUDE.md: only deliberate historical mentions in APP_VIEWMODEL_OBSERVATION_PLAN.md
- AppViewModel.swift line counts in parent and implementation commit: 4,992 and 4,992
- Manual smoke in isolated temporary app/package: Light exposure changed to +0.52 EV and histogram reported 3,244 clipped highlights; Color Grading wheel changed to hue 31 degrees/saturation 31 percent, undo returned it to neutral, and redo restored the adjustment; Info/Light/Color/Effects tab navigation and metadata/histogram display worked.
- Temporary smoke app, package, and isolated preference domain were cleaned up; no smoke app process remains.
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV855EO3B2QTXS18
Summary: Pass: revised observation criteria, build/test/performance checks, documentation, and isolated manual edit/undo smoke all verified; no findings or verification fixes.
