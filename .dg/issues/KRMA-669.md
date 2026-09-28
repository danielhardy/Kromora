---
id: KRMA-669
title: Radically rewrite product documentation around the current MVP
type: task
status: backlog
priority: high
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - docs
  - mvp
  - product-scope
created: 2026-09-28T00:06:24.095Z
updated: 2026-09-28T00:06:24.095Z
blockers: []
order: zzzv
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
