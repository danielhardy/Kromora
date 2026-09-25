---
id: KRMA-578
title: "About dialog: show app version, developer credits, and license"
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: About dialog contains Kromora's name, version, developer/author attribution, and MIT license information
      result: pass
    - criterion: Displayed version/build values come from bundle metadata rather than duplicated hard-coded strings
      result: pass
      notes: KromoraAboutMetadata reads CFBundleShortVersionString/CFBundleVersion from Bundle.main.infoDictionary
    - criterion: Developer and original-project credits are consistent with LICENSE and README.md
      result: pass
      notes: Attribution to Daniel Hardy and LUTzy/tsvb matches LICENSE copyright lines and README fork note
    - criterion: Full license is available in the packaged application or through a reliable in-app link
      result: pass
      notes: LICENSE.txt is byte-identical to root LICENSE, packaged via .copy("Resources"), rendered in full plus a canonical source Link
    - criterion: Development runs without packaged metadata fail gracefully and still identify the app and its license
      result: pass
      notes: Fallback strings 'Development build' / 'Unavailable in development build' cover missing or blank Info.plist values; bundled LICENSE.txt still resolves via KromoraKitResourceBundle fallback search
    - criterion: About remains available in expected App menu in both direct-distribution and dev configs; existing update command remains intact
      result: pass
      notes: "CommandGroup(replacing: .appInfo) is unconditional; Check for Updates stays under the existing KROMORA_DIRECT_DISTRIBUTION-gated CommandGroup(after: .appInfo)"
    - criterion: VoiceOver can identify the dialog contents and activate any license/source links
      result: pass
      notes: Header trait, accessibilityLabel on version line, license text, and Link elements are standard SwiftUI accessible controls
  checks_run:
    - swift build
    - KROMORA_DIRECT_DISTRIBUTION=1 swift build
    - swift test --filter KromoraAboutTests (4 passed)
    - git diff --check a8bf66c~1..a8bf66c -- Sources Tests
    - "manual diff: LICENSE vs Sources/KromoraKit/Resources/LICENSE.txt (byte-identical)"
    - "manual review: no @unchecked Sendable / nonisolated(unsafe) / @preconcurrency introduced"
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-25T06:04:43.847Z
  session: 01MUGK1IQYP3HFHKDK
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - ui
  - metadata
  - documentation
created: 2026-09-25T02:42:40.438Z
updated: 2026-09-25T06:04:43.849Z
blockers: []
order: a0
board: product
---

## Objective

Make the About Kromora dialog a useful source for the running app’s version, developer attribution, and license. Keep the entry in the normal macOS App menu and present information from the project’s existing metadata and license sources.

## Investigation findings

- The app currently uses SwiftUI/macOS’s standard About item; there is no custom About view or `showAbout` implementation.
- `Sources/KromoraKit/Views/MenuCommands.swift` only adds “Check for Updates…” after `.appInfo` for direct-distribution builds.
- `Sources/Kromora/Info.plist` defines `CFBundleShortVersionString` (`0.1`) and `CFBundleVersion` (`1`), which can supply version and build information.
- `Sources/KromoraKit/Models/AppVersion.swift` reads the packaged app version for the updater under `KROMORA_DIRECT_DISTRIBUTION`; the About experience should work for all app builds, including development builds without bundle metadata.
- The root `LICENSE` is MIT and carries the copyright attribution. The `README.md` documents Kromora’s LUTzy fork origin and retained attribution. Use these sources for developer/author credits and license text rather than inventing new attribution.

## Expected behavior

- About Kromora is reachable through the App menu.
- The dialog shows the app version and build number from bundle metadata when available, with a clear development-build fallback when it is not.
- The dialog identifies the developer/author using repository attribution, including the retained original-project attribution where appropriate.
- The dialog identifies the MIT license and lets users read the complete license text or open the canonical license source.
- Text and links are accessible and remain usable at ordinary window sizes; long license text can scroll or open in a separate readable view.

## Acceptance criteria

