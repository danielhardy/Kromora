---
id: KRMA-532
title: Reach a zero-warning build and enforce the warning budget
type: task
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - hygiene
  - ci
created: 2026-09-21T20:33:12.132Z
updated: 2026-09-21T20:33:30.808Z
depends_on:
  - KRMA-524
  - KRMA-517
estimate: 5
order: zzzx
board: product
---

## Objective

Remove the 35 unique warnings observed by the cleanup audit, fix tests that currently drop meaningful persistence results, and make CI fail on newly introduced warnings.

## Context and evidence

swift build --build-tests at d6e4977 emitted nine CIKL deprecation warnings, Swift 6 actor-isolation warnings in CropTests, twelve unused flushPendingWrites results, five deprecated PhotosImportCoordinator initializer uses, and two trivial unused-variable/mutability warnings. CLAUDE.md claims zero diagnostics, but no machine-enforced gate currently protects that claim.

## Scope

- Remove the nine CIKL warnings through CQ-09 or its equivalent.
- Mark crop tests @MainActor or otherwise correct isolation without unsafe opt-outs.
- Replace dropped flushPendingWrites results with assertions such as XCTAssertEqual(await flushPendingWrites(), .success), so tests verify the persistence outcome they intend to cover.
- Remove deprecated PhotosImportCoordinator initializer use after CQ-02 or update remaining tests.
- Fix trivial SceneEvidenceTests and GlobalToneAnalyzerTests warnings.
- Add a CI gate in scripts/ci-tests.sh or a CI-only build configuration that fails on any warning in Sources or Tests; ensure it is robust to expected toolchain noise and documented.

## Acceptance criteria

- [ ] Clean build log has zero warnings for Sources and Tests on the supported toolchain.
- [ ] Persistence tests assert flush outcomes instead of ignoring them.
- [ ] The CI gate fails on a deliberately introduced warning in a fixture/probe and passes on the clean tree.
- [ ] No unsafe Swift 6 opt-out is added to hide a warning.
- [ ] Fast, serial, package settings, and warning-gate checks pass.

## Dependencies and coordination

Depends on CQ-09 for shader warnings and should coordinate with CQ-02 for deprecated import shims. Do not wait for every architecture ticket; unrelated warnings should be fixed here.

## Likely files and checks

Package.swift/build scripts, scripts/ci-tests.sh, CropTests.swift, EditPersistenceIntegrationTests, LUTWorkflowTests, SceneEvidenceTests, GlobalToneAnalyzerTests, PhotosImportTests, and CI documentation.
