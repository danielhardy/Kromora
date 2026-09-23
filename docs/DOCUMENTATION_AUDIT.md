# Documentation audit — 2026-09-12

KRMA-340 first reduced the original `docs/` tree to a small durable set. KRMA-378 re-audited that
set; this update reconciles it with the package-backed product and the decisions in KRMA-517,
KRMA-519, KRMA-520, and KRMA-531. The current product uses a portable library package as the
authoritative owner of library membership, originals, metadata, and edit revisions. Folder, Photos,
and removable-volume selection are import sources. The local query index and device caches are
rebuildable projections. Existing standalone edit-store files are left untouched and are not opened
as a fallback. See [APP_ARCHITECTURE.md](APP_ARCHITECTURE.md),
[STORAGE_POLICY.md](STORAGE_POLICY.md), and [EDIT_STORE_IDENTITY_DISPOSITION.md](EDIT_STORE_IDENTITY_DISPOSITION.md).

## Current documentation map

| Path or scope | Classification | Current role |
| --- | --- | --- |
| `README.md` | Current, updated | User-facing product workflow, supported features, setup, architecture summary, and remaining roadmap. |
| `CLAUDE.md` | Current, updated | Agent/build/concurrency guidance and links to current architecture docs. |
| `BRANDING.md` | Current, retained | Kromora identity and fork/redistribution policy. |
| `docs/APP_ARCHITECTURE.md` | Current, retained | Application ownership and coordinator boundaries from KRMA-382. |
| `docs/ENGINEERING_GUIDE.md` | Current, updated | Durable render, persistence, masking, Auto, slider, and contributor invariants. |
| `docs/AUTO_EXPOSURE_POLICY.md` | Current, updated | Shipped content-aware Auto behavior and quality guardrails. |
| `docs/AUTO_PERFORMANCE.md` | Current, updated | Diagnostic contract plus explicitly dated baseline evidence and limitations. |
| `docs/COMPARISON_MODE.md` | Current, retained | Accepted always-both comparison interaction contract. |
| `docs/LOOKS.md` | Current, retained | LUT interchange, starter Looks, derive/save, and storage behavior. |
| `docs/LIBRARY_PACKAGE_PLAN.md` | Historical plan and format reference | Package product is implemented. The original phase sketch is retained as history; current behavior and migration boundaries are stated at the top and in `APP_ARCHITECTURE.md`. |
| `docs/PACKAGING.md` | Current, retained | Bundle, icon, signing, entitlement, and release workflow. |
| `docs/TESTING.md` | Current, retained | Required/optional test lanes, profiling, and manual UI checks. |
| `scripts/README.md` | Current, retained | Script entry points and their requirements. |
| `realworldtest/README.md` | Current, retained | Local fixture policy and licensing terms. |
| `.dg/README.md`, `.dg/AGENTS.md` | Current operational guidance | DispatchGraph commands and lifecycle rules. |
| `.dg/decisions/*.md` | Accepted historical decision records | Durable decisions remain discoverable; issue-specific capture details are not treated as current product docs. |
| `.dg/issues/*.md` | Canonical issue history | Generated/current lifecycle records; preserved rather than rewritten by this documentation audit. |
| `.dg/.project/pickup/*.md` | Generated operational packets | Disposable pickup context/log artifacts; not hand-authored product guidance. |
| `.context/initial_concept.md` | Superseded historical provenance | Clearly marked as the pre-Kromora concept; current readers should use `README.md` and `docs/`. |

The retained `docs/` tree is intentionally larger than the five-file post-KRMA-340 baseline because
the shipped Auto, comparison, coordinator, and package-library decisions have distinct current
roles. Volatile implementation transcripts and dated reports remain excluded unless they explain a
current constraint or supported workflow. The old folder-backed and SwiftData descriptions above
are superseded historical statements, not the current product contract.

## Disposition

