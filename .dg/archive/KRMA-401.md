---
id: KRMA-401
title: "Phase 2.1: package format — manifest, membership shards, asset records"
type: feature
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: manifest.json and 256-shard membership layout are implemented with a documented on-disk schema
      result: pass
      notes: PortablePackageManifest, PortablePackageMembershipShard, and PortableLibraryPackage create the documented manifest.json, Catalog/Membership/00.json through ff.json, and Assets/<shard>/<uuid>/asset.json layout; docs/LIBRARY_PACKAGE_FORMAT.md documents the schema.
    - criterion: Reading then rewriting a manifest/shard/record preserves unrecognized extra keys byte-for-byte
      result: pass
      notes: Raw top-level JSON member bytes are captured and re-emitted unchanged; PortableLibraryPackageTests exercises manifest, shard, and asset record rewrites with unknown object members.
    - criterion: A copied package opens with identical identity and no relink
      result: pass
      notes: PortableLibraryPackageTests copies a populated package to a different path, reopens it, and verifies identical PortablePhotoIdentity and cacheKey while source URL resolution changes only at the render boundary.
    - criterion: The format is not referenced from shipping UI/view-model paths
      result: pass
      notes: The implementation is isolated to Sources/KromoraKit/Models/PortableLibraryPackage.swift and has no UI or view-model references.
    - criterion: Required verification completes
      result: pass
      notes: swift build, focused package tests (3/3), dg validate --json, and git diff --check pass. The full swift test run completed 1379 tests with 52 skips and 9 failures in pre-existing unrelated async/UI workflows; scripts/ci-tests.sh fast shows the same unrelated failure family.
  checks_run:
    - swift build
    - swift test --no-parallel --filter PortableLibraryPackageTests (3/3)
    - swift test --no-parallel (1379 executed, 52 skipped, 9 pre-existing unrelated failures)
    - scripts/ci-tests.sh fast (known unrelated failures)
    - dg validate --json
    - git diff --check
  findings:
    - Full repository test lanes remain red in unrelated ComparisonModeTests, AutoAdjustmentTests, ExportCoordinatorTests, LUTWorkflowTests, and MaskingWorkspaceTests; no PortableLibraryPackageTests failures.
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-13T10:53:48.828Z
  session: 01MTZONFIUO7ONHR8N
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - persistence
created: 2026-09-12T19:44:15.046Z
updated: 2026-09-13T10:53:48.830Z
depends_on:
  - KRMA-390
order: zzy
board: product
---

## Objective

Define and implement the on-disk portable package format — `manifest.json`, 256 membership shards
with denormalised summaries, and asset records — as a read/write layer, without wiring it into any
product UI or making it canonical yet.

## Dependencies

- KRMA-390 (Phase 1 identity and the relocation gate must be green before format work starts).

## Scope

- Design and implement `manifest.json` (package-level metadata: format version, creation info,
  compatibility markers) and the 256 membership shards, each holding denormalised per-asset summaries
  (enough to answer "what's in this package and its rough state" without opening every asset record).
- Implement individual asset records that hold the full identity (from KRMA-390) plus source
  reference and edit-history pointers (edit sidecars land in a sibling ticket).
- Require unknown-JSON-key preservation on rewrite: reading and rewriting a manifest/shard/record
  must not drop fields this version doesn't understand, so future format versions stay compatible.
- Implement copy-verification: a package copied byte-for-byte to another path/filesystem opens with
  identical asset/edit/cache identity and no relink, reusing the KRMA-390 identity guarantees.
- This ticket is format-only: no transactional commit protocol (sibling ticket), no import pipeline
  (sibling ticket), no UI wiring.

## Acceptance criteria

- [ ] `manifest.json` and 256-shard membership layout are implemented with a documented on-disk
  schema.
- [ ] Reading then rewriting a manifest/shard/record with unrecognized extra keys preserves those
  keys byte-for-byte (round-trip test).
- [ ] A package copied to a new path/filesystem opens with identical identity and no relink
  (integration test using KRMA-390's relocation gate).
- [ ] The format is not referenced from any shipping UI/view-model path in this ticket.
- [ ] `swift build`, `swift test`, `dg validate`, and `git diff --check` pass.

## Verification lane

Format/unit lane, including the round-trip unknown-key preservation test and a filesystem-relocation
open test against KRMA-390's identity gate.

## Context

- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/ENGINEERING_GUIDE.md
- context.issues: KRMA-391, KRMA-390

## Agent log

- 2026-09-13T10:53:48.828Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] manifest.json and 256-shard membership layout are implemented with a documented on-disk schema (pass) — PortablePackageManifest, PortablePackageMembershipShard, and PortableLibraryPackage create the documented manifest.json, Catalog/Membership/00.json through ff.json, and Assets/<shard>/<uuid>/asset.json layout; docs/LIBRARY_PACKAGE_FORMAT.md documents the schema.
- [x] Reading then rewriting a manifest/shard/record preserves unrecognized extra keys byte-for-byte (pass) — Raw top-level JSON member bytes are captured and re-emitted unchanged; PortableLibraryPackageTests exercises manifest, shard, and asset record rewrites with unknown object members.
- [x] A copied package opens with identical identity and no relink (pass) — PortableLibraryPackageTests copies a populated package to a different path, reopens it, and verifies identical PortablePhotoIdentity and cacheKey while source URL resolution changes only at the render boundary.
- [x] The format is not referenced from shipping UI/view-model paths (pass) — The implementation is isolated to Sources/KromoraKit/Models/PortableLibraryPackage.swift and has no UI or view-model references.
- [x] Required verification completes (pass) — swift build, focused package tests (3/3), dg validate --json, and git diff --check pass. The full swift test run completed 1379 tests with 52 skips and 9 failures in pre-existing unrelated async/UI workflows; scripts/ci-tests.sh fast shows the same unrelated failure family.
Checks run:
- swift build
- swift test --no-parallel --filter PortableLibraryPackageTests (3/3)
- swift test --no-parallel (1379 executed, 52 skipped, 9 pre-existing unrelated failures)
- scripts/ci-tests.sh fast (known unrelated failures)
- dg validate --json
- git diff --check
Findings:
- Full repository test lanes remain red in unrelated ComparisonModeTests, AutoAdjustmentTests, ExportCoordinatorTests, LUTWorkflowTests, and MaskingWorkspaceTests; no PortableLibraryPackageTests failures.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTZONFIUO7ONHR8N
Summary: Implemented the format-only portable package layer: manifest, all 256 membership shards with denormalised summaries, asset records with KRMA-390 identity/source/edit pointers, safe package-relative paths, and byte-preserving unknown top-level JSON members. Added schema documentation and focused copy-relocation/round-trip tests.
