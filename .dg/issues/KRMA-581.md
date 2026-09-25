---
id: KRMA-581
title: Move bundled Look license and attribution disclosure out of the Looks tab
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The starter acknowledgement/license/attribution callout is no longer shown at the bottom of the Looks tab.
      result: pass
      notes: LookInspectorView no longer references bundledAcknowledgement or starterAcknowledgement; confirmed by grep and by testStarterLookDisclosureLivesInAboutAndNotTheLooksInspector.
    - criterion: Required license, attribution, and redistribution information remains accessible elsewhere in the app or through a clear link to that information; it is not deleted from the starter Look manifest or validation path.
      result: pass
      notes: Moved into KromoraAboutView's new 'Bundled Starter Looks' GroupBox, listing acknowledgement plus per-Look license/attribution/redistribution. Manifest and BundledLookLibrary.validate() are unchanged.
    - criterion: If the About dialog in KRMA-578 is used as the destination, the disclosure is placed in an appropriate About/credits/license section and remains readable and accessible.
      result: pass
      notes: "Placed alongside the existing 'Developed by' and 'MIT License' GroupBoxes; uses textSelection and accessibilityElement(children: .combine) per entry."
    - criterion: Look browsing, starter Look read-only behavior, imported Looks, search, and intensity controls are unchanged.
      result: pass
      notes: Only the acknowledgement footer view/branch was removed from LookInspectorView; list, search, intensity, and unresolved-look sections are untouched. LookInspectorViewTests (grouping, empty-state matrix, rendered populated state) pass.
    - criterion: Tests cover the removed Looks-tab callout and preserve coverage for manifest provenance and license validation.
      result: pass
      notes: KromoraAboutTests.testStarterLookDisclosureLivesInAboutAndNotTheLooksInspector checks both the About content and the inspector's absence of the callout, plus re-validates manifest completeness. BundledLookTests provenance/validation tests are unchanged and pass.
  checks_run:
    - swift build
    - swift test --filter 'BundledLookTests|LookInspectorViewTests|KromoraAboutTests' (16 tests, 0 failures)
    - git diff --check
  findings:
    - "Performance: KromoraAboutView.init() called BundledLookLibrary.load(), which parses every bundled .cube LUT from disk, just to read manifest text fields (acknowledgement/license/attribution). Every About window open re-parsed all 13 starter LUT files redundantly with the load already done for the Look library, purely to display strings that live in the manifest, not the parsed LUT data."
  fixes:
    - Added BundledLookLibrary.loadManifestOnly() (Sources/KromoraKit/Models/BundledLookLibrary.swift) which reads and decodes only manifest.json, and switched KromoraAboutView.init() (Sources/KromoraKit/Views/KromoraAboutView.swift) to use it instead of load().manifest, avoiding unnecessary CubeLUT parsing on About window init. Verified with swift build and the BundledLookTests/KromoraAboutTests/LookInspectorViewTests suites (16/16 passing).
  verification_commits:
    - e41501e
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-25T10:04:17.829Z
  session: 01MUGSKYJ1YOK9YSGF
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - ui
  - looks
  - licensing
created: 2026-09-25T03:05:06.267Z
updated: 2026-09-25T10:04:17.831Z
blockers: []
order: a0
board: product
commits:
  - e41501e
---

## Objective

Remove the bundled Look license/attribution callout from the Looks tab. Keep required license and provenance information available elsewhere in the app, such as the About dialog or another appropriate credits/license surface.

## Investigation findings

- `LookInspectorView.body` renders `starterAcknowledgement` below the Look list when bundled starter Looks are present.
- The footer reads `viewModel.library.bundledAcknowledgement`, sourced from `Sources/KromoraKit/Resources/StarterLooks/manifest.json`.
- The current manifest acknowledgement says the starter Looks are original Kromora assets, read-only, and need no third-party attribution; it also clarifies that film/manufacturer references are descriptive inspiration only. The per-Look manifest entries separately retain author, source, license, attribution, redistribution, and approval records.
- `BundledLookLibrary` validates that provenance and license metadata. Removing a UI callout must not remove or weaken those records or checks.
- KRMA-578 tracks version, developer credits, and license information in the About dialog; that is a natural place to consider for this disclosure. A suitable non-Looks credits/license surface is also acceptable if it is a better fit.

## Acceptance criteria

