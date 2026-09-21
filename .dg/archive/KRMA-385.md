---
id: KRMA-385
title: Remove MIT license information from the Looks panel
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The Looks panel no longer displays the MIT license information.
      result: pass
      notes: manifest.json acknowledgement string no longer references the Kromora MIT License; LookInspectorView.starterAcknowledgement renders this string verbatim.
    - criterion: The panel layout remains clean and correctly spaced after removal.
      result: pass
      notes: Only the license clause was removed from the sentence; no layout/padding code was touched, and the shortened text still reads as a complete sentence.
    - criterion: No unrelated licensing notices or required attribution are removed.
      result: pass
      notes: Read-only/no-third-party-attribution/descriptive-inspiration guidance retained in the acknowledgement; LUTzy MIT attribution in README.md/LICENSE and BundledLookLibrary.validateProvenance license-gate string are unrelated to the panel and were correctly left untouched.
  checks_run:
    - swift build
    - swift test --filter BundledLookTests
  findings: []
  fixes: []
  verification_commits:
    - 4bb85e4ffe5fba7e372afca6adf1e7f46932a857
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-12T18:33:28.315Z
  session: 01MTYQ2S1QTBC0VLM7
created: 2026-09-12T16:16:27.668Z
updated: 2026-09-12T18:33:28.317Z
order: a0
board: product
commits:
  - 4bb85e4ffe5fba7e372afca6adf1e7f46932a857
---

## Objective

Remove the MIT license information currently displayed in the Looks panel.

## Acceptance criteria

- [ ] The Looks panel no longer displays the MIT license information.
- [ ] The panel layout remains clean and correctly spaced after removal.
- [ ] No unrelated licensing notices or required attribution are removed.

## Implementation notes

<!-- Identify the source of the panel text and confirm whether any attribution is required elsewhere. -->

### Comment — codex @ 2026-09-12T18:32:20.720Z

Implemented and verified: removed the MIT-license wording from the Looks-panel starter acknowledgement while retaining the original-assets, read-only, no-third-party-attribution, and descriptive-inspiration guidance. Added a regression assertion that the displayed acknowledgement contains no MIT wording. Checks passed: swift test --filter BundledLookTests; swift test --filter LookInspectorViewTests; swift build; dg validate; git diff --check. Commit: 4bb85e4.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-12T18:33:28.315Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The Looks panel no longer displays the MIT license information. (pass) — manifest.json acknowledgement string no longer references the Kromora MIT License; LookInspectorView.starterAcknowledgement renders this string verbatim.
- [x] The panel layout remains clean and correctly spaced after removal. (pass) — Only the license clause was removed from the sentence; no layout/padding code was touched, and the shortened text still reads as a complete sentence.
- [x] No unrelated licensing notices or required attribution are removed. (pass) — Read-only/no-third-party-attribution/descriptive-inspiration guidance retained in the acknowledgement; LUTzy MIT attribution in README.md/LICENSE and BundledLookLibrary.validateProvenance license-gate string are unrelated to the panel and were correctly left untouched.
Checks run:
- swift build
- swift test --filter BundledLookTests
Findings:
- None
Fixes:
- None
Verification commits:
- 4bb85e4ffe5fba7e372afca6adf1e7f46932a857
Actor: claude
Resolved model: sonnet
Pickup session: 01MTYQ2S1QTBC0VLM7
Summary: Verified: MIT license wording removed from Looks-panel acknowledgement; unrelated attribution/licensing untouched; regression test added; build and targeted tests pass.
