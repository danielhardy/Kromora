---
id: KRMA-808
title: "Epic: App Store compatibility, privacy, and entitlements"
type: feature
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The sandbox audit document is complete and every blocker has a ticket.
      result: pass
      notes: Pass reports for KRMA-783, KRMA-784, and KRMA-785 cover the audit; the current signed-run and staging questions are separately tracked in KRMA-818 and KRMA-823.
    - criterion: The Photos usage string is present; no unneeded permission strings exist.
      result: pass
      notes: Verified through KRMA-782 and KRMA-785; the usage-description, purpose-string, and protected-API inventory work is complete.
    - criterion: Entitlements are the minimal audited set and are asserted by verification scripts.
      result: pass
      notes: KRMA-790 passed; App/Kromora.entitlements and the signature verification script are present.
    - criterion: The App Store Connect privacy posture is documented from the app's and partners' actual data practices.
      result: pass
      notes: KRMA-783/784/785 and KRMA-807 pass; docs/APP_STORE_SUBMISSION.md is present.
    - criterion: "The required-reason manifest scope is documented accurately: Kromora's native macOS target does not need required-reason entries solely for its API calls; mandatory third-party SDK manifests or future covered platforms are handled separately."
      result: pass
      notes: KRMA-798 passed; docs/APP_STORE_SANDBOX_AUDIT.md records native macOS scope and future covered-platform handling.
  checks_run:
    - Confirmed declared child issues KRMA-782, KRMA-783, KRMA-784, KRMA-785, KRMA-790, and KRMA-798 are done and each has verification_report.verdict=pass.
    - git merge-base --is-ancestor for each declared child implementation commit against HEAD 59f9039f (all passed).
    - Confirmed docs/APP_STORE_SANDBOX_AUDIT.md, docs/APP_STORE_SUBMISSION.md, App/Kromora.entitlements, and scripts/verify-app-signature.sh are present.
    - "dg validate --json: ok; only pre-existing model-configuration warnings."
  findings:
    - KRMA-818 remains in review with a Human blocker for final signed UI checks and cleanup; KRMA-823 tracks a separate sandbox write check for replacement Look staging. Both are separately ticketed follow-ups and are outside KRMA-808 declared dependencies.
  fixes: []
  verification_commits:
    - 4d7ae86d
    - e130845a
    - 059cbb22
    - 5d7e4eb0
    - 3398378f
    - b78b888c
  actor: codex
  resolved_model: unknown
  completed_at: 2026-10-05T14:49:26.675Z
  session: 01MUVD1ROJCD0VSI8U
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - epic
  - appstore
created: 2026-10-03T19:25:12.534Z
updated: 2026-10-05T14:49:26.679Z
depends_on:
  - KRMA-782
  - KRMA-783
  - KRMA-784
  - KRMA-785
  - KRMA-790
  - KRMA-798
blockers: []
order: a0
board: product
commits:
  - 4d7ae86d
  - e130845a
  - 059cbb22
  - 5d7e4eb0
  - 3398378f
  - b78b888c
---

## Completion disposition

This aggregate parent is complete: each declared child dependency is done with passing verification,
and each implementation commit is present in repository history. Related follow-up work remains
tracked separately: KRMA-818 has human signed-build checks pending, and KRMA-823 tracks a sandbox
write check for replacement Look staging. These follow-ups are outside this epic's declared
dependencies; the audit blockers have explicit tickets.

## Objective

Establish by audit and then by minimal configuration that Kromora can run inside the App Sandbox with only the capabilities and purpose strings it truly uses, and declare its privacy posture.

Source plan: `.context/2026-09-30-app-store-release-plan.md` (Plan Workstreams 0, 3, 4).

## Outcome

