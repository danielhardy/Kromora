# Documentation map and audit — 2026-09-28

This audit establishes the current reading order after KRMA-669. Product intent has one home in
[`PRODUCT_SCOPE.md`](PRODUCT_SCOPE.md). The [README](../README.md) is the concise description of
the running product; feature and engineering guides own their detailed contracts. Historical plans,
dated evaluations, and proposal archives remain available with their provenance and do not define
the active MVP or roadmap.

## Current product and technical guidance

| Document | Classification | Role |
| --- | --- | --- |
| [`README.md`](../README.md) | Current product overview | Audience, workflow, current features and limits, build/run, architecture summary. |
| [`PRODUCT_SCOPE.md`](PRODUCT_SCOPE.md) | Current product intent | MVP audience, core loop, release bar, current scope, post-MVP boundaries. |
| [`APP_ARCHITECTURE.md`](APP_ARCHITECTURE.md) | Current architecture | Workflow ownership, coordinators, package-library boundary. |
| [`ENGINEERING_GUIDE.md`](ENGINEERING_GUIDE.md) | Current engineering contract | Render, concurrency, persistence, masking, UI and contributor invariants. |
| [`MODEL_ARCHITECTURE.md`](MODEL_ARCHITECTURE.md) | Current architecture reference | Module direction and model/source boundaries. |
| [`STORAGE_POLICY.md`](STORAGE_POLICY.md) | Current data-safety contract | Canonical package data, projections, caches, backup, restore, and output. |
| [`TESTING.md`](TESTING.md) | Current operations | Required and optional verification lanes, profiling, manual UI checks. |
| [`PACKAGING.md`](PACKAGING.md) | Current operations | App bundle, identity, sandbox, signing, and release workflow. |
| [`ONBOARDING.md`](ONBOARDING.md) | Current feature guide | First-run choices, sample photos, tour, guided editing. |
| [`AUTO_EXPOSURE_POLICY.md`](AUTO_EXPOSURE_POLICY.md) | Current feature contract | Renderer-backed Auto decisions and quality guardrails. |
| [`AUTO_PERFORMANCE.md`](AUTO_PERFORMANCE.md) | Dated diagnostic evidence | Auto measurement method and machine-specific baseline, not a speed promise. |
| [`COMPARISON_MODE.md`](COMPARISON_MODE.md) | Current interaction decision | Single and side-by-side comparison behavior. |
| [`LOOKS.md`](LOOKS.md) | Current feature guide | `.cube` Looks, bundled assets, import, derive, save, licensing. |
| [`RETOUCH.md`](RETOUCH.md) | Current feature guide and dated quality evidence | Recipe/render behavior, dust suggestions, limitations, fixture results. |
| [`INTEROP_EXPORT.md`](INTEROP_EXPORT.md) | Current feature guide | Rendered-file external-editor handoff and interoperability output. |
| [`LIBRARY_PACKAGE_FORMAT.md`](LIBRARY_PACKAGE_FORMAT.md) | Format reference | Portable package record and compatibility format; runtime behavior is governed by storage and architecture guides. |
| [`BRANDING.md`](../BRANDING.md) | Current identity policy | Branding, attribution, and redistribution. |
| [`scripts/README.md`](../scripts/README.md) | Current operations | Script entry points and prerequisites. |
| [`realworldtest/README.md`](../realworldtest/README.md) | Current fixture policy | Licensed local camera-file policy and real-world checks. |
| [`CLAUDE.md`](../CLAUDE.md), [`AGENTS.md`](../AGENTS.md) | Current contributor guidance | Build, code, repository, and agent workflow rules. |
| [`.dg/AGENTS.md`](../.dg/AGENTS.md), [`.dg/README.md`](../.dg/README.md) | Current workflow guidance | DispatchGraph lifecycle and issue operations. |

## Historical records and dated evidence

