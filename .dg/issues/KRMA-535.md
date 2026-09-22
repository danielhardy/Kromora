---
id: KRMA-535
title: Reconcile documentation with the package-backed product
type: task
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - documentation
  - architecture
created: 2026-09-21T20:33:14.597Z
updated: 2026-09-21T20:33:32.137Z
depends_on:
  - KRMA-519
  - KRMA-520
  - KRMA-531
estimate: 3
order: zzzzh
board: product
---

## Objective

Make repository guidance accurately describe the package-backed product, record which older improvement-plan items are complete or superseded, and document the measured production path.

## Context and evidence

CLAUDE.md still says the current product is folder-backed and portable library is future. DOCUMENTATION_AUDIT.md and LIBRARY_PACKAGE_PLAN.md repeat that outdated model. REPOSITORY_IMPROVEMENT_PLAN.md does not distinguish done/open/moot work. LIBRARY_SCALE_REGRESSION.md does not disclose that the production UI path is not measured. ENGINEERING_GUIDE.md still describes the standalone v2 persistence store.

## Scope

- Update CLAUDE.md and DOCUMENTATION_AUDIT.md to describe package-backed storage and current compatibility boundaries.
- Update LIBRARY_PACKAGE_PLAN.md and STORAGE_POLICY.md where the package is now the product source of truth.
- Point REPOSITORY_IMPROVEMENT_PLAN.md to CODE_QUALITY_CLEANUP_PLAN.md for remaining work, or retire/supersede it explicitly with status mapping.
- Update LIBRARY_SCALE_REGRESSION.md with the production-path benchmark and limitations from CQ-04.
- Update ENGINEERING_GUIDE.md persistence sections after CQ-16 to describe the package-backed cache and sidecars.
- Document decisions and migration boundaries from CQ-05, CQ-16, and any retained legacy files; do not claim behavior that tests/benchmarks do not verify.

## Acceptance criteria

- [ ] No current guidance claims the product is folder-backed or that package storage is merely future.
- [ ] Improvement-plan status clearly identifies done, open, superseded, and linked CQ tickets.
- [ ] Scale documentation distinguishes production UI measurements from helper/fixture measurements.
- [ ] Persistence and storage docs match the implemented package-backed source of truth.
- [ ] Links, headings, and examples are valid; documentation audit/relevant validation checks pass.

## Dependencies and coordination

Land the behavior-specific updates with CQ-04, CQ-05, and CQ-16 where practical; this final reconciliation depends on those tickets' decisions. Keep repo-meta-only changes small and avoid rewriting historical records.

## Likely files and checks

CLAUDE.md, docs/DOCUMENTATION_AUDIT.md, docs/LIBRARY_PACKAGE_PLAN.md, docs/REPOSITORY_IMPROVEMENT_PLAN.md, docs/LIBRARY_SCALE_REGRESSION.md, docs/ENGINEERING_GUIDE.md, docs/STORAGE_POLICY.md, and documentation validation.
