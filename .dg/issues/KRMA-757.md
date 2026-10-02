---
id: KRMA-757
title: Measure Edit-panel and histogram timing for a warm photo switch (extend StoredEditAdoptionBenchmark)
type: task
status: ready
priority: high
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - performance
  - interaction
created: 2026-10-02T03:33:19.451Z
updated: 2026-10-02T03:34:19.256Z
blockers: []
order: a0
board: product
---

## Objective

Measure, without a window, how long a **warm photo switch** takes to give the Edit panel its stored values and the histogram. The current benchmark only measures a cold relaunch of one photo. A real filmstrip switch (photo A already open, then photo B) is the case users feel, and the two follow-up tickets (KRMA-758 neighbour warming, KRMA-759 histogram) need a baseline for it. This ticket changes **no product code**.

## Context

KRMA-755 added `StoredEditAdoptionBenchmark` (Tests/KromoraKitTests/StoredEditAdoptionBenchmark.swift, opt-in, no display). It reopens the package for every sample and selects the one photo, and reports when the panel got the stored exposure (`adopted`), when the source finished preparing (`prepared`), and when the photo settled (`ready`). Measured on DSC01019.ARW in Release on an M1 Pro: adopted p50 154 ms, prepared 292 ms, ready 703 ms. See docs/TESTING.md, "Edit-panel stored-edit adoption (KRMA-755)".

The histogram is computed by `PreviewAdmissionCoordinator.updateHistogram` (Sources/KromoraKit/ViewModels/PreviewAdmissionCoordinator.swift). It needs the inspector presented (`AppViewModel.isInspectorPresented`), a prepared `imageSource`, and a presented frame whose request matches the current document, so it cannot start before source preparation, and it is queued at `ImageWorkScheduler.Priority.histogram` (2), behind `activeEditor` (0) and `comparison` (1) work. The result is published to `AppViewModel.histogram`. Nothing measures when that happens.

## Work

1. In `StoredEditAdoptionBenchmark`, present the inspector (`viewModel.inspectorState.isPresented = true`) before selecting, and record `histogramMilliseconds`: the time from selection until `viewModel.histogram != nil` (use a different exposure per photo so a leftover histogram from the previous photo cannot satisfy it; see Notes).
2. Add a second scenario, `switch`, next to the existing `relaunch` one: copy the RAW to three file names (use `duplicatePolicy: .importAnyway`), give each a different stored exposure, open the first and wait until it is ready and its histogram is published, then select the second and measure `adopted`, `prepared`, `ready`, `histogram` from the moment of selection; repeat A to B to C to B so there are enough samples (the iteration env var already exists).
3. Print one `STORED_EDIT_ADOPTION` line per scenario with p50/p95 of every field plus `histogram_after_ready` (histogram minus ready, p50). Keep the existing output fields.
4. Record both scenarios, with the machine, OS, source, and sample count, in docs/TESTING.md under the existing KRMA-755 section.

## Notes

- A histogram from the previous photo stays visible on purpose while the next one loads (see the comment in `beginLoad`). To detect the *new* photo's histogram, compare against something that differs per photo (for example compare the `HistogramData` value to the one captured before selection, and require it to change) and say how you decided in a comment.
- Measure in Release, as the existing benchmark does: `KROMORA_STORED_EDIT_ADOPTION_BENCHMARK=1 KROMORA_STORED_EDIT_ADOPTION_ITERATIONS=10 swift test -c release --filter StoredEditAdoptionBenchmark`.

## Acceptance criteria

- [ ] The benchmark reports `histogramMilliseconds` and a `switch` scenario; the existing `relaunch` numbers are still printed.
- [ ] Both scenarios are recorded in docs/TESTING.md with machine, OS, source, and sample counts.
- [ ] `StoredEditAdoptionTests` and the fast lane still pass; no file under Sources/ is modified.
- [ ] A comment on this ticket states in two or three sentences what the numbers say: how long the histogram takes after ready, and whether the warm switch panel time is above or below the cold one.

## Rules for an unattended run (read first)

- **Do not run the display-bound captures** (`scripts/run-kromora-capture.sh`, the last-known-frame benchmark) and do not add them to this ticket. Everything here is verified by deterministic tests or by `StoredEditAdoptionBenchmark`, which needs no window and no unlocked display (see CLAUDE.md, "Display-bound benchmarks").
- **Do not open child tickets.** If a criterion cannot be met, or the numbers do not improve, record exactly what you measured and tried in a comment on this ticket, commit what is safe, and hand off to review. A measured miss with a profile is an acceptable outcome; a new ticket is not.
- Keep the change to what this ticket lists. Do not touch the slider animation (KRMA-756, in progress), the capture script, or the wall-clock budgets (ADR-LKF-001).
- Commit with a subject that starts `KRMA-<this id>:`. Do not push. Do not stash, reset, or revert anyone elses uncommitted changes in the tree.
- Gate before handoff: `swift test --filter` for the suites you touched, `scripts/ci-tests.sh warning-gate`, `scripts/ci-tests.sh fast`, `swift format lint` on changed Swift files, `git diff --check`, `dg validate`.
