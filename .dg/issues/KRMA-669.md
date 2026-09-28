---
id: KRMA-669
title: Radically rewrite product documentation around the current MVP
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Inventory README/docs/.context and classify each
      result: pass
      notes: docs/DOCUMENTATION_AUDIT.md provides a full classification table (current guidance, historical record, dated evidence, deferred idea) covering docs/, .context/, and top-level files.
    - criterion: Rewrite README product story and feature list accurately
      result: pass
      notes: README.md rewritten around Library->Edit->Export workflow. Spot-checked 6 factual claims (Metal usage, export formats/GPS default, Heal/Clone + dust-as-suggestion, Auto guardrails/unchanged path, verified backup/restore, external-editor TIFF handoff) against Sources/KromoraKit and docs/INTEROP_EXPORT.md; all supported.
    - criterion: Establish one clear MVP intent source with audience/workflow/release bar/post-MVP boundaries
      result: pass
      notes: docs/PRODUCT_SCOPE.md added; explicitly states no Lightroom parity goal, defines release bar and post-MVP boundaries.
    - criterion: Reconcile cross-links and status language across topical guides
      result: pass
      notes: APP_ARCHITECTURE.md, ENGINEERING_GUIDE.md, STORAGE_POLICY.md, LIBRARY_PACKAGE_BASELINE.md, REPOSITORY_IMPROVEMENT_PLAN.md, and others gained short PRODUCT_SCOPE.md cross-links and historical/current labeling headers; RETOUCH.md/TESTING.md/PACKAGING.md linked from README and audit table.
    - criterion: Keep durable engineering constraints discoverable
      result: pass
      notes: macOS 14+, Swift 6, zero third-party deps, package ownership rules, shared render pipeline, and CI verification lanes all remain stated in README and CLAUDE.md.
    - criterion: Review and update DOCUMENTATION_AUDIT.md
      result: pass
      notes: Rewritten with current/historical/deferred tables and a consolidation section explaining what changed and why.
    - criterion: Keep deferred proposal spec recoverable and separate from MVP roadmap
      result: pass
      notes: .context/2026-09-22-professional-polish-evaluation.md retained and explicitly labeled as an idea archive, linked from README/PRODUCT_SCOPE/audit, not folded into MVP scope.
    - criterion: Check internal links/command examples; run dg validate and git diff --check
      result: pass
      notes: "Re-ran both independently: dg validate returns OK (only pre-existing unrelated model-name warnings); git diff --check on the doc commit is clean. Also independently re-verified every markdown link in README.md, PRODUCT_SCOPE.md, and DOCUMENTATION_AUDIT.md resolves to an existing file."
  checks_run:
    - dg validate -> OK (only pre-existing unrelated model-name warnings)
    - git diff --check ac819e8^ ac819e8 -> clean, no whitespace errors
    - custom markdown link resolution check over README.md, docs/PRODUCT_SCOPE.md, docs/DOCUMENTATION_AUDIT.md -> all relative links resolve
    - source cross-check of 6 README factual capability claims (Metal, export/GPS default, Heal/Clone+dust suggestion, Auto guardrails, verified backup/restore, external-editor TIFF handoff) against Sources/KromoraKit and docs/INTEROP_EXPORT.md -> all supported
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-28T16:23:19.000Z
  session: 01MULGG45NECLFZOLD
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - docs
  - mvp
  - product-scope
created: 2026-09-28T00:06:24.095Z
updated: 2026-09-28T16:23:19.002Z
blockers: []
order: a0
board: product
---

## Objective

Radically reorganize and rewrite Kromora's documentation so it describes the product that exists, the MVP it is trying to ship, and the ideas that have explicitly been deferred. A reader should be able to understand Kromora's intended audience, core workflow, current capabilities, limitations, and architectural constraints without mistaking a competitor gap analysis or a historical implementation plan for the roadmap.

## Context

The documentation has accumulated several layers: current product behavior, historical plans, architectural contracts, evaluation notes, and DispatchGraph proposals. Some current capabilities and recent work are not reflected consistently in the top-level product story, while `.context/initial_concept.md` and `.context/2026-09-22-professional-polish-evaluation.md` can be mistaken for active plans despite their historical/gap-analysis framing.

Use this issue to establish a coherent documentation hierarchy and update the docs to match the current app and selected MVP scope. Preserve technically important architecture and storage contracts; retire or clearly label stale implementation detail instead of flattening everything into the README. The professional-polish proposals preserved in the evaluation document are idea storage, not MVP commitments.

## Acceptance criteria

