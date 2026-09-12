---
id: KRMA-377
title: Organize the Looks panel into Starter Looks and My Looks sections
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - looks
  - ux
created: 2026-09-12T15:19:03.429Z
updated: 2026-09-12T15:19:18.072Z
order: zh
board: product
---

## Objective

Simplify the Looks panel by replacing the current per-Look accordion layout with two always-visible collections:

- **Starter Looks** — bundled/default Looks shipped with the app.
- **My Looks** — Looks imported or uploaded by the user.

These names are intended to be clearer and more welcoming than “Included” and “Users.”

## Context

The current Looks panel makes every Look independently collapsible, which adds interaction overhead and hides the available choices. The expanded default library work in KRMA-372 will increase the number of bundled Looks, making a flat, grouped browser more useful. User-provided Looks must remain clearly separate from the read-only bundled collection.

Related work:
- KRMA-372 — expand the default Looks library.
- KRMA-150 — original bundled starter-library behavior and bundled/user source separation.

## Acceptance criteria

- [ ] Remove the individual accordion/disclosure behavior from Look rows; each Look is directly visible in its collection.
- [ ] Add a visible **Starter Looks** group containing every bundled/default Look, including the additional defaults from KRMA-372.
- [ ] Add a visible **My Looks** group containing every user-uploaded/imported or user-created Look.
- [ ] The two group headings remain visible while browsing; they are not themselves collapsible unless a later design decision explicitly adds that behavior.
- [ ] Keep the existing Look actions intact, including selecting/applying, previewing, auditioning, intensity adjustment, importing, and any remove/reveal actions supported for user Looks.
- [ ] Preserve the read-only status and provenance distinction for Starter Looks; user Looks must not be presented as bundled content.
- [ ] Define and implement sensible empty states, including a clear import action when My Looks has no user-provided entries.
- [ ] Use stable deterministic ordering within each group and keep the layout usable as the Starter Looks collection grows.
- [ ] Add or update UI/state tests covering group membership, no per-row accordions, empty My Looks behavior, and separation of bundled versus user sources.
- [ ] Verify existing Look-library tests and the relevant build/test lanes; run `dg validate` and `git diff --check`.

## Out of scope

- Adding or replacing Look assets; the bundled asset expansion belongs to KRMA-372.
- Changing LUT/Look import formats, persistence locations, or application/rendering behavior.
- Making the Starter Looks collection editable or deletable by users.
