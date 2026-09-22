# Script lifecycle

The scripts in this directory are the supported entry points for CI, packaging, and opt-in local
measurements. Current requirements and verification limits are summarized in
[`docs/TESTING.md`](../docs/TESTING.md) and [`docs/PACKAGING.md`](../docs/PACKAGING.md).

| Lifecycle | Script | Purpose | Requirements / inputs |
| --- | --- | --- | --- |
| Active | `agent-worktree.sh` | Create or remove an isolated agent worktree | Git checkout; used by agent workflow documentation |
| Active | `build-macos-app.sh` | Build and sign the distributable macOS app bundle | macOS 26 SDK, SwiftPM, `xcrun actool`, signing identity or ad-hoc signing |
| Active | `release-dmg.sh` | Build a universal, signed, notarized, stapled DMG (or a local skip-notarize dry run) | macOS, SwiftPM, Developer ID identity, `notarytool` keychain profile for distribution |
| Active | `check-swift-format.sh` | Check changed Swift files against `.swift-format` | macOS Swift toolchain; optional `SWIFT_FORMAT_BASE` |
| Active | `ci-tests.sh` | Enforce the zero-warning build and run the deterministic, serial render/UI, or optional test lane | macOS 26 SDK; optional lane needs the documented `KROMORA_*` fixtures/settings |
| Opt-in | `photo-intelligence-report.sh` | Generate the photo-intelligence corpus report | Photo-intelligence test fixtures; optional `KROMORA_PHOTO_INTELLIGENCE_REPORT_PATH` |
| Opt-in | `run-kromora-capture.sh` | Run a Release `xctrace` capture for `metal-presentation` or `concurrent-export-editing` | macOS, logged-in display, `xctrace`/`xctest`, and a licensed RAW fixture; use `--benchmark` and optionally `--source` |
| Active | `smoke-macos-app.sh` | Exercise launch, Open, Settings, and Export through the packaged app | Built `.build/Kromora.app`, macOS UI session, accessible WindowServer; exits 2 when hosted UI is unavailable |
| Active | `verify-app-icon.sh` | Verify Icon Composer inputs and packaged icon/resource outputs | Built `.build/Kromora.app`, Icon Composer asset, Python 3 |
| Active | `verify-app-signature.sh` | Verify the app signature and expected entitlements | Built `.build/Kromora.app`, `codesign`, Python 3 |
| Active | `verify-library-package-metadata.sh` | Verify the `.kromoralibrary` document/UTI declaration and Pictures entitlement | Source plist files, Python 3 |

The capture wrapper replaces the former issue-specific wrappers. Use explicit benchmark modes so the
benchmark filter and environment are visible at the call site:

```sh
scripts/run-kromora-capture.sh --benchmark metal-presentation \
  --source /absolute/path/to/fixtures/DSC07826.ARW

scripts/run-kromora-capture.sh --benchmark concurrent-export-editing \
  --source /absolute/path/to/fixtures/DSC07826.ARW \
  --items 6 --gestures 10
```
