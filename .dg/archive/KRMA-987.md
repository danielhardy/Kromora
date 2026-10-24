---
id: KRMA-987
title: Document the Observation convention for new UI state
type: task
status: done
priority: medium
agent: claude
human_review_required: false
model: sonnet
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: CLAUDE.md contains concise Observation guidance and a working link to docs/ENGINEERING_GUIDE.md#observation.
      result: pass
    - criterion: The guidance prefers Observation for new UI-facing state and maps plain stored references, @Bindable bindings, and @State view-owned models.
      result: pass
    - criterion: No tests, source scans, allowlists, lint/compiler checks, or CI gates were added or changed for this convention.
      result: pass
      notes: Reviewed the changed test and CI paths; their unrelated export coverage/filter changes add no Observation enforcement.
    - criterion: .dg/AGENTS.md remains unchanged.
      result: pass
  checks_run:
    - Resolved the CLAUDE.md relative link and confirmed the observation anchor exists in docs/ENGINEERING_GUIDE.md.
    - Reviewed the CLAUDE.md documentation diff.
    - git diff --check -- CLAUDE.md passed.
    - Build and tests skipped as directed for this documentation-only change.
  findings: []
  fixes: []
  verification_commits:
    - 4b40e90a764a75954619c0e212f72d284542cabf
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-15T01:36:49.055Z
  session: 01MV8V9A59CYQTK5HN
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - observation
  - swiftui
  - maintainability
created: 2026-10-13T22:11:31.143Z
updated: 2026-10-15T01:36:49.059Z
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-15T01:34:47.291Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 4b40e90a764a75954619c0e212f72d284542cabf
---

## Objective

Document the project convention for new UI-facing state: prefer Swift Observation (`@Observable`) by default, and point contributors to the architecture guidance for the ownership and SwiftUI wrapper details. This is contributor guidance only; do not add hard enforcement.

## Context

The Observation migration completed in KRMA-981. [`docs/ENGINEERING_GUIDE.md`](../../docs/ENGINEERING_GUIDE.md#observation) already explains the current architecture and implementation details, but `CLAUDE.md` has no short convention for agents adding new UI state. Since `CLAUDE.md` is the canonical shared agent guidance, add a concise pointer there rather than duplicating the full architecture section.

Do not add a source scan, allowlist, lint rule, compiler check, or CI gate for this convention. Do not change existing tests as part of this documentation issue.

## Approach

1. Add a short Observation subsection under the Swift 6 guidance in `CLAUDE.md`.
2. State that new UI-facing state should generally use `@MainActor @Observable`, with plain stored references, `@Bindable` for needed bindings, and `@State` for view-owned models.
3. Mention `@ObservationIgnored` for stored implementation details views do not read, then link to the Observation section of `docs/ENGINEERING_GUIDE.md` for the complete rules and rationale.
4. Keep this change limited to documentation; no source, tests, or enforcement mechanisms.

## Acceptance criteria

- [ ] `CLAUDE.md` contains concise Observation guidance and a working link to `docs/ENGINEERING_GUIDE.md#observation`.
- [ ] The guidance says to prefer Observation for new UI-facing state and gives the basic SwiftUI ownership and wrapper mapping.
- [ ] No tests, source scans, allowlists, lint/compiler checks, or CI gates are added or changed for this convention.
- [ ] `.dg/AGENTS.md` remains unchanged.

## Verification

- Check that the Markdown link resolves to the existing Observation section in `docs/ENGINEERING_GUIDE.md`.
- Review the documentation diff; no build or test run is needed for this docs-only change.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-15T01:36:49.055Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] CLAUDE.md contains concise Observation guidance and a working link to docs/ENGINEERING_GUIDE.md#observation. (pass)
- [x] The guidance prefers Observation for new UI-facing state and maps plain stored references, @Bindable bindings, and @State view-owned models. (pass)
- [x] No tests, source scans, allowlists, lint/compiler checks, or CI gates were added or changed for this convention. (pass) — Reviewed the changed test and CI paths; their unrelated export coverage/filter changes add no Observation enforcement.
- [x] .dg/AGENTS.md remains unchanged. (pass)
Checks run:
- Resolved the CLAUDE.md relative link and confirmed the observation anchor exists in docs/ENGINEERING_GUIDE.md.
- Reviewed the CLAUDE.md documentation diff.
- git diff --check -- CLAUDE.md passed.
- Build and tests skipped as directed for this documentation-only change.
Findings:
- None
Fixes:
- None
Verification commits:
- 4b40e90a764a75954619c0e212f72d284542cabf
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV8V9A59CYQTK5HN
Summary: Counterpoint verification passed; documentation link and guidance are correct. Commit 4b40e90a764a75954619c0e212f72d284542cabf.
