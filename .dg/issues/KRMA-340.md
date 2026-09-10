---
id: KRMA-340
title: Audit and prune the entire docs tree
type: task
status: done
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - docs
  - maintenance
created: 2026-09-10T13:59:59.115Z
updated: 2026-09-10T15:08:05.031Z
order: a0
board: product
commits:
  - 7e42db7
---

## Objective

Perform a comprehensive audit of every file under `docs/` and reduce the documentation set to the smallest accurate, relevant, maintainable collection that supports the current Kromora project. Many documents may have originated upstream or describe superseded plans; do not preserve them merely because they exist.

## Scope

- Audit every file recursively under `docs/`, including `docs/superpowers/` plans and specs.
- Compare documentation against the current source tree, tests, package structure, shipped behavior, project goals, and DispatchGraph issue history.
- Review cross-references from the rest of the repository, including README files, contributor guidance, scripts, issue records, and configuration.
- Do not change product or implementation behavior as part of this ticket.

## Audit standard

For each document, make an explicit disposition:

- **Retain** only if it is accurate, materially useful today, and has a clear role as current project documentation.
- **Merge or rewrite** when multiple documents overlap, when a durable document can replace several fragments, or when only a small accurate subset remains useful.
- **Delete** when the document is obsolete, upstream-only, speculative without active project intent, superseded by implementation, duplicative, inaccurate, historical noise, or not useful to a current Kromora contributor.
- Favor deletion over archival for material that has no ongoing operational, design, or historical value. Do not create an archive folder as a way to avoid deciding.
- Treat historical evidence as retainable only when it explains an active compatibility constraint, records a decision that still governs implementation, or is required to understand a current supported workflow.
- Remove or rewrite upstream names, stale project assumptions, abandoned terminology, obsolete paths, and claims that cannot be verified.
- Ensure each retained document has one clear source of truth and does not restate volatile implementation details that will quickly drift.

## Acceptance criteria

- [ ] Every file currently under `docs/` is listed in an audit disposition recorded in the issue comment or an accompanying audit note.
- [ ] Obsolete, irrelevant, upstream-inherited, speculative, duplicate, and superseded documents are deleted or consolidated.
- [ ] Every retained document is accurate against the current code and tests, relevant to Kromora current goals, internally consistent, and written for current contributors.
- [ ] Plans and specs are clearly marked as current only when they represent active, approved work; otherwise they are removed or converted into concise durable documentation when justified.
- [ ] Historical reports and performance artifacts are retained only when they provide current value; otherwise remove them.
- [ ] Cross-references throughout the repository are updated after deletions or renames.
- [ ] No retained document links to missing files, obsolete paths, abandoned tools, or unsupported workflows.
- [ ] Documentation uses consistent current terminology for the product, architecture, workflows, and status of work.
- [ ] The final `docs/` tree is intentionally small and easy to navigate, with no catch-all or unexplained leftovers.
- [ ] Run `dg validate` and `git diff --check`; run relevant documentation or repository checks available in the project.
- [ ] The completion comment records the file-by-file disposition, the final retained documentation structure, checks run, and any explicitly accepted limitations.

## Suggested method

1. Inventory the complete tree, including file sizes, dates, headings, and apparent document type.
2. Group documents by purpose and identify duplicates, superseded versions, upstream material, and historical-only material.
3. Read the current architecture and implementation sources needed to verify each candidate retained claim. Use tests and issue records as supporting evidence, not as substitutes for current behavior.
4. Search the whole repository for references before deleting or renaming anything.
5. Apply the smallest coherent documentation set, then perform a second pass focused only on factual accuracy, links, terminology, and discoverability.
6. Leave a concise disposition record so future contributors know why removed material was not preserved.

## Notes

The bar is not to keep a complete project history. The desired result is a lean, accurate documentation set that helps someone understand and work on the current Kromora product without being misled by upstream history or abandoned plans.

### Comment — codex @ 2026-09-10T15:07:58.948Z

Completed KRMA-340 documentation audit and cleanup.

Final docs tree (5 files):
- docs/ENGINEERING_GUIDE.md — current architecture, render/resource boundaries, persistence, masking, and contributor invariants.
- docs/LOOKS.md — LUT format, Look save/derive behavior, starter assets, and storage.
- docs/PACKAGING.md — icon, bundle, signing, entitlements, and release workflow.
- docs/TESTING.md — required lanes, optional fixtures/benchmarks, profiling, and manual UI checks.
- docs/DOCUMENTATION_AUDIT.md — dated audit record and full disposition table.

