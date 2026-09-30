---
id: KRMA-384
title: Track the portable library package implementation plan
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Review and approve the package format, identity, migration, and performance assumptions
      result: pass
      notes: ADR-001 status approved; EDIT_STORE_IDENTITY_DISPOSITION.md exists
    - criterion: Break the plan into implementation issues with dependencies and verification lanes
      result: pass
      notes: KRMA-389..393 archived with status done
    - criterion: Implement the approved phases without changing deletion behavior or discarding data
      result: pass
      notes: Phases archived done; no source changes in this issue
    - criterion: Update or retire the plan as each phase lands
      result: pass
      notes: LIBRARY_PACKAGE_PLAN.md carries historical notice and links to APP_ARCHITECTURE/STORAGE_POLICY; linked docs and ADR exist
  checks_run:
    - "dg validate (warnings only: unknown model names on unrelated issues)"
    - git diff --check (clean)
    - verified ADR-001 approved and KRMA-389..393 archived done
    - verified linked docs exist
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T13:00:48.603Z
  session: 01MUMOP2UMFQ3NID1G
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - library
  - architecture
  - documentation
created: 2026-09-12T15:25:59.782Z
updated: 2026-09-29T13:00:48.605Z
blockers:
  - id: legacy-krma-384
    type: human
    reason: The package plan requires human approval of the current EditStore data disposition and the local-only package and compatibility policy before identity or persistence implementation can begin.
    action: Approve ADR-001, or specify the migration/disposition for current library data and any changes to the local-only compatibility boundary; then resume KRMA-384.
    created_at: 2026-09-12T19:23:20.577Z
    resolved_at: 2026-09-29T12:58:27.829Z
    resolved_by: web
order: a0
board: product
blocked_reason: The package plan requires human approval of the current EditStore data disposition and the local-only package and compatibility policy before identity or persistence implementation can begin.
blocked_action: Approve ADR-001, or specify the migration/disposition for current library data and any changes to the local-only compatibility boundary; then resume KRMA-384.
blocked_from_status: claimed
---

## Objective

Track the approved portable, self-contained library package plan through its design, phased
implementation, and transition to the shipped product architecture.

## Context

The implementation phases have shipped. `docs/LIBRARY_PACKAGE_PLAN.md` retains the original design
and format rationale as a historical reference; current behavior is documented in
`docs/APP_ARCHITECTURE.md`, `docs/STORAGE_POLICY.md`, and `docs/LIBRARY_PACKAGE_FORMAT.md`. Keep this
work separate from the unrelated KRMA-371 Library deletion workflow. The approved legacy-data
disposition is recorded in `docs/EDIT_STORE_IDENTITY_DISPOSITION.md` and ADR-001.

## Acceptance criteria

- [x] Review and approve the package format, identity, migration, and performance assumptions. —
  ADR-001 is approved; the current-data disposition is explicitly recorded.
- [x] Break the plan into implementation issues with explicit dependencies and verification lanes. —
  KRMA-389 through KRMA-393 captured the phases and are archived as complete.
- [x] Implement the approved phases without changing current deletion behavior or silently
  discarding existing library data. — The package implementation and follow-on integration shipped;
  the legacy-data disposition was approved and documented, and deletion behavior remained separate.
- [x] Update or retire the plan as each phase lands. — The plan now identifies itself as historical
  and points to current architecture and storage documentation.

## Implementation notes

- Historical design: `docs/LIBRARY_PACKAGE_PLAN.md`.
- iCloud sync remains out of scope and requires a separate decision. The approved legacy-data
  disposition is documented in ADR-001 and `docs/EDIT_STORE_IDENTITY_DISPOSITION.md`.

### Comment — codex @ 2026-09-12T19:23:16.543Z

Reviewed docs/LIBRARY_PACKAGE_PLAN.md and recorded ADR-001. Created the phased implementation issues KRMA-389 through KRMA-393 with explicit dependencies, acceptance criteria, and verification lanes. Updated the plan tracking line. No source, deletion behavior, or current library data was changed.

### Comment — codex @ 2026-09-29T13:00:09.464Z

Completed the package plan tracking: ADR-001 and the legacy-data disposition are approved, KRMA-389–393 are archived complete, and docs/LIBRARY_PACKAGE_PLAN.md now identifies the shipped plan as historical and links current architecture guidance. No further product changes were needed. Checks: dg validate and git diff --check passed.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

## HUMAN NOTE:

I have alrady approved and we are good to go

### Comment — codex @ 2026-09-29

Closed the tracking loop: ADR-001 and the legacy-data disposition are approved and documented;
KRMA-389 through KRMA-393 are archived complete; the package phases and integration are shipped;
and the plan now marks itself historical with links to current architecture and storage docs.
No additional product changes were needed for KRMA-384.

- 2026-09-29T13:00:48.603Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Review and approve the package format, identity, migration, and performance assumptions (pass) — ADR-001 status approved; EDIT_STORE_IDENTITY_DISPOSITION.md exists
- [x] Break the plan into implementation issues with dependencies and verification lanes (pass) — KRMA-389..393 archived with status done
- [x] Implement the approved phases without changing deletion behavior or discarding data (pass) — Phases archived done; no source changes in this issue
- [x] Update or retire the plan as each phase lands (pass) — LIBRARY_PACKAGE_PLAN.md carries historical notice and links to APP_ARCHITECTURE/STORAGE_POLICY; linked docs and ADR exist
Checks run:
- dg validate (warnings only: unknown model names on unrelated issues)
- git diff --check (clean)
- verified ADR-001 approved and KRMA-389..393 archived done
- verified linked docs exist
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUMOP2UMFQ3NID1G
Summary: Verified docs-only tracking closure: ADR-001 approved, phases archived done, plan marked historical with valid links.