- The starter acknowledgement/license/attribution callout is no longer shown at the bottom of the Looks tab.
- Required license, attribution, and redistribution information remains accessible elsewhere in the app or through a clear link to that information; it is not deleted from the starter Look manifest or validation path.
- If the About dialog in KRMA-578 is used as the destination, the disclosure is placed in an appropriate About/credits/license section and remains readable and accessible.
- Look browsing, starter Look read-only behavior, imported Looks, search, and intensity controls are unchanged.
- Tests cover the removed Looks-tab callout and preserve coverage for manifest provenance and license validation.

## Context

- Looks-tab disclosure: `Sources/KromoraKit/Views/LookInspectorView.swift` (`starterAcknowledgement`).
- Disclosure text: `Sources/KromoraKit/Resources/StarterLooks/manifest.json`.
- Provenance/license validation: `Sources/KromoraKit/Models/BundledLookLibrary.swift`.
- Relevant tests: `Tests/KromoraKitTests/BundledLookTests.swift` and `Tests/KromoraKitTests/LookInspectorViewTests.swift`.
- Possible destination: KRMA-578, About dialog version, developer credits, and license.

## Checks

- `swift build`
- Run `BundledLookTests` and relevant Look inspector tests.
- `git diff --check`

## Out of scope

- Changing license terms, starter Look assets, their provenance, or redistribution approvals.
- Redesigning the Looks tab or bundled Look library.


### Comment — codex @ 2026-09-25T10:02:21.902Z

Moved starter Look acknowledgement and per-Look license, attribution, and redistribution details into About > Bundled Starter Looks; removed the Looks-tab callout. Manifest data and validation remain intact. Checks: swift build; 16 focused BundledLook, About, and LookInspector tests; git diff --check. Commit: 0a71726.

## Agent log

- 2026-09-25T10:04:17.830Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The starter acknowledgement/license/attribution callout is no longer shown at the bottom of the Looks tab. (pass) — LookInspectorView no longer references bundledAcknowledgement or starterAcknowledgement; confirmed by grep and by testStarterLookDisclosureLivesInAboutAndNotTheLooksInspector.
- [x] Required license, attribution, and redistribution information remains accessible elsewhere in the app or through a clear link to that information; it is not deleted from the starter Look manifest or validation path. (pass) — Moved into KromoraAboutView's new 'Bundled Starter Looks' GroupBox, listing acknowledgement plus per-Look license/attribution/redistribution. Manifest and BundledLookLibrary.validate() are unchanged.
- [x] If the About dialog in KRMA-578 is used as the destination, the disclosure is placed in an appropriate About/credits/license section and remains readable and accessible. (pass) — Placed alongside the existing 'Developed by' and 'MIT License' GroupBoxes; uses textSelection and accessibilityElement(children: .combine) per entry.
- [x] Look browsing, starter Look read-only behavior, imported Looks, search, and intensity controls are unchanged. (pass) — Only the acknowledgement footer view/branch was removed from LookInspectorView; list, search, intensity, and unresolved-look sections are untouched. LookInspectorViewTests (grouping, empty-state matrix, rendered populated state) pass.
- [x] Tests cover the removed Looks-tab callout and preserve coverage for manifest provenance and license validation. (pass) — KromoraAboutTests.testStarterLookDisclosureLivesInAboutAndNotTheLooksInspector checks both the About content and the inspector's absence of the callout, plus re-validates manifest completeness. BundledLookTests provenance/validation tests are unchanged and pass.
Checks run:
- swift build
- swift test --filter 'BundledLookTests|LookInspectorViewTests|KromoraAboutTests' (16 tests, 0 failures)
- git diff --check
Findings:
- Performance: KromoraAboutView.init() called BundledLookLibrary.load(), which parses every bundled .cube LUT from disk, just to read manifest text fields (acknowledgement/license/attribution). Every About window open re-parsed all 13 starter LUT files redundantly with the load already done for the Look library, purely to display strings that live in the manifest, not the parsed LUT data.
Fixes:
- Added BundledLookLibrary.loadManifestOnly() (Sources/KromoraKit/Models/BundledLookLibrary.swift) which reads and decodes only manifest.json, and switched KromoraAboutView.init() (Sources/KromoraKit/Views/KromoraAboutView.swift) to use it instead of load().manifest, avoiding unnecessary CubeLUT parsing on About window init. Verified with swift build and the BundledLookTests/KromoraAboutTests/LookInspectorViewTests suites (16/16 passing).
Verification commits:
- e41501e
Actor: claude
Resolved model: sonnet
Pickup session: 01MUGSKYJ1YOK9YSGF
