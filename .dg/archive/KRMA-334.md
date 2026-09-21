---
id: KRMA-334
title: Audit and retire obsolete scripts under scripts/
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: lifecycle-table
      result: pass
      notes: scripts/README.md covers active, opt-in, and historical scripts with macOS/display/fixture requirements.
    - criterion: ci-scripts-preserved
      result: pass
      notes: Formatting, test lanes, packaging/icon/signature verification, and smoke scripts remain present and unchanged.
    - criterion: mutation-harness-retirement
      result: pass
      notes: mutate-step9.sh and mutate-step10a.sh removed; Phase 2 docs retain outcomes and git history remains provenance.
    - criterion: capture-interface
      result: pass
      notes: run-kromora-capture.sh provides explicit metal-presentation and concurrent-export-editing modes and historical command references were updated.
    - criterion: reference-cleanup
      result: pass
      notes: No obsolete wrapper/run-lumo command references remain in live instructions; historical issue logs and archived summaries were preserved.
    - criterion: verification
      result: pass
      notes: dg validate, git diff --check, zsh/bash syntax checks, executable checks, trailing-whitespace audit, stale-reference audit, and CI-file immutability check passed.
  checks_run:
    - dg validate
    - git diff --check
    - zsh -n scripts/*.sh
    - bash -n scripts/agent-worktree.sh
    - retained scripts executable check
    - capture wrapper help and error-path smoke checks
    - live documentation/reference audit
    - CI workflow and retained CI-facing script diff check
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-10T14:31:43.985Z
  session: 01MTVMCU7ZUBHMVAZ4
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - maintenance
  - tooling
created: 2026-09-10T12:58:13.402Z
updated: 2026-09-10T14:31:43.986Z
order: z
board: product
commits:
  - b61e093
---

## Objective

Make the `scripts/` directory self-explanatory and remove or consolidate tooling that only served
completed historical work, without weakening CI, packaging verification, or reproducible local
benchmark capture.

## Context

The directory currently contains 12 executable scripts with mixed lifecycles. The active CI and
developer entry points are interleaved with phase-specific mutation harnesses and issue-specific
capture wrappers, making it unclear which scripts are safe/expected to run today.

Audit performed 2026-09-10:

| Script(s) | Evidence | Initial disposition |
| --- | --- | --- |
| `agent-worktree.sh` | Referenced by `CLAUDE.md` agent-safety instructions | Keep; document as workflow tooling |
| `check-swift-format.sh`, `ci-tests.sh` | Invoked by `.github/workflows/ci.yml`; also documented in `README.md` | Keep |
| `build-macos-app.sh`, `verify-app-icon.sh`, `verify-app-signature.sh` | Invoked by the CI package job and documented in `README.md`/icon docs | Keep |
| `smoke-macos-app.sh` | Invoked by the CI smoke job; exits 2 only for an unavailable hosted WindowServer | Keep; document its environment-dependent skip |
| `photo-intelligence-report.sh` | Referenced by the current photo-intelligence tuning doc and wraps the corpus report test | Keep; document as an opt-in report generator |
| `mutate-step9.sh`, `mutate-step10a.sh` | One-off Phase 2 harnesses from 2026-08; not used by CI. `docs/ENGINEERING_GUIDE.md` calls the mutation gate historical and the findings are already recorded in docs/tests | Retire from the live scripts directory after preserving provenance and updating stale references |
| `run-kromora-118-capture.sh` | KRMA-118 is done; still referenced by the performance capture matrix and `README.md` as a reproducible opt-in capture | Keep only if intentionally supported, otherwise migrate to a generic capture wrapper before removal |
| `run-kromora-123-capture.sh` | KRMA-123 is done; only the historical capture summary references this wrapper | Candidate for consolidation/removal; preserve the durable summary and trace metadata |

The two capture wrappers duplicate the same build/Release XCTest bundle/xctrace setup and differ
primarily in benchmark filter, environment variables, and summary metadata. The mutation scripts
also contain hard-coded source patterns and are not a maintainable regression mechanism once their
phase work is complete.

## Acceptance criteria

- [ ] Add a short lifecycle table (active, opt-in, or historical) for every script, either in
      `README.md` or a new `scripts/README.md`, including required macOS/display/fixture inputs.
- [ ] Keep and verify all scripts still required by CI: formatting, test lanes, app packaging/icon/
      signature checks, and the environment-dependent app smoke path.
- [ ] Retire `mutate-step9.sh` and `mutate-step10a.sh` from the live tree, or record a concrete
      reason to retain each. Before removal, ensure the mutation results and the Step 9/10a gap
      findings remain represented in durable docs/tests and update references that imply the files
      are current commands. Git history is sufficient provenance; do not copy the full harness into
      another live script.
- [ ] Decide the supported future capture interface. Prefer one parameterized xctrace capture
      wrapper for the shared setup, with benchmark-specific configuration passed explicitly; if
      the issue-specific wrappers are retained instead, document why. Preserve the existing
      KRMA-118/KRMA-123 historical summaries and update all command references consistently.
- [ ] Remove stale `run-lumo-*`/old product-name references from living instructions encountered
      during the script cleanup, while leaving historical issue logs and factual archived summaries
      intact where changing them would rewrite history.
- [ ] Run `dg validate`, `git diff --check`, shell syntax checks for retained scripts, and the
      relevant lightweight documentation/reference audit. CI-facing behavior must remain unchanged.

## Implementation notes

Do not delete scripts solely because they have few references: CI YAML, opt-in commands, and
historical reproducibility docs are valid consumers. Do not rerun the mutation harnesses or hardware
captures as part of this maintenance task unless needed to validate a replacement interface.

Relevant files: `scripts/`, `.github/workflows/ci.yml`, `CLAUDE.md`, `README.md`,
`docs/ENGINEERING_GUIDE.md`, `docs/ENGINEERING_GUIDE.md`, `docs/TESTING.md`,
`docs/TESTING.md`, and the completed issues KRMA-118/KRMA-123.

### Comment — codex @ 2026-09-10T14:31:29.395Z

Implemented the scripts cleanup. Added scripts/README.md with lifecycle and macOS/display/fixture requirements; removed the historical Step 9/10a mutation harnesses and preserved their outcomes/provenance in the Phase 2 docs; consolidated the two duplicate xctrace wrappers into scripts/run-kromora-capture.sh with explicit metal-presentation and concurrent-export-editing benchmark modes; updated README, the capture matrix, and historical summary command references; removed the stale standalone capture wording from living README instructions. CI workflow and retained CI-facing scripts were left unchanged.

### Comment — codex @ 2026-09-10T14:31:34.281Z

Implemented the scripts cleanup. Added scripts/README.md with lifecycle and macOS/display/fixture requirements; removed the historical Step 9/10a mutation harnesses and preserved their outcomes/provenance in the Phase 2 docs; consolidated the two duplicate xctrace wrappers into scripts/run-kromora-capture.sh with explicit metal-presentation and concurrent-export-editing benchmark modes; updated README, the capture matrix, and historical summary command references; removed the stale standalone capture wording from living README instructions. CI workflow and retained CI-facing scripts were left unchanged.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-10T14:31:43.985Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] lifecycle-table (pass) — scripts/README.md covers active, opt-in, and historical scripts with macOS/display/fixture requirements.
- [x] ci-scripts-preserved (pass) — Formatting, test lanes, packaging/icon/signature verification, and smoke scripts remain present and unchanged.
- [x] mutation-harness-retirement (pass) — mutate-step9.sh and mutate-step10a.sh removed; Phase 2 docs retain outcomes and git history remains provenance.
- [x] capture-interface (pass) — run-kromora-capture.sh provides explicit metal-presentation and concurrent-export-editing modes and historical command references were updated.
- [x] reference-cleanup (pass) — No obsolete wrapper/run-lumo command references remain in live instructions; historical issue logs and archived summaries were preserved.
- [x] verification (pass) — dg validate, git diff --check, zsh/bash syntax checks, executable checks, trailing-whitespace audit, stale-reference audit, and CI-file immutability check passed.
Checks run:
- dg validate
- git diff --check
- zsh -n scripts/*.sh
- bash -n scripts/agent-worktree.sh
- retained scripts executable check
- capture wrapper help and error-path smoke checks
- live documentation/reference audit
- CI workflow and retained CI-facing script diff check
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTVMCU7ZUBHMVAZ4
Summary: Scripts audit completed: lifecycle documentation added, obsolete mutation harnesses retired, duplicate capture wrappers consolidated into the parameterized run-kromora-capture.sh interface, historical summaries preserved, and live references updated.
