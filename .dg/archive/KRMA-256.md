---
id: KRMA-256
title: EditRecord.document silently drops corrupt/undecodable edits without surfacing status
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Undecodable EditRecord documentData is surfaced through an actionable corrupt status instead of appearing ready
      result: pass
    - criterion: Corrupt rows return neutral edits without being mistaken for a missing record
      result: pass
    - criterion: Normal decode, relink, and existing status behavior remain covered
      result: pass
  checks_run:
    - swift test --filter EditDocumentStoreTests — 10 passed, 0 failures
    - swift test — 920 executed, 41 skipped, 0 failures
    - git diff --check — passed
    - dg validate — OK; existing unrelated warnings
  findings: []
  fixes:
    - Added a throwing EditRecord decode path and EditDocumentStore.Status.corrupt(String); load reports corrupt rows as found with identity fallback and actionable messaging.
  verification_commits:
    - d704cc5
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-07T00:42:07.746Z
  session: 01MTQI84TEA4K3EE6K
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-06T23:21:12.777Z
updated: 2026-09-10T12:53:51.129Z
depends_on:
  - KRMA-244
order: m15gzpj9
board: product
commits:
  - d704cc5
---

## Finding (verification of KRMA-244 / commit c2b7851)

`EditRecord.document` (Sources/LumoKit/Models/EditRecord.swift:15-18) silently falls back to
`EditDocument()` (the identity document) whenever `documentData` fails to decode:

```swift
var document: EditDocument {
    get { (try? JSONDecoder().decode(EditDocument.self, from: documentData)) ?? EditDocument() }
    ...
}
```

The JSON-catalog store this replaces treated an undecodable record as `.corrupt(...)`, an
actionable `Status` surfaced to the caller (`EditDocumentStore.Status.corrupt`, removed in
c2b7851). The SwiftData store has no equivalent path: a row whose `documentData` blob cannot be
decoded (bit rot, a future non-additive schema change to `EditDocument`, partial write recovered
by SQLite's own journal) is read back as silently-blank edits with `status == .ready`, so the
caller cannot distinguish "no edits" from "edits could not be read." This is a quiet-data-loss
risk this epic did not need to introduce, even though there is no migration path from the old
format.

Not a blocker: the epic's stated definition of done (round-trip, relink, coalescing, failure
injection) does not require this signal, and the current fully-passing test suite doesn't exercise
a corrupt-blob case. But it's worth tracking as a small follow-up: have the `document` getter (or
`EditDocumentStore.load`) surface a decode failure through `Status`, mirroring the old
`.corrupt` case, rather than swallowing it via `try?`.

## Agent log

- 2026-09-07T00:42:07.751Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Undecodable EditRecord documentData is surfaced through an actionable corrupt status instead of appearing ready (pass)
- [x] Corrupt rows return neutral edits without being mistaken for a missing record (pass)
- [x] Normal decode, relink, and existing status behavior remain covered (pass)
Checks run:
- swift test --filter EditDocumentStoreTests — 10 passed, 0 failures
- swift test — 920 executed, 41 skipped, 0 failures
- git diff --check — passed
- dg validate — OK; existing unrelated warnings
Findings:
- None
Fixes:
- Added a throwing EditRecord decode path and EditDocumentStore.Status.corrupt(String); load reports corrupt rows as found with identity fallback and actionable messaging.
Verification commits:
- d704cc5
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTQI84TEA4K3EE6K
Summary: Surface corrupt SwiftData edit records as actionable load status while retaining neutral-edit fallback.