| Original path | Disposition | Reason |
| --- | --- | --- |
| `ARCHITECTURE_BOUNDARIES.md` | Merged into `ENGINEERING_GUIDE.md` | Current boundaries were useful, but the standalone text contained a stale extraction reference. |
| `AUTO_ADJUSTMENT.md` | Merged into `ENGINEERING_GUIDE.md` | The detailed heuristic was implementation-level and incomplete after the content-aware Auto work. |
| `CANVAS_OBSERVATION_PERFORMANCE.md` | Merged into `ENGINEERING_GUIDE.md` | Current observation ownership is durable; the old issue-named capture recipe was redundant. |
| `CODE_REVIEW.md` | Deleted | Historical audit with superseded findings, stale phase framing, and no single current operational role. |
| `COLOR_MODEL.md` | Deleted | Volatile renderer details and old cache-version claims; source/tests are authoritative. |
| `EFFECTS_MODEL.md` | Deleted | Volatile stage/version detail duplicated by the implementation and already drifted. |
| `EFFECTS_VALIDATION.md` | Merged into `TESTING.md` | The current test/profiling principle remains useful; the standalone matrix was redundant. |
| `INSPECTOR_DISCLOSURES.md` | Merged into `TESTING.md` | Manual UI coverage belongs with the other manual checks. |
| `INSTRUMENTS.md` | Merged into `TESTING.md` | Profiling procedure is current but belongs in one testing guide. |
| `KROMORA_ICON.md` | Merged into `PACKAGING.md` | Icon guidance is part of the release workflow. |
| `LIGHT_MODEL.md` | Deleted | Volatile model/cache-version detail duplicated by source and README. |
| `LUMO-108-RESOLUTION-PLANNING.md` | Deleted | Completed issue planning record; no active compatibility constraint. |
| `LUMO-113-SCHEDULING.md` | Merged into `ENGINEERING_GUIDE.md` | Durable ownership principle retained; dated measurements and issue framing removed. |
| `LUMO-118-DSC07826-20260901-201604-summary.md` | Deleted | Historical hardware capture artifact with no current operational value. |
| `LUMO-121-DSC07826-20260901-222341-summary.md` | Deleted | Historical hardware capture artifact with no current operational value. |
| `LUMO-123-DSC07826-20260902-124253-summary.md` | Deleted | Historical concurrent-capture report superseded by the supported wrapper. |
| `LUMO-217-MASK-OVERLAY-BASELINE-2026-09-04.md` | Deleted | Prototype/baseline report; shipped masking behavior is covered by source/tests. |
| `LUMO-226-MASKING-HARDENING-REPORT-2026-09-05.md` | Deleted | Completed hardening report and dated hardware limitation, not current guidance. |
| `LUT_FORMAT.md` | Merged into `LOOKS.md` | LUT support and Look storage form one workflow. |
| `MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md` | Deleted | Explicitly planning-only and superseded by the implemented masking system. |
| `MASK_PERSISTENCE.md` | Merged into `ENGINEERING_GUIDE.md` | Current persistence boundary retained without a duplicate standalone model note. |
| `PERFORMANCE_AUDIT_2026-09-01.md` | Deleted | Dated audit and ticket index; no current claim depends on its measurements. |
| `PERFORMANCE_CAPTURE_MATRIX_2026-09-01.md` | Deleted | Historical capture matrix duplicated by the current testing guide. |
| `PHASE2_SPEC.md` | Rewritten as `ENGINEERING_GUIDE.md` | Completed phase plan was converted into durable current contracts. |
| `PHASE3_SPEC.md` | Deleted | Superseded issue plan with stale ticket names and sequencing; current implementation is the source of truth. |
| `PHOTOS_IMPORT_PERFORMANCE.md` | Merged into `TESTING.md` | Current bounded-import checks belong with the required/optional test lanes. |
| `PHOTO_INTELLIGENCE_TUNING_2026-09-04.md` | Deleted | Dated tuning report; no current contributor workflow requires its numbers. |
| `RENDER_MEMORY_BUDGET.md` | Merged into `ENGINEERING_GUIDE.md` | Resource ownership and bounded-work invariant retained without fragile numeric detail. |
| `STARTER_LOOKS.md` | Merged into `LOOKS.md` | Starter assets and LUT format are one user/contributor workflow. |
| `TEST_LIBRARY_CLEANUP.md` | Deleted | One-time cleanup procedure for historical generated fixtures. |
| `THEME_VALIDATION.md` | Merged into `TESTING.md` | Current manual appearance check consolidated with other UI checks. |
| `superpowers/plans/2026-08-06-step10a-raw-develop-inspector.md` | Deleted | Upstream/one-off implementation plan, completed and full of stale paths and commands. |
| `superpowers/plans/2026-08-06-step10b-adjustments-inspector.md` | Deleted | Upstream/one-off implementation plan, completed and full of stale paths and commands. |
| `superpowers/specs/2026-08-05-step9-derive-registry-design.md` | Deleted | Historical design transcript superseded by shipped implementation and tests. |
| `superpowers/specs/2026-08-06-step10a-raw-develop-inspector-design.md` | Deleted | Historical design transcript superseded by shipped implementation and tests. |
| `superpowers/specs/2026-08-06-step10b-adjustments-inspector-design.md` | Deleted | Historical design transcript superseded by shipped implementation and tests. |

Accepted limitation: dated performance results and full planning provenance remain discoverable in
git history and DispatchGraph issue records, but are intentionally not retained as current docs.
