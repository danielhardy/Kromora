---
id: KRMA-378
title: Update all documentation to reflect current progress
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Every tracked documentation file inventoried and classified
      result: pass
      notes: docs/DOCUMENTATION_AUDIT.md carries a full current documentation map plus disposition table covering README, CLAUDE.md, BRANDING.md, docs/, scripts/README.md, realworldtest/README.md, .dg/ guidance, and .context/initial_concept.md.
    - criterion: User/developer docs accurately describe current product
      result: pass
      notes: "Spot-checked claims against source: PhotoAnalysisCoordinator (actor, Models/PhotoAnalysis/), ContentAwareAutoEngine, AutoEnhancementCoordinator, EditorDocumentCoordinator, PhotosImportCoordinator, ComparisonFramePolicy all exist as described; render stage order (orientation -> Light/Color -> ordered adjustments -> Look -> local adjustments -> crop -> vignette -> grain) matches RenderPipeline.swift; test count '1,338 XCTest methods' matches `swift test list`."
    - criterion: Roadmaps/plans/architecture/status reflect completed work and gaps
      result: pass
      notes: LIBRARY_PACKAGE_PLAN.md and initial_concept.md explicitly marked as future/superseded with pointers to current implementation; new APP_ARCHITECTURE.md documents current coordinator ownership boundaries.
    - criterion: Obsolete instructions/paths/claims removed or marked historical
      result: pass
      notes: .dg/README.md LUMO-001 -> KRMA-001 example fixed; initial_concept.md given a superseded-provenance banner; stale JSON-catalog/backup persistence description replaced with current SwiftData EditRecord description.
    - criterion: Internal links and referenced files valid
      result: pass
      notes: Re-scanned every .md-suffixed link in README.md, CLAUDE.md, and docs/*.md resolved relative to its own directory; all resolve to existing files. No broken links found.
    - criterion: Documentation validation and repository checks pass
      result: pass
      notes: "Re-ran independently: `dg validate` -> OK (only pre-existing unknown-model warnings for KRMA-341/KRMA-368, unrelated to this issue); `swift build` -> Build complete; `git diff --check` on the doc commit -> clean."
  checks_run:
    - dg validate
    - swift build
    - swift test list | wc -l (1338, matches README claim)
    - git diff --check 59657fc^ 59657fc
    - grep-based existence check for PhotoAnalysisCoordinator, ContentAwareAutoEngine, AutoEnhancementCoordinator, EditorDocumentCoordinator, PhotosImportCoordinator, ComparisonFramePolicy
    - grep-based render stage order cross-check against RenderPipeline.swift
    - custom relative-link resolution scan across README.md, CLAUDE.md, docs/*.md
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-12T19:07:16.531Z
  session: 01MTYR9SKVCQ9VB2DX
created: 2026-09-12T15:24:00.767Z
updated: 2026-09-12T19:07:16.533Z
order: a0
board: product
---

## Objective

Bring all project documentation up to date with the substantial product and implementation progress since the existing docs were written.

## Scope

- Inventory and review README files, project plans, architecture notes, decision records, feature documentation, and developer/agent guidance.
- Update documentation to reflect the current Library/Edit workflow, editing features, Auto/photo-analysis capabilities, rendering architecture, RAW support, and current project status.
- Remove or revise stale plans, claims, commands, screenshots, file paths, and implementation notes.
- Reconcile cross-references and links so the documentation presents one consistent current picture.

## Acceptance criteria

- [ ] Every tracked documentation file has been inventoried and classified as current, updated, superseded, or intentionally retained.
- [ ] User-facing and developer-facing documentation accurately describes the current product and supported workflows.
- [ ] Roadmaps, plans, architecture notes, and status references reflect completed work and remaining gaps.
- [ ] Obsolete instructions, paths, screenshots, and feature claims are removed or clearly marked historical.
- [ ] Internal links and referenced files are valid.
- [ ] Documentation validation and repository checks pass.

## Implementation notes

Start with the documentation tree, README/CLAUDE guidance, DG decisions, and recent completed issue records; use the current source and tests as the behavioral authority.

### Comment — codex @ 2026-09-12T19:05:43.702Z

Implemented and committed documentation reconciliation in 59657fc. Updated README/CLAUDE and durable guides to describe the current Library/Edit workflow, SwiftData edit records, culling/deletion, RAW/local masking, content-aware Auto/photo analysis, comparison, rendering stages, and coordinator ownership. Added APP_ARCHITECTURE.md, marked the portable library package as future KRMA-384 work, refreshed the documentation inventory/dispositions, corrected the DispatchGraph example from LUMO-001 to KRMA-001, and marked the initial concept as superseded provenance. Current-document relative-link scan passed. Checks: dg validate (pass; pre-existing unknown-model warnings only), scripts/ci-tests.sh verify (1,338 total; 922 fast, 370 serial, 46 optional), swift build (pass), swift test (1,338 executed, 49 skipped, 0 failures), git diff --check (pass). Pre-existing non-documentation worktree changes were preserved and not included.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-12T19:07:16.531Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Every tracked documentation file inventoried and classified (pass) — docs/DOCUMENTATION_AUDIT.md carries a full current documentation map plus disposition table covering README, CLAUDE.md, BRANDING.md, docs/, scripts/README.md, realworldtest/README.md, .dg/ guidance, and .context/initial_concept.md.
- [x] User/developer docs accurately describe current product (pass) — Spot-checked claims against source: PhotoAnalysisCoordinator (actor, Models/PhotoAnalysis/), ContentAwareAutoEngine, AutoEnhancementCoordinator, EditorDocumentCoordinator, PhotosImportCoordinator, ComparisonFramePolicy all exist as described; render stage order (orientation -> Light/Color -> ordered adjustments -> Look -> local adjustments -> crop -> vignette -> grain) matches RenderPipeline.swift; test count '1,338 XCTest methods' matches `swift test list`.
- [x] Roadmaps/plans/architecture/status reflect completed work and gaps (pass) — LIBRARY_PACKAGE_PLAN.md and initial_concept.md explicitly marked as future/superseded with pointers to current implementation; new APP_ARCHITECTURE.md documents current coordinator ownership boundaries.
- [x] Obsolete instructions/paths/claims removed or marked historical (pass) — .dg/README.md LUMO-001 -> KRMA-001 example fixed; initial_concept.md given a superseded-provenance banner; stale JSON-catalog/backup persistence description replaced with current SwiftData EditRecord description.
- [x] Internal links and referenced files valid (pass) — Re-scanned every .md-suffixed link in README.md, CLAUDE.md, and docs/*.md resolved relative to its own directory; all resolve to existing files. No broken links found.
- [x] Documentation validation and repository checks pass (pass) — Re-ran independently: `dg validate` -> OK (only pre-existing unknown-model warnings for KRMA-341/KRMA-368, unrelated to this issue); `swift build` -> Build complete; `git diff --check` on the doc commit -> clean.
Checks run:
- dg validate
- swift build
- swift test list | wc -l (1338, matches README claim)
- git diff --check 59657fc^ 59657fc
- grep-based existence check for PhotoAnalysisCoordinator, ContentAwareAutoEngine, AutoEnhancementCoordinator, EditorDocumentCoordinator, PhotosImportCoordinator, ComparisonFramePolicy
- grep-based render stage order cross-check against RenderPipeline.swift
- custom relative-link resolution scan across README.md, CLAUDE.md, docs/*.md
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTYR9SKVCQ9VB2DX
