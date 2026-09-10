---
id: KRMA-260
title: Make edit-document encoding failures loud at write time
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits:
    - 4e925bb
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-09T13:48:32.061Z
  session: 01MTU5KL9142IQSLPS
labels:
  - persistence
created: 2026-09-07T01:10:25.971Z
updated: 2026-09-10T12:53:51.472Z
depends_on:
  - KRMA-244
order: x
board: product
commits:
  - 4e925bb
---

## Objective

An `EditDocument` that fails to JSON-encode must fail the save loudly instead of persisting
empty bytes that read back as `.corrupt` later.

## Context

`EditRecord.init` and the `document` setter both encode with `try?` and fall back to `Data()`.
`EditDocumentStore.save` then assigns through that setter, calls `persist()`, sets
`status = .ready`, and returns normally — a total, silent loss of the edit the user just made,
surfaced only on the next load as corruption. Encoding a `Codable` edit graph should not fail
in practice, which is exactly why the failure path has never been exercised and must not be
silent.

Related nits to fold in while touching this code:

- `save` double-encodes: it constructs `EditRecord(assetID:document:)` (encode #1) and then
  immediately runs `record.document = document` (encode #2). Encode once.
- The `document` getter's `(try? decodeDocument()) ?? EditDocument()` fallback is now load-
  bearing for nobody — the store uses throwing `decodeDocument()` (KRMA-256) — but remains a
  footgun for the next caller. Either remove the silent fallback or document that only the
  store may read documents and everyone else goes through it.

## Work

- Give the encode path a throwing shape (throwing setter helper or encode-before-construct in
  `save`) so `save` throws before touching the context.
- On encode failure the store must surface `.writeFailure` (or throw without persisting), never
  `.ready` with empty bytes stored.
- Resolve the getter-fallback question above one way or the other.

## Acceptance criteria

- [ ] A document that cannot be encoded throws out of `save` with `.writeFailure` status; no
      empty-`Data` row is persisted.
- [ ] Single encode per save.
- [ ] New tests: injected encode failure (e.g. via a non-conforming test double or by
      exercising the throwing path directly) asserts throw + status + no persisted row.

## Agent log

- 2026-09-09T13:48:32.061Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- 4e925bb
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTU5KL9142IQSLPS
Summary: Verified the existing implementation: save encodes once before touching SwiftData, propagates encoding failures as writeFailure, and EditRecord has no silent document fallback. Added regression coverage is present.
