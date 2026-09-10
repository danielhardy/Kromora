# Documentation audit — 2026-09-10

KRMA-340 reviewed every file under `docs/` against the current `Sources/`, `Tests/`, `README.md`,
`CLAUDE.md`, scripts, package manifest, and DispatchGraph records. The final tree intentionally
contains only durable contributor guidance and this disposition record. Issue history remains in
`.dg/`; it is not duplicated under `docs/`.

## Final documentation tree

- [`ENGINEERING_GUIDE.md`](ENGINEERING_GUIDE.md) — current architecture, render/resource boundaries,
  persistence, masking, and contributor invariants.
- [`LOOKS.md`](LOOKS.md) — current LUT interchange, Look save/derive behavior, starter assets, and
  storage rules.
- [`PACKAGING.md`](PACKAGING.md) — current icon, bundle, signing, entitlement, and release workflow.
- [`TESTING.md`](TESTING.md) — required lanes, optional fixtures/benchmarks, profiling metadata, and
  manual UI verification scope.
- [`DOCUMENTATION_AUDIT.md`](DOCUMENTATION_AUDIT.md) — this audit and the file-by-file disposition.

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