File-by-file disposition:
- ARCHITECTURE_BOUNDARIES.md — merged into ENGINEERING_GUIDE.md; removed stale extraction framing.
- AUTO_ADJUSTMENT.md — merged into ENGINEERING_GUIDE.md; volatile heuristic detail was incomplete after content-aware Auto work.
- CANVAS_OBSERVATION_PERFORMANCE.md — merged into ENGINEERING_GUIDE.md; retained the durable ownership boundary, removed dated capture procedure.
- CODE_REVIEW.md — deleted; historical audit with superseded findings and no current operational role.
- COLOR_MODEL.md — deleted; volatile renderer/cache details duplicated by source and tests.
- EFFECTS_MODEL.md — deleted; volatile stage/version details had drifted.
- EFFECTS_VALIDATION.md — merged into TESTING.md.
- INSPECTOR_DISCLOSURES.md — merged into TESTING.md.
- INSTRUMENTS.md — merged into TESTING.md.
- KROMORA_ICON.md — merged into PACKAGING.md.
- LIGHT_MODEL.md — deleted; volatile model/cache detail duplicated by source and README.
- LUMO-108-RESOLUTION-PLANNING.md — deleted; completed issue plan with no active constraint.
- LUMO-113-SCHEDULING.md — merged into ENGINEERING_GUIDE.md; retained durable scheduling/resource principles.
- LUMO-118-DSC07826-20260901-201604-summary.md — deleted; dated hardware artifact.
- LUMO-121-DSC07826-20260901-222341-summary.md — deleted; dated hardware artifact.
- LUMO-123-DSC07826-20260902-124253-summary.md — deleted; historical capture report superseded by the wrapper.
- LUMO-217-MASK-OVERLAY-BASELINE-2026-09-04.md — deleted; prototype/baseline report superseded by shipped source/tests.
- LUMO-226-MASKING-HARDENING-REPORT-2026-09-05.md — deleted; completed dated hardening report.
- LUT_FORMAT.md — merged into LOOKS.md.
- MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md — deleted; planning-only and superseded by implemented masking.
- MASK_PERSISTENCE.md — merged into ENGINEERING_GUIDE.md.
- PERFORMANCE_AUDIT_2026-09-01.md — deleted; dated ticket-indexed audit.
- PERFORMANCE_CAPTURE_MATRIX_2026-09-01.md — deleted; historical matrix duplicated by TESTING.md.
- PHASE2_SPEC.md — rewritten as durable current contracts in ENGINEERING_GUIDE.md.
- PHASE3_SPEC.md — deleted; superseded issue plan with stale names/sequencing.
- PHOTOS_IMPORT_PERFORMANCE.md — merged into TESTING.md.
- PHOTO_INTELLIGENCE_TUNING_2026-09-04.md — deleted; dated tuning report.
- RENDER_MEMORY_BUDGET.md — merged into ENGINEERING_GUIDE.md.
- STARTER_LOOKS.md — merged into LOOKS.md.
- TEST_LIBRARY_CLEANUP.md — deleted; one-time fixture cleanup procedure.
- THEME_VALIDATION.md — merged into TESTING.md.
- docs/superpowers/plans/2026-08-06-step10a-raw-develop-inspector.md — deleted; completed upstream/one-off plan.
- docs/superpowers/plans/2026-08-06-step10b-adjustments-inspector.md — deleted; completed upstream/one-off plan.
- docs/superpowers/specs/2026-08-05-step9-derive-registry-design.md — deleted; historical design transcript superseded by implementation/tests.
- docs/superpowers/specs/2026-08-06-step10a-raw-develop-inspector-design.md — deleted; historical design transcript superseded by implementation/tests.
- docs/superpowers/specs/2026-08-06-step10b-adjustments-inspector-design.md — deleted; historical design transcript superseded by implementation/tests.

Updated README.md, CLAUDE.md, scripts/README.md, source/test comments, and DG issue references for renamed/removed docs. No product behavior changed.

Checks:
- dg validate — OK (pre-existing warnings: unknown pickup-runner model and low context completeness on KRMA-341)
- git diff --check — OK
- swift build — passed; existing Core Image kernel deprecation warnings only
- swift build -c release — passed
- swift test — 1,070 executed, 47 skipped, 0 failures
- repository-wide Markdown reference scan — all referenced Markdown paths exist

Accepted limitation: dated performance results and full planning provenance remain in git history and DG issue records, not in the current docs tree.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-10T15:08:05.029Z: Audited all 36 original docs files, consolidated durable guidance into five current documents, removed obsolete plans/reports, updated cross-references, and verified build/tests/docs paths.
