---
id: KRMA-527
title: Separate diagnostics and evaluation code from the shipping Auto path
type: task
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - architecture
  - diagnostics
created: 2026-09-21T20:33:07.860Z
updated: 2026-09-21T23:41:32.938Z
estimate: 8
order: zy
board: product
---

## Objective

Remove test/evaluation harness code and scattered statistics-only hooks from the shipping application target while keeping scripts, tests, and runtime diagnostics usable.

## Context and evidence

The production module currently includes AutoCandidateEvaluator, preview/export parity reporting, artifact writing, AutoEvaluatedRender/AutoEvaluationReport, VisionAesthetics diagnostics, LiveEditTelemetry, and many ForTesting counters. Much of this has zero production callers and exists only for tests or scripts. File-writing evaluation code in the app binary increases surface area and couples the Auto path to test infrastructure.

Some value types, such as AutoCandidateEvaluation used by CurrentEditMeasurement, may remain in KromoraKit. The split must distinguish shared runtime values from harness/reporting behavior.

## Scope

- Move test-only evaluators/reports/artifact writers into KromoraKitTests or a small internal KromoraDiagnostics target.
- Preserve script entry points such as photo-intelligence reports, updating imports/target dependencies as needed.
- Group runtime counters behind one RenderDiagnostics snapshot API rather than scattered properties and ForTesting hooks.
- Keep only value types genuinely needed by shipping code in KromoraKit.
- Update PackageSettingsTests and Swift 6 settings if a new target is introduced; do not add unsafe opt-outs.

## Acceptance criteria

- [ ] No file-writing evaluation harness code ships in the app binary.
- [ ] Existing diagnostics/evaluation scripts and tests run with the new target/module layout.
- [ ] Runtime code has a coherent diagnostics snapshot boundary; test-only counters are not individually exposed.
- [ ] New target, if any, follows Swift 6 settings and package/resource conventions.
- [ ] Fast, serial, auto-quality, and photo-intelligence checks pass.

## Dependencies and coordination

Independent of the library chain. CQ-13 depends on the resulting Auto/runtime boundary. Do not move shared value types needed by production.

## Likely files and checks

AutoCandidateEvaluation.swift, AutoPerformanceDiagnostics.swift, LiveEditTelemetry.swift, RenderEngine/PreviewSurface/PortablePackageMaintenance/MaskStore ForTesting hooks, Package.swift, scripts/photo-intelligence-derive.swift, and relevant tests.
