---
id: KRMA-806
title: Write the sandboxed-build acceptance checklist and fold it into KRMA-059
type: task
status: done
priority: high
verification_agent: claude
human_review_required: false
verification_model: sonnet
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: docs/APP_STORE_ACCEPTANCE.md exists with every scoped item, each with expected result and command/UI path
      result: pass
      notes: 30 cases A1-A30 plus Results template; covers sandbox check, folder/removable/drop imports, Photos allow/deny/limited, exports, bookmarks, Looks, sidecar boundary, Sandbox log stream.
    - criterion: Every could-not-be-proven audit item appears as a checklist step
      result: pass
      notes: Audit section 1 six runtime items, section 2 export items, and resource-bundle uncertainty map to A2,A5-A26; cross-check section included.
    - criterion: KRMA-059 has the linking comment and is otherwise unmodified
      result: pass
      notes: Acceptance note added at KRMA-059.md:54 in commit 415e031f (6-line change); status/criteria not touched.
    - criterion: No source or script changes
      result: pass
      notes: Commit 415e031f touches only docs and KRMA-059.md.
  checks_run:
    - Read full checklist and cross-checked against docs/APP_STORE_SANDBOX_AUDIT.md runtime items
    - Verified entitlements listed in A1 match App/Kromora.entitlements (5 keys)
    - Verified Xcode/Kromora.xcodeproj, release plan and audit paths exist
    - git diff --check clean
    - git show --stat 415e031f
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-05T00:00:32.174Z
  session: 01MUUHH3UTS1HODNAG
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - acceptance
  - docs
created: 2026-10-03T19:24:46.016Z
updated: 2026-10-05T00:00:32.177Z
depends_on:
  - KRMA-799
  - KRMA-785
blockers: []
order: t
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-04T23:52:23.042Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Define exactly what a person must run on the signed, sandboxed Xcode build to prove the plan's success criteria, since `swift run` cannot prove them.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, "Success criteria"). `.dg/issues/KRMA-059.md` ("Run fault-recovery and end-to-end MVP release acceptance") already covers a clean-profile import, cull, edit, compare, relaunch, and export pass; it should run against the sandboxed build, not `swift run`. The sandbox audit (`docs/APP_STORE_SANDBOX_AUDIT.md`) lists behaviors that could not be proven by reading code. Photos prompts and TestFlight behavior need a real display and account; an agent cannot run them, so this ticket produces the checklist, not the results.

## Scope

- Create `docs/APP_STORE_ACCEPTANCE.md`: a checklist with exact steps and expected results for the sandboxed Release build, covering: launches with the sandbox enabled (check with `codesign -d --entitlements :-` and Activity Monitor "Sandbox: Yes"); open/import a folder, a removable volume, and a drag-dropped folder; Photos permission prompt, allow, deny, and limited-library cases; export to a user-chosen folder and to Photos; reopen the library after quit and relaunch (bookmark persistence); bundled Looks appear; a RAW file's sidecar/neighbor access; no `Sandbox` denials in `log stream --predicate 'sender == "Sandbox"'` during the pass; plus every uncertain behavior listed in the audit.
- Add a "Results" template (date, build number, machine, pass/fail per item, denial log excerpt) the human fills in.
- Add a comment to `.dg/issues/KRMA-059.md` (via `dg issue comment KRMA-059 --actor <your agent name> …`) stating that its acceptance pass must use the sandboxed Xcode build and linking this checklist. Do not change KRMA-059's status or criteria.

## Acceptance criteria

- [ ] `docs/APP_STORE_ACCEPTANCE.md` exists with every item above, each with an expected result and the command or UI path to check it.
- [ ] Every "could not be proven" item from the audit appears as a checklist step.
- [ ] KRMA-059 has the linking comment and is otherwise unmodified.
- [ ] No source or script changes.

## Verification

- Cross-check the checklist against the audit's open items and the plan's success criteria list.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.


### Comment — codex @ 2026-10-04T23:52:19.646Z

Added docs/APP_STORE_ACCEPTANCE.md with an executable signed Xcode Release and TestFlight checklist, expected outcomes, log/entitlement checks, and a per-case Results template. Added the KRMA-059 link comment. Cross-checked 30 cases against the sandbox audit and release-plan criteria; git diff --check and the case/results-row consistency check passed. No app tests were run for this documentation-only ticket.

## Agent log

- 2026-10-05T00:00:32.174Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] docs/APP_STORE_ACCEPTANCE.md exists with every scoped item, each with expected result and command/UI path (pass) — 30 cases A1-A30 plus Results template; covers sandbox check, folder/removable/drop imports, Photos allow/deny/limited, exports, bookmarks, Looks, sidecar boundary, Sandbox log stream.
- [x] Every could-not-be-proven audit item appears as a checklist step (pass) — Audit section 1 six runtime items, section 2 export items, and resource-bundle uncertainty map to A2,A5-A26; cross-check section included.
- [x] KRMA-059 has the linking comment and is otherwise unmodified (pass) — Acceptance note added at KRMA-059.md:54 in commit 415e031f (6-line change); status/criteria not touched.
- [x] No source or script changes (pass) — Commit 415e031f touches only docs and KRMA-059.md.
Checks run:
- Read full checklist and cross-checked against docs/APP_STORE_SANDBOX_AUDIT.md runtime items
- Verified entitlements listed in A1 match App/Kromora.entitlements (5 keys)
- Verified Xcode/Kromora.xcodeproj, release plan and audit paths exist
- git diff --check clean
- git show --stat 415e031f
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUUHH3UTS1HODNAG
