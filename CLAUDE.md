# CLAUDE.md — project guidance for AI agents

Kromora is a native **macOS 14+** RAW photo editor (**Swift 6 language mode**, SwiftUI + Core Image, **zero third-party dependencies**): it develops RAW through `CIRAWFilter`, applies tone/colour adjustments, local masks, and `.cube` LUTs through one Metal-backed render pipeline, and can derive a `.cube` LUT from a (RAW, JPG) pair. The current product is the package-backed Library/Edit workflow with culling, deletion, content-aware Auto, comparison, and full-resolution export. The open package owns library membership, originals, metadata, and edit revisions; folder, Photos, and removable-volume choices are import sources. Local indexes and caches are projections. Existing `EditStore*.store` files remain untouched and are not read as a library fallback. See [`docs/APP_ARCHITECTURE.md`](docs/APP_ARCHITECTURE.md) for the current coordinator and migration boundaries, [`docs/STORAGE_POLICY.md`](docs/STORAGE_POLICY.md) for durable storage, and [`docs/LIBRARY_PACKAGE_PLAN.md`](docs/LIBRARY_PACKAGE_PLAN.md) for format history.

## Build / run / test

- Build: `swift build`
- Run (fast iteration; no sandbox/icon): `swift run`
- Full app (icon + App Sandbox): open `Package.swift` in Xcode and Run.
- Tests: `swift test`. CI runs `scripts/ci-tests.sh fast` for deterministic/model/fake-engine tests
  in parallel and `scripts/ci-tests.sh serial` for Core Image/render and AppKit/UI tests serially.
  RAW-fixture and benchmark methods are opt-in through `scripts/ci-tests.sh optional`, then CI
  builds and verifies the packaged app.

**SDK and deployment target are different things — don't conflate them.** CI runs on `macos-26`
(Xcode 26.x, macOS 26 SDK); `Package.swift` deploys to **macOS 14**. Building against a current SDK
while deploying to 14 is the normal Apple model and is the *stricter* arrangement: the compiler
refuses any API newer than the deployment target unless it is `#available`-guarded, so the guard is
enforced rather than remembered. Use newer API behind `#available` — don't avoid it.

**Requires Xcode 26 or newer to build.** That is the cost of the above: `RAWDevelopSettings` references
`CIRAWFilter.isHighlightRecoveryEnabled`, which only exists in the macOS 26 SDK. On an older Xcode the
package will not compile, and no availability check can change that — `#available` gates a call at
runtime; it cannot conjure a symbol the SDK never declared. That distinction cost a red build in Phase 2
Step 2, when CI still ran `macos-14` (Xcode 15.4 / macOS 14.5 SDK) and the code built clean locally.

If CI ever needs to move back to an older image, that reference is the thing that has to go with it.

## Swift 6 language mode is on, for every target

`Package.swift` is a 6.0 tools version and declares `.swiftLanguageMode(.v6)` on `KromoraKit`, `Kromora`
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
  `PhotoAnalysisCoordinator` own focused workflows. Only `ContentView` and
  `KromoraCommands` are `public`; keep the rest internal.
- `Sources/Kromora/` — the `@main` entry point, `AppDelegate`, and the asset catalog. Nothing else belongs here.
- `Tests/KromoraKitTests/` — XCTest. **Most fixtures are generated, never committed** (`Fixtures.swift`
  builds `.cube` files and orientation-tagged JPEGs into a temp dir). Exception (KRMA-459): a small
  set of AI-generated photo-intelligence JPEGs (≤ 5 MB total, each ≤ 500 KB) may be committed under
  the tests target resources with a provenance manifest. Licensed camera files for the opt-in RAW
  lane still live outside the checkout and are selected with `KROMORA_RAW_FIXTURE_DIR`.

When a test needs to exercise private behavior, first consider testing through the existing boundary.
Widen an implementation detail only when that makes the production boundary clearer and the test
needs the seam; document why, and keep test-only helpers in the test target when possible.

Constraints that must hold: **macOS 14 minimum**, **zero third-party dependencies** (Apple frameworks only). Don't introduce SPM/CocoaPods/Carthage deps.

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
