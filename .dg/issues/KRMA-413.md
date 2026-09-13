---
id: KRMA-413
title: "Phase 4.3: explicit validation/scrub — critical vs. rebuildable classification"
type: feature
status: ready
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - backup
  - recovery
created: 2026-09-12T19:44:25.610Z
updated: 2026-09-13T04:44:02.251Z
depends_on:
  - KRMA-392
  - KRMA-391
order: zzzzzh
board: product
---

## Objective

Implement explicit library validation/scrubbing that separates missing/corrupt critical data
(manifest, shards, asset records, edit sidecars) from rebuildable data (thumbnails, previews, local
index, masks, analysis results) — the check both backup and restore rely on.

## Dependencies

- KRMA-392 (index/projection ownership must be stable so validation can tell "critical" from
  "rebuildable" correctly).
- KRMA-391 (checksums and format are required to validate against).

## Scope

- Implement a validation/scrub pass over a package that walks manifest, shards, asset records, and
  edit sidecars, verifying checksums and structural integrity, and separately walks `Derived/`
  (thumbnails, previews), the local index, masks, and analysis results.
- Report results in two explicit buckets: critical failures (data loss risk — manifest/shard/record/
  sidecar corruption or missing) and rebuildable gaps (missing/stale thumbnails, previews, index,
  masks, analysis — never treated as data loss).
- This validation report is the sibling backup/restore tickets' dependency for "verify every
  canonical component" and "validates completely" — expose it as a reusable API, not just a UI
  action.
- Do not perform any destructive action as part of validation itself (no auto-deletion, no
  auto-rebuild) — reporting only; remediation is explicit user/maintenance action (sibling tickets).

## Acceptance criteria

- [ ] Validation walks all canonical components and all rebuildable components and produces a report
  with two distinct buckets (critical vs rebuildable).
- [ ] A corrupted asset record or edit sidecar is reported as critical; a missing thumbnail or stale
  index is reported as rebuildable, never as critical.
- [ ] The validation API is reusable by backup and restore (not UI-only).
- [ ] Running validation performs no destructive or mutating action on the package.
- [ ] `swift build`, `swift test`, `dg validate`, and `git diff --check` pass.

## Verification lane

Validation/unit lane with injected corruption at each canonical and rebuildable component type,
asserting correct bucket classification.

## Context

- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/ENGINEERING_GUIDE.md
- context.issues: KRMA-393, KRMA-392, KRMA-391