| Document | Classification | Disposition |
| --- | --- | --- |
| [`LIBRARY_PACKAGE_PLAN.md`](LIBRARY_PACKAGE_PLAN.md) | Historical implementation plan and design rationale | The package library shipped. Retained for format/migration provenance; the completed phase sequence is not an execution queue. Current contracts are in APP_ARCHITECTURE and STORAGE_POLICY. |
| [`LIBRARY_PACKAGE_BASELINE.md`](LIBRARY_PACKAGE_BASELINE.md) | Frozen pre-package baseline | Retained to explain historical measurements. It describes a folder-backed implementation that is no longer the product. |
| [`LIBRARY_SCALE_REGRESSION.md`](LIBRARY_SCALE_REGRESSION.md) | Dated regression evidence | Retained as benchmark provenance. Values describe named fixtures, machines, and methods. |
| [`EDIT_STORE_IDENTITY_DISPOSITION.md`](EDIT_STORE_IDENTITY_DISPOSITION.md) | Superseded migration record | Retained to explain old standalone stores; current authority is STORAGE_POLICY. |
| [`REPOSITORY_IMPROVEMENT_PLAN.md`](REPOSITORY_IMPROVEMENT_PLAN.md) | Superseded review and execution plan | Retained as dated findings/provenance. Its ordering and acceptance text are not the live backlog. Re-triage through current issues. |

## Project context and deferred ideas

| Path | Classification | Disposition |
| --- | --- | --- |
| [`.context/initial_concept.md`](../.context/initial_concept.md) | Historical project provenance | Its pre-fork feature brief, milestone sequence, exclusions, and commands are superseded. Use PRODUCT_SCOPE and current guides. |
| [`.context/2026-09-22-professional-polish-evaluation.md`](../.context/2026-09-22-professional-polish-evaluation.md) | Deferred idea archive | Preserves competitor-gap analysis and removed proposal specifications. Proposals may be reconsidered through future product decisions; none is an MVP commitment or active roadmap. |
| [`.context/2026-09-25-stability-performance-review.md`](../.context/2026-09-25-stability-performance-review.md) | Dated review evidence | Findings are tied to its recorded checkout and environment. Later implementation may have changed them; consult current code, tests, and issue status before acting. |
| [`.context/2026-09-27-heal-remove-plan.md`](../.context/2026-09-27-heal-remove-plan.md) | Historical feature implementation plan | Retained for decisions and provenance. Retouch is now described by RETOUCH.md and current source/tests; planned phases are not an open implementation queue. |
| [`.context/CODE_QUALITY_CLEANUP_PLAN.md`](../.context/CODE_QUALITY_CLEANUP_PLAN.md) | Superseded cleanup proposal | Its issue-sized proposals are historical analysis, not current backlog. Re-triage from current code before scheduling. |
| [`.context/review-evidence-2026-09-25/ReviewProbes.swift`](../.context/review-evidence-2026-09-25/ReviewProbes.swift) | Dated review artifact | Probe source for the 2026-09-25 review, not production or a supported verification command. |
| [`.dg/decisions/`](../.dg/decisions/) | Accepted decision history | Decision records explain choices; implementation and current guides define present behavior. |
| [`.dg/issues/`](../.dg/issues/) | Canonical issue history | Lifecycle and implementation records, not user-facing product documentation. |

## Consolidation and retention

Earlier audits consolidated volatile or duplicate implementation notes into the current engineering,
testing, and Look guides; those merges and deletions are recorded in git history and in the prior
audit. KRMA-669 adds a product-intent document and replaces the README's long feature-by-feature
implementation inventory with a workflow overview, verified capability summary, and explicit
limits. No source guide or deferred proposal archive was removed.

The package plan, pre-package benchmark, package-scale evidence, review plans, and proposal archive
remain separate because they preserve migration decisions, reproducibility details, or ideas that
may be reconsidered. They are labeled here so historical detail cannot be mistaken for current
behavior or a commitment. Update this map when a document is added, retired, or changes role.
