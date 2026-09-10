---
id: KRMA-335
title: Clarify MIT licensing and reserve Kromora branding
type: task
status: claimed
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - legal
  - documentation
created: 2026-09-10T13:03:27.613Z
updated: 2026-09-10T13:03:47.506Z
order: a0
board: product
claim:
  actor: codex
  session: 01MTVJGENI03T8OOD0
  claimed_at: 2026-09-10T13:03:47.502Z
  expires_at: 2026-09-10T14:03:47.502Z
  branch: main
branch: main
---

## Objective

Keep MIT as Kromora's source-code license while clearly separating the product's name, logo, app
icon, and visual identity from the code license.

## Context

Kromora began as a fork of the MIT-licensed LUTzy project and now has an original product name and
visual identity. MIT is appropriate for broad code reuse, but the repository should not imply that a
modified fork may present itself as an official Kromora release. The project does not claim a
registered trademark; this ticket documents a practical branding policy without using a registration
symbol or making a registration claim.

The copyright notice should preserve Tim's original copyright and acknowledge Daniel Hardy's later
contributions. This is subject to correction if a separate assignment or work-for-hire agreement
establishes different ownership.

## Acceptance criteria

- [x] Keep the MIT license for the source code and preserve the original copyright notice.
- [x] Update the copyright notice to include the verified copyright holders for the original and
      later contributions.
- [x] Add a clearly named branding policy covering the Kromora name, word mark, logo, app icon, and
      related visual identity, without claiming federal trademark registration.
- [x] State that modified forks must not imply official Kromora endorsement and should use their own
      product name and visual identity; permit attribution to the upstream project.
- [x] Update the README and icon documentation so the code license and branding policy do not conflict.
- [x] Run `dg validate` and `git diff --check`.

## Implementation notes

Use `BRANDING.md` for the policy and link it from `README.md` and `docs/KROMORA_ICON.md`. Do not add
`TM` or `®` claims. Keep the policy limited to use of the Kromora identity; it must not restrict the
MIT rights to copy, modify, or distribute the code.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
