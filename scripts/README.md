# Script lifecycle

The scripts in this directory are the supported entry points for CI, packaging, and opt-in local
measurements. Current requirements and verification limits are summarized in
[`docs/TESTING.md`](../docs/TESTING.md) and [`docs/PACKAGING.md`](../docs/PACKAGING.md).

| Lifecycle | Script | Purpose | Requirements / inputs |
| --- | --- | --- | --- |
| Active | `agent-worktree.sh` | Create or remove an isolated agent worktree | Git checkout; used by agent workflow documentation |
| Active | `app-store-build.sh` | Build and verify the production Xcode app, or create `.build/xcode/Kromora.xcarchive` for Xcode Organizer | Xcode 27+ / macOS 27 SDK; archive uses `DEVELOPMENT_TEAM` when set, otherwise the single local team, or the Apple Distribution team when a personal team is also installed; signs with Apple Development |
| Active | `disposable-app.sh` | Launch the unsandboxed development app on an APFS clone of a library package with its own preferences (`start <package>`, `stop`, `status`), so live UI checks never touch the personal library | macOS UI session, SwiftPM Release build; honors `KROMORA_LIBRARY_PACKAGE` |
| Active | `check-swift-format.sh` | Check changed Swift files against `.swift-format` | macOS Swift toolchain; optional `SWIFT_FORMAT_BASE` |
| Active | `ci-tests.sh` | Enforce the zero-warning build and run the deterministic, serial render/UI, or optional test lane | Xcode 27+ / macOS 27 SDK; optional lane needs the documented `KROMORA_*` fixtures/settings |
| Opt-in | `auto-evaluation-report.sh` | Render a gradient fixture unchanged versus a +1 EV Auto proposal through the real `RenderEngine` and write PNG/JSON/Markdown evidence to the gitignored `artifacts/auto-evaluation/` | Release-capable build; optional output directory argument |
| Opt-in | `auto-quality-report.sh` | Run the Auto quality corpus (deterministic policy lane plus the actual-render lane) and write per-fixture evidence to the gitignored `artifacts/auto-quality/` | Optional output directory argument |
| Active | `build-metal-libraries.sh` | Rebuild the checked-in precompiled Metal libraries from their `.metal` sources and record a source checksum beside each | Xcode Metal toolchain; rerun after editing any `.metal` source |
| Opt-in | `photo-intelligence-derive.swift` | Derive a gain/contrast variant of a corpus JPEG for the photo-intelligence fixtures | `<input.jpg> <output.jpg> <linear-gain> [linear-contrast]` |
| Opt-in | `photo-intelligence-report.sh` | Generate the photo-intelligence corpus report | Photo-intelligence test fixtures; optional `KROMORA_PHOTO_INTELLIGENCE_REPORT_PATH` |
| Opt-in | `run-kromora-capture.sh` | Run a Release `xctrace` capture for `metal-presentation`, `concurrent-export-editing`, or `last-known-frame` | macOS, logged-in display, `xctrace`/`xctest`, and a licensed RAW fixture; use `--benchmark` and optionally `--source` |
| Active | `smoke-macos-app.sh` | Exercise launch, Open, Settings, and Export through the packaged app | Xcode-built `.build/xcode/Build/Products/Release/Kromora.app`, macOS UI session, accessible WindowServer; exits 2 when hosted UI is unavailable |
| Active | `verify-app-icon.sh` | Verify Icon Composer inputs and packaged icon/resource outputs | Xcode-built `.build/xcode/Build/Products/Release/Kromora.app`, Icon Composer asset, Python 3 |
| Active | `verify-app-signature.sh` | Verify the app signature and expected entitlements | Xcode-built `.build/xcode/Build/Products/Release/Kromora.app`, `codesign`, Python 3 |
| Active | `verify-xcode-app.sh` | Verify the built app's identity, metadata, packaged resources, signature, and icon | Xcode-built `.build/xcode/Build/Products/Release/Kromora.app`, Swift, Python 3 |
| Active | `verify-library-package-metadata.sh` | Verify the `.kromoralibrary` UTI declaration, absent Finder document type, and the exact sandbox entitlement set | Source plist files, Python 3 |

Kromora is distributed through the Mac App Store, with prerelease builds tested through TestFlight;
developers can build the source with SwiftPM. Xcode Organizer handles archive validation and the
interactive App Store Connect upload. Distribution requires the configured App Store signing assets
and account access; there is no automated upload script. See [`docs/PACKAGING.md`](../docs/PACKAGING.md)
for the full release workflow.

The capture wrapper replaces the former issue-specific wrappers. Use explicit benchmark modes so the
benchmark filter and environment are visible at the call site:

```sh
scripts/run-kromora-capture.sh --benchmark metal-presentation \
  --source /absolute/path/to/fixtures/DSC07826.ARW

scripts/run-kromora-capture.sh --benchmark concurrent-export-editing \
  --source /absolute/path/to/fixtures/DSC07826.ARW \
  --items 6 --gestures 10

scripts/run-kromora-capture.sh --benchmark last-known-frame \
  --source /absolute/path/to/fixtures/DSC01019.ARW --iterations 5
```