- [ ] Inventory the README, current `docs/`, and relevant `.context/` files; classify each as current product guidance, architecture/operations reference, historical record, or deferred idea.
- [ ] Rewrite the README's product story and feature list to accurately describe the current workflow and shipped behavior, including recently added capabilities and known limits. Remove unsupported parity claims and avoid promising roadmap ideas as current features.
- [ ] Establish one clear, concise source for MVP intent, target user, core workflow, release bar, and explicit post-MVP boundaries. Make clear that Kromora is not aiming for full Lightroom feature parity.
- [ ] Reconcile cross-links and status language across `APP_ARCHITECTURE.md`, `ENGINEERING_GUIDE.md`, `STORAGE_POLICY.md`, `LIBRARY_PACKAGE_PLAN.md`, `RETOUCH.md`, `TESTING.md`, `PACKAGING.md`, and the remaining topical guides. Current behavior must point to current sources; historical plans and completed sequences must be unmistakably labeled.
- [ ] Keep durable engineering constraints discoverable: macOS 14+, Swift 6, zero third-party runtime dependencies, package ownership/data-safety rules, shared preview/export rendering, and verification lanes.
- [ ] Review `DOCUMENTATION_AUDIT.md` and update it to reflect this rewrite, including documents consolidated, retained, relabeled, or removed and why.
- [ ] Keep the deferred proposal specifications in `.context/2026-09-22-professional-polish-evaluation.md` recoverable and clearly separate from the MVP roadmap.
- [ ] Check all internal links and command examples touched by the rewrite; run `dg validate` and `git diff --check`.

## Implementation notes

- Begin from the live README, source, tests, and durable architecture/storage guides. Treat `.context/initial_concept.md` as project provenance, not a requirements source.
- Avoid a broad code change or rewriting useful architecture references just to reduce document count.
- Keep product-facing prose direct and specific. Put implementation detail in the relevant guide and ideas in the deferred-proposal section.
- Preserve provenance where historical files remain useful; do not delete context needed to recover decisions or deferred proposals.

### Comment — codex @ 2026-09-28T16:21:24.188Z

Rewrote the README around the current Library → Edit → Export workflow; added docs/PRODUCT_SCOPE.md for MVP intent, release bar, and post-MVP boundaries; updated DOCUMENTATION_AUDIT.md and relabeled historical plans, dated reviews, and the deferred proposal archive. Internal Markdown links checked across 28 files; dg validate passes with existing model-name warnings; git diff --check passes. Commit: ac819e8.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-28T16:23:19.000Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Inventory README/docs/.context and classify each (pass) — docs/DOCUMENTATION_AUDIT.md provides a full classification table (current guidance, historical record, dated evidence, deferred idea) covering docs/, .context/, and top-level files.
- [x] Rewrite README product story and feature list accurately (pass) — README.md rewritten around Library->Edit->Export workflow. Spot-checked 6 factual claims (Metal usage, export formats/GPS default, Heal/Clone + dust-as-suggestion, Auto guardrails/unchanged path, verified backup/restore, external-editor TIFF handoff) against Sources/KromoraKit and docs/INTEROP_EXPORT.md; all supported.
- [x] Establish one clear MVP intent source with audience/workflow/release bar/post-MVP boundaries (pass) — docs/PRODUCT_SCOPE.md added; explicitly states no Lightroom parity goal, defines release bar and post-MVP boundaries.
- [x] Reconcile cross-links and status language across topical guides (pass) — APP_ARCHITECTURE.md, ENGINEERING_GUIDE.md, STORAGE_POLICY.md, LIBRARY_PACKAGE_BASELINE.md, REPOSITORY_IMPROVEMENT_PLAN.md, and others gained short PRODUCT_SCOPE.md cross-links and historical/current labeling headers; RETOUCH.md/TESTING.md/PACKAGING.md linked from README and audit table.
- [x] Keep durable engineering constraints discoverable (pass) — macOS 14+, Swift 6, zero third-party deps, package ownership rules, shared render pipeline, and CI verification lanes all remain stated in README and CLAUDE.md.
- [x] Review and update DOCUMENTATION_AUDIT.md (pass) — Rewritten with current/historical/deferred tables and a consolidation section explaining what changed and why.
- [x] Keep deferred proposal spec recoverable and separate from MVP roadmap (pass) — .context/2026-09-22-professional-polish-evaluation.md retained and explicitly labeled as an idea archive, linked from README/PRODUCT_SCOPE/audit, not folded into MVP scope.
- [x] Check internal links/command examples; run dg validate and git diff --check (pass) — Re-ran both independently: dg validate returns OK (only pre-existing unrelated model-name warnings); git diff --check on the doc commit is clean. Also independently re-verified every markdown link in README.md, PRODUCT_SCOPE.md, and DOCUMENTATION_AUDIT.md resolves to an existing file.
Checks run:
- dg validate -> OK (only pre-existing unrelated model-name warnings)
- git diff --check ac819e8^ ac819e8 -> clean, no whitespace errors
- custom markdown link resolution check over README.md, docs/PRODUCT_SCOPE.md, docs/DOCUMENTATION_AUDIT.md -> all relative links resolve
- source cross-check of 6 README factual capability claims (Metal, export/GPS default, Heal/Clone+dust suggestion, Auto guardrails, verified backup/restore, external-editor TIFF handoff) against Sources/KromoraKit and docs/INTEROP_EXPORT.md -> all supported
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MULGG45NECLFZOLD