- [x] The sandbox audit document is complete and every blocker has a ticket.
- [x] The Photos usage string is present; no unneeded permission strings exist.
- [x] Entitlements are the minimal audited set and are asserted by verification scripts.
- [x] The App Store Connect privacy posture is documented from the app's and partners' actual data practices.
- [x] The required-reason manifest scope is documented accurately: Kromora's native macOS target does not need required-reason entries solely for its API calls; mandatory third-party SDK manifests or future covered platforms are handled separately.

## Child tickets (in execution order)

- KRMA-782 — Add the Photos library usage description to the app Info.plist
- KRMA-783 — App Sandbox audit 1/3: import, open, drag-drop, and security-scoped access
- KRMA-784 — App Sandbox audit 2/3: export, Photos, storage, caches, and temp files
- KRMA-785 — App Sandbox audit 3/3: network, subprocesses, resources, and protected-API inventory
- KRMA-790 — Trim entitlements to the capabilities Kromora actually uses
- KRMA-798 — Document native macOS required-reason privacy scope


### Comment — codex @ 2026-10-05T04:16:02.556Z

Reviewed the tracking parent and its outcomes. The six listed dependencies are done, with the sandbox audit, Photos usage description, minimal asserted entitlements, submission privacy worksheet, and native macOS required-reason scope documented. Per this issue's current disposition, no child implementation belongs in this session; releasing the claim and keeping KRMA-808 in backlog.


### Comment — codex @ 2026-10-05T13:18:53.392Z

codex pickup review: this parent is explicitly tracking-only, and all six declared child dependencies are already done with passing verification reports. The scoped work is complete; no additional implementation belongs in this session.

## Agent log

- 2026-10-05T14:49:26.675Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The sandbox audit document is complete and every blocker has a ticket. (pass) — Pass reports for KRMA-783, KRMA-784, and KRMA-785 cover the audit; the current signed-run and staging questions are separately tracked in KRMA-818 and KRMA-823.
- [x] The Photos usage string is present; no unneeded permission strings exist. (pass) — Verified through KRMA-782 and KRMA-785; the usage-description, purpose-string, and protected-API inventory work is complete.
- [x] Entitlements are the minimal audited set and are asserted by verification scripts. (pass) — KRMA-790 passed; App/Kromora.entitlements and the signature verification script are present.
- [x] The App Store Connect privacy posture is documented from the app's and partners' actual data practices. (pass) — KRMA-783/784/785 and KRMA-807 pass; docs/APP_STORE_SUBMISSION.md is present.
- [x] The required-reason manifest scope is documented accurately: Kromora's native macOS target does not need required-reason entries solely for its API calls; mandatory third-party SDK manifests or future covered platforms are handled separately. (pass) — KRMA-798 passed; docs/APP_STORE_SANDBOX_AUDIT.md records native macOS scope and future covered-platform handling.
Checks run:
- Confirmed declared child issues KRMA-782, KRMA-783, KRMA-784, KRMA-785, KRMA-790, and KRMA-798 are done and each has verification_report.verdict=pass.
- git merge-base --is-ancestor for each declared child implementation commit against HEAD 59f9039f (all passed).
- Confirmed docs/APP_STORE_SANDBOX_AUDIT.md, docs/APP_STORE_SUBMISSION.md, App/Kromora.entitlements, and scripts/verify-app-signature.sh are present.
- dg validate --json: ok; only pre-existing model-configuration warnings.
Findings:
- KRMA-818 remains in review with a Human blocker for final signed UI checks and cleanup; KRMA-823 tracks a separate sandbox write check for replacement Look staging. Both are separately ticketed follow-ups and are outside KRMA-808 declared dependencies.
Fixes:
- None
Verification commits:
- 4d7ae86d
- e130845a
- 059cbb22
- 5d7e4eb0
- 3398378f
- b78b888c
Actor: codex
Resolved model: unknown
Pickup session: 01MUVD1ROJCD0VSI8U
Summary: Verified: all six declared child tickets are done with passing reports; their commits and the App Store sandbox/privacy artifacts are present. Signed UI and staging questions remain separately ticketed in KRMA-818 and KRMA-823.
