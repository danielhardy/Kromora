# CLAUDE.md — project guidance for AI agents

Kromora targets **macOS 26 (Tahoe) and later on Apple Silicon only**. Prefer current-platform APIs and simplicity over backwards compatibility. Do not implement fallbacks for earlier macOS releases or Intel hardware. Focus on exceptional code quality using the modern API, and recommend current best practices.

Kromora is a native RAW photo editor (**Swift 6 language mode**, SwiftUI + Core Image, **zero third-party dependencies**) with a package-backed Library/Edit/Export workflow. The open package owns library membership, originals, metadata, and edit revisions; folder, Photos, and removable-volume choices are import sources. Local indexes and caches are projections. Existing `EditStore*.store` files remain untouched and are not read as a library fallback. See [`docs/PRODUCT_SCOPE.md`](docs/PRODUCT_SCOPE.md) for MVP intent and boundaries, [`docs/APP_ARCHITECTURE.md`](docs/APP_ARCHITECTURE.md) for current coordinator ownership, [`docs/STORAGE_POLICY.md`](docs/STORAGE_POLICY.md) for durable storage, and [`docs/LIBRARY_PACKAGE_PLAN.md`](docs/LIBRARY_PACKAGE_PLAN.md) for format history.

## Build architecture

SwiftPM is the primary development build system. All application functionality belongs in
`KromoraKit`. The SwiftPM `Kromora` executable is the development launcher, and the Xcode
`Kromora` target is the production launcher. The Xcode project exists only to package `KromoraKit`
as the signed, sandboxed Mac App Store app. Do not add implementation files to the Xcode target;
`XcodeProjectInvariantTests` enforces this boundary. Verify the production app with
`scripts/app-store-build.sh`.

Binary distribution is through the Mac App Store, with TestFlight for prereleases; developers can
build from source using SwiftPM. We do not distribute DMGs or maintain an updater.

## Build / run / test

- Build: `swift build`
- Run (fast iteration; no sandbox/icon): `swift run`
- Production app (icon + App Sandbox): run `open Xcode/Kromora.xcodeproj`, then run the
  `Kromora` scheme in Xcode.
- Tests: `swift test`. CI runs `scripts/ci-tests.sh fast` for deterministic/model/fake-engine tests
  in parallel and `scripts/ci-tests.sh serial` for Core Image/render and AppKit/UI tests serially.
  RAW-fixture and benchmark methods are opt-in through `scripts/ci-tests.sh optional`, then CI
  builds and verifies the packaged app.

CI runs on GitHub Actions' arm64 `xcode-27` image with Xcode 27 and the macOS 27 SDK. That hosted
image is currently in preview. The package, app bundle, and distributable still target **macOS 26
(Tahoe) on Apple Silicon**; keep product API usage compatible with that deployment floor. Do not add
`#available` branches, alternate code paths, or universal-binary support to keep an older OS or Intel
Mac working.

**Requires Xcode 27 or newer to build.** Symbols available in the macOS 26 SDK, such as
`CIRAWFilter.isHighlightRecoveryEnabled`, are part of the product baseline. An availability check cannot
supply a symbol the SDK never declared, and this project does not keep a fallback for that case.

## Display-bound benchmarks are rare and release-time

`scripts/run-kromora-capture.sh` (`last-known-frame`, `metal-presentation`, `concurrent-export-editing`)
mounts a real window and needs an unlocked, awake display, so it cannot run unattended and it takes
minutes. It is **release-qualification evidence, not a per-ticket check**:

- Do not run it to verify an ordinary change, a refactor, a fix, or a test. Use the deterministic
  lanes (`scripts/ci-tests.sh fast|serial|identity`) and structural assertions, and prefer a
  window-independent test (real engine and RAW, no `NSWindow`) when a number is needed.
- Cite the numbers already in `docs/TESTING.md` (the measured-state section) instead of re-measuring.
  The harness fails fast on a locked or asleep display; that is not a defect to chase.
- Run it only when the ticket is an explicitly supervised performance task that must produce new
  numbers, at most one series of three runs per ticket, with `caffeinate -dimu`, one capture at a
  time. If a ticket's acceptance criteria ask for a capture on a change that cannot move those
  numbers, say so in the ticket and skip it rather than starting a capture.
- The script refuses a repeat run on an unchanged tree unless you pass `--force`; do not pass it to get
  around the guard. A wall-clock miss is a handoff with a profile, not a reason to open a ticket on
  every re-run (see `.dg/decisions/ADR-LKF-001`).

## Swift 6 language mode is on, for every target

`Package.swift` is a 6.2 tools version and declares `.swiftLanguageMode(.v6)` on `KromoraKit`, `Kromora`
and `KromoraKitTests`. Data-race safety is **errors, not warnings**, and the module compiles with **zero** diagnostics
and **zero** escape hatches: no `@unchecked Sendable`, no `nonisolated(unsafe)`, no
`@preconcurrency`. `PackageSettingsTests` fails if any of that changes, because none of it is
observable at runtime.

Practical consequences when writing code here:

