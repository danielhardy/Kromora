---
id: KRMA-981
title: "Observation step 10: Narrow document readers and close out docs"
type: task
status: backlog
priority: medium
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - swiftui
created: 2026-10-13T19:37:04.033Z
updated: 2026-10-13T19:37:04.972Z
depends_on:
  - KRMA-980
blockers: []
order: zzzzzx
board: product
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

- [ ] Probe test (KRMA-972 helpers): on a real `InfoInspectorView` with the Light tab selected, a Light-slider mutation does **not** increment the shell's own body count beyond the baseline expected for the histogram it displays (state the expected number in the test), the Light inspector re-evaluates only the affected row plus summary readers, and PreviewView re-evaluates. Add the equivalent rows for a Color mutation and an Effects mutation.
- [ ] Mirror rows for Color/Effects/Look/Info stay at 0 re-evaluations on a Light mutation (read-set check, labelled mirror).
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
