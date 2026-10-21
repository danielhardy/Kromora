# Documentation map

This map lists every file under `docs/` and every retained `.context/` file with one role each.
When two sources disagree, current behavior is defined by the source tree and tests first, then by
the guides marked current below. The [README](../README.md) is the concise description of the
running product and carries the audience, workflow, capabilities, and limits; each guide owns the
detailed contract named in its role. [`CLAUDE.md`](../CLAUDE.md) owns build, toolchain, and
contributor constraints. Historical files say so in their first paragraph and never define current
behavior or a roadmap.

## Current guides

| Document | Role |
| --- | --- |
| [`README.md`](../README.md) | Audience, workflow, capabilities, limits, build/run, architecture summary. |
| [`CLAUDE.md`](../CLAUDE.md), [`AGENTS.md`](../AGENTS.md) | Build, toolchain, code, repository, and agent workflow rules. |
| [`DOCUMENTATION_AUDIT.md`](DOCUMENTATION_AUDIT.md) | Inventory of documentation roles and the retention rule. |
| [`BRANDING.md`](../BRANDING.md) | Branding, attribution, and redistribution. |
| [`scripts/README.md`](../scripts/README.md) | Script entry points and prerequisites. |
| [`realworldtest/README.md`](../realworldtest/README.md) | Local-only camera-file policy and real-world checks. |
| [`.dg/AGENTS.md`](../.dg/AGENTS.md), [`.dg/README.md`](../.dg/README.md) | DispatchGraph lifecycle and issue operations. |
| [`APP_ARCHITECTURE.md`](APP_ARCHITECTURE.md) | Workflow ownership, coordinators, package-library boundary. |
| [`MODEL_ARCHITECTURE.md`](MODEL_ARCHITECTURE.md) | Module direction and model/source boundaries. |
| [`ENGINEERING_GUIDE.md`](ENGINEERING_GUIDE.md) | Render, concurrency, persistence, masking, UI, and contributor invariants. |
| [`STORAGE_POLICY.md`](STORAGE_POLICY.md) | Package ownership, canonical data, projections, caches, quit-and-copy, dormant backup/restore. |
| [`EDITOR_SESSION_RETENTION.md`](EDITOR_SESSION_RETENTION.md) | Resident edit-session budget (32 sessions, 192 MiB), pinning, eviction, and undo contract. |
| [`KEYBOARD_QA_CHECKLIST.md`](KEYBOARD_QA_CHECKLIST.md) | Expected result of every shortcut per focus state; a test keeps it in agreement with the shortcut catalog. |
| [`TESTING.md`](TESTING.md) | Release bar, `fast` / `serial` / `optional` lanes, profiling, manual UI checks, dated measurement records. |
| [`PACKAGING.md`](PACKAGING.md) | App bundle, identity, sandbox, signing, and release workflow. |
| [`APP_STORE_SUBMISSION.md`](APP_STORE_SUBMISSION.md) | App Store Connect submission checklist, privacy, and review notes. |
| [`APP_STORE_ACCEPTANCE.md`](APP_STORE_ACCEPTANCE.md) | App Store acceptance criteria and verification record. |
| [`ONBOARDING.md`](ONBOARDING.md) | First-run choices, sample photos, tour, guided editing. |
| [`AUTO_EXPOSURE_POLICY.md`](AUTO_EXPOSURE_POLICY.md) | Renderer-backed Auto decisions and quality guardrails. |
| [`COMPARISON_MODE.md`](COMPARISON_MODE.md) | Single and side-by-side comparison behavior. |
| [`LOOKS.md`](LOOKS.md) | `.cube` Looks, bundled assets, import, derive, save, licensing. |
| [`RETOUCH.md`](RETOUCH.md) | Retouch recipe and render behavior, dust suggestions, limits, fixture results. |
| [`INTEROP_EXPORT.md`](INTEROP_EXPORT.md) | Rendered-file external-editor handoff. |
| [`LIBRARY_PACKAGE_FORMAT.md`](LIBRARY_PACKAGE_FORMAT.md) | Portable package record and compatibility format. |

## Historical records and dated evidence

| Document | Role |
| --- | --- |
| [`LIBRARY_PACKAGE_PLAN.md`](LIBRARY_PACKAGE_PLAN.md) | Completed package-library design and migration rationale; not an execution queue. |
| [`LIBRARY_PACKAGE_BASELINE.md`](LIBRARY_PACKAGE_BASELINE.md) | Frozen pre-package, folder-backed measurements. |
| [`LIBRARY_SCALE_REGRESSION.md`](LIBRARY_SCALE_REGRESSION.md) | Library-scale benchmark method and results for named fixtures and machines. |
| [`evidence/library-scale-krma-829.json`](evidence/library-scale-krma-829.json) | Raw benchmark sample behind `LIBRARY_SCALE_REGRESSION.md`. |
| [`evidence/library-scale-krma-829-verification.json`](evidence/library-scale-krma-829-verification.json) | Verification sample behind `LIBRARY_SCALE_REGRESSION.md`. |
| [`evidence/library-scale-krma-831.json`](evidence/library-scale-krma-831.json) | Raw benchmark sample behind `LIBRARY_SCALE_REGRESSION.md`. |
| [`AUTO_PERFORMANCE.md`](AUTO_PERFORMANCE.md) | Auto measurement method and a dated machine-specific baseline, not a speed promise. |
| [`APP_STORE_SANDBOX_AUDIT.md`](APP_STORE_SANDBOX_AUDIT.md) | Sandbox entitlement and file-access review of an earlier checkout; re-verify line references before relying on them. |
| [`EDIT_STORE_IDENTITY_DISPOSITION.md`](EDIT_STORE_IDENTITY_DISPOSITION.md) | Superseded record of the old standalone edit stores; `STORAGE_POLICY.md` is current. |
| [`.context/2026-10-19-release-readiness-review.md`](../.context/2026-10-19-release-readiness-review.md) | Dated release-readiness review; findings became DispatchGraph issues. |
| [`.context/2026-10-20-KRMA-1063-retouch-qualification.md`](../.context/2026-10-20-KRMA-1063-retouch-qualification.md) | Execution record of the camera-scale retouch qualification; cited by `RETOUCH.md`. |
| [`.context/initial_concept.md`](../.context/initial_concept.md) | Pre-fork project brief, kept as provenance. |
| [`.dg/decisions/`](../.dg/decisions/), [`.dg/issues/`](../.dg/issues/) | Decision records and canonical issue history. |

## Deferred ideas

| Document | Role |
| --- | --- |
| [`.context/2026-10-03-icloud-sync-plan.md`](../.context/2026-10-03-icloud-sync-plan.md) | iCloud library sync proposal. Sync is a product limit today; `STORAGE_POLICY.md` stays authoritative until a phase ships. |

## Retention

Superseded plans, one-off reviews, run records, and scratch artifacts are deleted rather than
archived; git history preserves them. A document stays only if a current guide, test, or evidence
file depends on it, or if it preserves a decision or idea set that may be reconsidered. A completed
migration plan is removed once the guide that owns the resulting contract states it. Update this
map when a document is added, removed, or changes role.
