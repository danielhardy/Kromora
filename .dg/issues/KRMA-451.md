---
id: KRMA-451
title: Add zero-dependency GitHub Releases auto-update with signature verification
type: feature
status: ready
priority: high
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - packaging
  - release
  - updater
  - security
created: 2026-09-18T22:38:54.334Z
updated: 2026-09-18T22:40:12.543Z
depends_on:
  - KRMA-450
order: y
board: product
---

## Objective

Add a zero-third-party-dependency in-app updater that checks GitHub Releases for a newer Kromora version, offers notes + install, downloads the release DMG, verifies Developer ID signature against the running app's Team ID + bundle ID, swaps the bundle in place, and relaunches — with a testable coordinator and a Settings/menu entry.

## Dependencies

- **KRMA-450** — signed/notarized DMG release packaging must define the artifact shape (DMG containing `Kromora.app`) and ideally the skip-notarize local test path. Do not implement installer assumptions that disagree with that script.

## Context

### Current state

- No Sparkle, no update check, no `Check for Updates…` command.
- Packaging today stops at `scripts/build-macos-app.sh` / Xcode Archive docs (`docs/PACKAGING.md`).
- Product constraint from CLAUDE.md: **zero third-party dependencies** — Sparkle is out.

### Upstream reference (adapt to Kromora)

LUTzy PR #40 (`8349826`, follow-ups `11b01ff`, `692713c`) on `tsvb/lutzy`:

- `ReleaseFeed` — unauthenticated `GET /repos/{owner}/{repo}/releases/latest`, pick DMG by extension
- `UpdateCoordinator` — automatic daily check (quiet) vs manual check (reports all outcomes); skip-version support
- `UpdateInstaller` — download DMG → `hdiutil` mount → **codesign requirement check** (Apple anchor, same Team ID, same bundle ID, strict/nested) → same-volume rename swap → relaunch via `open` after terminate
- `UpdateSheet` + Settings/menu wiring
- `UpdateTests` with injected feed/install closures (no network in CI)
- Unsigned `swift run` builds cannot install in-place (no Team ID) — sheet falls back to opening the release page

View with:
- `git show upstream/main:Sources/LUTzyKit/ViewModels/UpdateCoordinator.swift`
- `git show upstream/main:Sources/LUTzyKit/Models/UpdateInstaller.swift`
- `git show upstream/main:Sources/LUTzyKit/Models/ReleaseFeed.swift`

### Product constraints

- macOS 14+, Swift 6, no `@unchecked Sendable` / `nonisolated(unsafe)` / `@preconcurrency`.
- Network access for update checks requires an explicit entitlement / App Sandbox exception — add the **minimum** client outbound entitlement and document it in `docs/PACKAGING.md` + entitlements file comments.
- Never install a download that fails signature verification, regardless of what the feed said.
- Automatic checks must be quiet on failure (offline laptops); manual checks must surface errors.
- Do not phone home beyond GitHub Releases API + the release asset URL.

## Acceptance criteria

- [ ] Menu command **Check for Updates…** (and optional Settings affordance) runs a manual check and presents: up to date, update available (notes + version), skipped-but-newer, or error.
- [ ] An automatic check may run at launch at most once per 24h (or documented interval), stays silent unless a newer non-skipped release exists, and never alerts solely because the network failed.
- [ ] User can skip a specific version; skipped versions suppress automatic prompts until a newer tag appears.
- [ ] When the running app is Developer ID–signed, **Install and Relaunch** downloads the DMG, mounts read-only, verifies the embedded app's signature against the running app's Team ID + bundle ID, swaps on the same volume, and relaunches.
- [ ] When the running app is unsigned (e.g. `swift run`) or verification fails, the UI offers the release page / discards the download and does **not** swap binaries.
- [ ] Feed parsing, phase machine, and installer seams are injected so unit tests cover success, up-to-date, skip, bad tag, missing DMG, signature rejection, and unsigned-running-app paths without network or mutating `/Applications`.
- [ ] Logging (e.g. `os.Logger` subsystem for Kromora updates) records check/install steps for field diagnosis without dumping secrets.
- [ ] Entitlements + packaging docs updated for outbound HTTPS to `api.github.com` and GitHub asset hosts as needed.
- [ ] Repository / bundle identifiers in the feed default to Kromora's GitHub repo (`danielhardy/Kromora` or the configured origin), not `tsvb/lutzy`.

## Out of scope

- Implementing the DMG build script itself (KRMA-450).
- Delta/patch updates, beta channels, or Sparkle appcasts.
- Force-updating or killing in-progress edits without a clear “Install and Relaunch” confirmation.
- Windows/Linux (macOS only).

## Implementation notes

1. Keep types in `KromoraKit` with thin app-target wiring for menu/Settings (same pattern as other coordinators owned by `AppViewModel`).
2. Prefer `@MainActor` coordinator + `Sendable` value models; `Sec*` / `NSWorkspace` work stays in an installer type that tests can replace.
3. Terminate/relaunch: if `NSApp.terminate` is ignored (upstream `11b01ff`), dismiss UI and exit explicitly so the swap is not left half-done.
4. Security bar: signature requirement string must be built from the **running** app, not hard-coded Team IDs in source beyond what's read from the code signature at runtime.
5. Do not merge LUTzy files verbatim — re-implement against Kromora naming, logging, and settings store (`KromoraSettings`).

## Verification

- Focused `UpdateTests` (or equivalent) green.
- `swift build`
- Manual dry-run only on a signed local build with KRMA-450 skip-notarize DMG if credentials allow; otherwise document and rely on injected installer tests.
- `git diff --check`; update `docs/PACKAGING.md`.

### Comment — cursor @ 2026-09-18T22:40:12.542Z

Provenance: adapt LUTzy zero-dep updater (PR #40). Blocked on KRMA-450 for DMG artifact shape. Security bar is runtime Team ID + bundle ID codesign verification before swap — never Sparkle, never install unverified downloads.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
