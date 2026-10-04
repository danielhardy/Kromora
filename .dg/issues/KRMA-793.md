---
id: KRMA-793
title: Move Info.plist, entitlements, assets, and branding into a top-level App/ folder
type: task
status: ready
priority: high
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - packaging
  - layout
created: 2026-10-03T19:24:24.419Z
updated: 2026-10-03T19:25:47.623Z
depends_on:
  - KRMA-790
  - KRMA-792
blockers: []
order: zz
board: product
---

## Objective

Give production packaging inputs their planned home in `App/`, leaving `Sources/Kromora/` with only the SwiftPM launcher.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, "Target repository layout"). Today `Sources/Kromora/` holds `Info.plist`, `Kromora.entitlements`, `Assets.xcassets`, `Branding/KromoraIcon.svg`, and `KromoraApp.swift`; `Package.swift` excludes the first four from the executable target (`exclude: ["Assets.xcassets", "Branding", "Info.plist", "Kromora.entitlements"]`). Paths are referenced by `scripts/build-macos-app.sh`, `scripts/verify-library-package-metadata.sh`, `scripts/smoke-macos-app.sh` (`Sources/Kromora/Branding/KromoraIcon.svg`), `docs/PACKAGING.md`, `CLAUDE.md`, `scripts/README.md`, and possibly tests (`grep -rn "Sources/Kromora/" scripts docs Tests CLAUDE.md README.md .github Package.swift`). `Kromora.icon` (Icon Composer) and `BRANDING.md` stay at the repository root.

## Scope

- `git mv` `Info.plist`, `Kromora.entitlements`, `Assets.xcassets`, and `Branding` from `Sources/Kromora/` to `App/` (keep file names).
- Remove the now-empty `exclude:` list from the `Kromora` executable target in `Package.swift` and update its comment to say packaging inputs live in `App/`.
- Update every path reference found by the grep above. The `Sources/Kromora/KromoraApp.swift` launcher itself does not move.
- Update the `CLAUDE.md` Layout bullet for `Sources/Kromora/` and add an `App/` bullet: production packaging inputs only, no Swift implementation.

## Acceptance criteria

- [ ] `Sources/Kromora/` contains only `KromoraApp.swift`; `App/` contains the moved four items.
- [ ] `grep -rn "Sources/Kromora/\(Info.plist\|Kromora.entitlements\|Assets.xcassets\|Branding\)" .` (excluding `.dg/`, `.context/`, `.build/`, `.git/`) returns nothing.
- [ ] `swift build` shows no "unhandled resource" warning for the `Kromora` target, and `scripts/ci-tests.sh warning-gate` passes.
- [ ] `scripts/build-macos-app.sh`, `scripts/verify-app-icon.sh`, `scripts/verify-app-signature.sh`, and `scripts/verify-library-package-metadata.sh` pass; `scripts/ci-tests.sh fast` passes.

## Verification

- Run the grep, `swift build`, the four scripts in order, and `scripts/ci-tests.sh fast`.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