- **`deinit` is `nonisolated`.** It can run on any thread, so it may not touch non-`Sendable` stored
  state even on a `@MainActor` class. Teardown that needs the main actor belongs in an explicit
  method the owner calls — see `KeyMonitor.stop()`, which is why that pattern exists.
- **Closures handed to an unstructured `Task` must be `@Sendable`.** Mark the parameter rather than
  reaching for an opt-out.
- **`CIImage`, `CIFilter` and `CIContext` are not `Sendable`** and must stay inside `RenderEngine`.
  Only values cross the boundary — `EditDocument`, `ImageSource`, `CubeLUT`, `WorkingSpace`,
  `RenderScale` — plus a `sending CGImage?` or `Data` on the way out.
- If something genuinely cannot be expressed safely, raise it rather than silencing it. The zero-opt-out
  property is what makes "Swift 6 mode is on" mean anything; the mode is trivially satisfiable file
  by file otherwise.

## Layout

The package is split so the app's code is testable (`@testable` can't import an executable target):

- `Sources/KromoraKit/` — everything of substance (Models, ViewModels, Views). `AppViewModel` remains
  the composition root; `EditorDocumentCoordinator`, `PhotosImportCoordinator`, `PreviewCoordinator`,
  `EditPersistenceCoordinator`, `ExportCoordinator`, `DeriveCoordinator`, Look coordinators, and
  `PhotoAnalysisCoordinator` own focused workflows. `ContentView`, `KromoraCommands`,
  `KromoraAppDelegate`, and `KromoraScene` are `public`; keep the rest internal.
- `Sources/Kromora/` — SwiftPM launcher only (`KromoraApp.swift`).
- `App/` — production packaging inputs only (`Info.plist`, entitlements, asset catalog, and
  branding); no Swift implementation.
- `Tests/KromoraKitTests/` — XCTest. **Most fixtures are generated, never committed** (`Fixtures.swift`
  builds `.cube` files and orientation-tagged JPEGs into a temp dir). Exception (KRMA-459): a small
  set of AI-generated photo-intelligence JPEGs (≤ 5 MB total, each ≤ 500 KB) may be committed under
  the tests target resources with a provenance manifest. Local camera files for the opt-in RAW lane
  belong in the gitignored `realworldtest/` folder and are selected with `KROMORA_RAW_FIXTURE_DIR`
  when stored elsewhere. Keep them out of commits and document the workflow in its README.

When a test needs to exercise private behavior, first consider testing through the existing boundary.
Widen an implementation detail only when that makes the production boundary clearer and the test
needs the seam; document why, and keep test-only helpers in the test target when possible.

Constraints that must hold: **macOS 26 (Tahoe) and later, Apple Silicon only**, **zero third-party dependencies** (Apple frameworks only). Don't introduce SPM/CocoaPods/Carthage deps, and don't add compatibility shims for earlier macOS releases or Intel hardware.

## Agent and workflow safety

- Preserve the user's existing working-tree changes. At task start, inspect and distinguish
  pre-existing changes from work made for the task. Do not stash, reset, checkout over, or revert
  pre-existing changes unless the user explicitly directs you to. If ownership is unclear, leave
  them untouched.
- Tasks explicitly scoped as analysis/spec/review should not edit product source unless the active
  project workflow authorizes localized verification fixes. When parallel agents are explicitly
  requested, give research tasks read-only access; isolate delegated code edits in a separate
  worktree and review them before integration.
- Do not create branches, push, or open a PR unless the user or the active project workflow asks for
  it. Follow the current branch and commit rules below and any more specific instructions in
  `.dg/AGENTS.md` for DispatchGraph work.
- Do not rewrite history or discard work (`reset --hard`, force-push, `stash drop/clear`, deleting
  branches, or equivalent) without explicit user approval.

For an isolated checkout, `scripts/agent-worktree.sh create` prints a temporary worktree path;
remove it with `scripts/agent-worktree.sh remove <path>` after its work has been reviewed.

## Repo conventions

- Default branch is `main`; work on the branch already checked out unless the user or task workflow says otherwise. Keep commits focused and describe the change accurately. Do not add an agent-specific co-author trailer unless requested.
- Build artifacts (`.build/`, ~hundreds of MB), `.DS_Store`, and `.claude/` are gitignored. `CLAUDE.md` is the canonical source for shared project guidance; root `AGENTS.md` points agents to it so tools that discover `AGENTS.md` load the same source rather than maintaining a duplicate.
- `docs/ENGINEERING_GUIDE.md` records the current architecture, render/resource boundaries, persistence, masking, and contributor invariants. It is durable guidance, not an implementation plan; per-change transcripts belong in the PR or DispatchGraph issue.
- `docs/APP_ARCHITECTURE.md` records the current application ownership boundaries and coordinator extraction.
- `docs/AUTO_EXPOSURE_POLICY.md`, `docs/AUTO_PERFORMANCE.md`, and `docs/COMPARISON_MODE.md` record the current Auto and comparison contracts; performance numbers in the Auto guide are dated baseline evidence, not universal product claims.
- `docs/LOOKS.md`, `docs/PACKAGING.md`, and `docs/TESTING.md` are the current workflow guides for Looks/LUTs, release packaging, and verification/profiling.
