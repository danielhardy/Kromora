---
id: KRMA-768
title: Make frame writes survive an abrupt quit (Xcode Stop, crash, force quit)
type: task
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - performance
  - cache
  - reliability
created: 2026-10-02T13:44:24.216Z
updated: 2026-10-03T19:17:47.734Z
depends_on:
  - KRMA-778
  - KRMA-779
  - KRMA-780
blockers: []
order: zw
board: product
---

## Objective

Track the bounded loss window and crash-safe persistence of settled preview and thumbnail frames across graceful termination and abrupt process death.

## Role of this issue

This is a tracking parent. Implementation and focused verification live in these independent child tickets:

- [KRMA-778](KRMA-778.md) — flush both frame stores on graceful termination.
- [KRMA-779](KRMA-779.md) — bound pending packed-thumbnail writes and index rewrite cost.
- [KRMA-780](KRMA-780.md) — bound and make per-asset preview-frame writes crash-safe.

KRMA-768 remains in backlog as an umbrella while any child is unfinished; it is not an implementation pickup. Its dependencies on the children encode the aggregate completion condition.

## Acceptance criteria

- [ ] KRMA-778, KRMA-779, and KRMA-780 are complete and verified.
- [ ] `docs/STORAGE_POLICY.md` and `docs/TESTING.md` describe both frame-store bounds and graceful termination behavior consistently.
- [ ] The full `fast` and `serial` lanes pass after the child changes are integrated.

## Shared constraints

- Do not run display-bound captures for these children; deterministic store and lifecycle tests are sufficient.
- Cache files are disposable presentation caches, never package truth. A cache failure must degrade to a miss, never to a wrong-photo frame, package error, or blocked open.
- Use Swift 6 with no escape hatches, macOS 26+ on Apple Silicon, and no third-party dependencies.
- Each implementation commit starts with its child issue ID. Do not push or disturb unrelated working-tree changes.