- The About dialog contains Kromora’s name, version, developer/author attribution, and MIT license information.
- Displayed version/build values come from bundle metadata rather than duplicated hard-coded strings.
- Developer and original-project credits are consistent with `LICENSE` and `README.md`.
- The full license is available in the packaged application or through a reliable in-app link; the dialog does not show only the word “MIT” without a way to read the terms.
- Development runs without packaged metadata fail gracefully and still identify the app and its license.
- About remains available in the expected App menu in both direct-distribution and development configurations; the existing update command remains intact.
- VoiceOver can identify the dialog contents and activate any license/source links.

## Implementation notes

- Menu integration: `Sources/KromoraKit/Views/MenuCommands.swift` and, if needed, the app entry point in `Sources/Kromora/KromoraApp.swift`.
- Bundle metadata: `Sources/Kromora/Info.plist`; version helper: `Sources/KromoraKit/Models/AppVersion.swift`.
- Canonical license and attribution: root `LICENSE` and `README.md`.
- Avoid coupling About presentation to updater-only compilation conditions.

## Tests and verification

- Add focused coverage for version/build formatting and the development-metadata fallback.
- Verify the license resource/text is present and readable in the packaged app path.
- Verify menu integration without requiring a full interactive window where existing test seams allow it.
- `swift build`
- Run relevant About/menu/app-metadata tests.
- `git diff --check`

## Out of scope

- Settings or a full application information/credits site.
- Changing project copyright or license terms.
- Changing updater behavior or bundle versioning policy.


### Comment — codex @ 2026-09-25T06:03:15.158Z

Implemented and committed as a8bf66c. Added a SwiftUI About window in the App menu with bundle-sourced version/build and development fallbacks, Daniel Hardy and retained LUTzy attribution, and the complete packaged MIT license with source links. Verified with swift build, KROMORA_DIRECT_DISTRIBUTION=1 swift build, swift test --filter KromoraAboutTests (4 passed), and git diff --check.

## Agent log

- 2026-09-25T06:04:43.848Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] About dialog contains Kromora's name, version, developer/author attribution, and MIT license information (pass)
- [x] Displayed version/build values come from bundle metadata rather than duplicated hard-coded strings (pass) — KromoraAboutMetadata reads CFBundleShortVersionString/CFBundleVersion from Bundle.main.infoDictionary
- [x] Developer and original-project credits are consistent with LICENSE and README.md (pass) — Attribution to Daniel Hardy and LUTzy/tsvb matches LICENSE copyright lines and README fork note
- [x] Full license is available in the packaged application or through a reliable in-app link (pass) — LICENSE.txt is byte-identical to root LICENSE, packaged via .copy("Resources"), rendered in full plus a canonical source Link
- [x] Development runs without packaged metadata fail gracefully and still identify the app and its license (pass) — Fallback strings 'Development build' / 'Unavailable in development build' cover missing or blank Info.plist values; bundled LICENSE.txt still resolves via KromoraKitResourceBundle fallback search
- [x] About remains available in expected App menu in both direct-distribution and dev configs; existing update command remains intact (pass) — CommandGroup(replacing: .appInfo) is unconditional; Check for Updates stays under the existing KROMORA_DIRECT_DISTRIBUTION-gated CommandGroup(after: .appInfo)
- [x] VoiceOver can identify the dialog contents and activate any license/source links (pass) — Header trait, accessibilityLabel on version line, license text, and Link elements are standard SwiftUI accessible controls
Checks run:
- swift build
- KROMORA_DIRECT_DISTRIBUTION=1 swift build
- swift test --filter KromoraAboutTests (4 passed)
- git diff --check a8bf66c~1..a8bf66c -- Sources Tests
- manual diff: LICENSE vs Sources/KromoraKit/Resources/LICENSE.txt (byte-identical)
- manual review: no @unchecked Sendable / nonisolated(unsafe) / @preconcurrency introduced
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUGK1IQYP3HFHKDK
Summary: Verified About window: bundle-sourced version/build with development fallbacks, LICENSE.txt byte-identical to root LICENSE and packaged via SwiftPM resources, attribution consistent with LICENSE/README, About menu item unconditional and Check for Updates preserved. swift build (both configs) and swift test --filter KromoraAboutTests (4/4) pass; git diff --check clean.
