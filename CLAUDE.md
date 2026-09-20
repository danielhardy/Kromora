# CLAUDE.md — project guidance for AI agents

Kromora is a native **macOS 14+** RAW photo editor (**Swift 6 language mode**, SwiftUI + Core Image, **zero third-party dependencies**): it develops RAW through `CIRAWFilter`, applies tone/colour adjustments, local masks, and `.cube` LUTs through one Metal-backed render pipeline, and can derive a `.cube` LUT from a (RAW, JPG) pair. The current product is the folder-backed Library/Edit workflow with culling, deletion, content-aware Auto, comparison, and full-resolution export. See [`docs/APP_ARCHITECTURE.md`](docs/APP_ARCHITECTURE.md) for the current coordinator boundaries and [`docs/LIBRARY_PACKAGE_PLAN.md`](docs/LIBRARY_PACKAGE_PLAN.md) for the explicitly future portable-library work.

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

When a test needs something currently `private`, widen it to internal with a comment saying why —
`RecipeExtractor.buildCube` and `workingSize` are the precedent.

Constraints that must hold: **macOS 14 minimum**, **zero third-party dependencies** (Apple frameworks only). Don't introduce SPM/CocoaPods/Carthage deps.

## Agent & workflow safety (READ THIS)

A prior multi-agent **spec/analysis** run was meant to be read-only but a sub-agent edited tracked source as a side effect. Those edits had to be reverted and re-introduced deliberately as a reviewed PR. To prevent a repeat, these rules are binding for any agent or multi-agent workflow operating in this repo:

1. **Analysis/spec/review runs are read-only w.r.t. tracked source.** Fan-out sub-agents must NOT `Edit`/`Write`/`NotebookEdit` files under version control. They return their findings/spec **as text**; the orchestrator (main session) makes any file changes on the main tree after reviewing that text.
2. **Enforce read-only mechanically, don't just ask.** Prefer one of:
   - spawn sub-agents with a read-only agent type (e.g. `Plan`, `Explore`) — they cannot write; or
   - in a `Workflow`, restrict sub-agents to read-only tools; or
   - if a sub-agent genuinely must edit, give it **worktree isolation** (`isolation: "worktree"`, or the helper below) so it operates on a throwaway copy, never the main tree.
3. **Verify the tree after any agent run.** `git status --porcelain` must be empty (aside from intended outputs). If unexpected changes appear, stash + revert them and surface to the user rather than committing.
4. **Code changes land via the normal flow** — a branch + reviewed PR — not as a silent side effect of an analysis task. Repo-meta docs (README, LICENSE, specs, this file) may be committed directly to `main`.
5. **Don't run destructive git** (history rewrite, force-push, `stash drop/clear`, branch `-D`) without explicit user approval.

### Throwaway worktree helper

For any agent run that needs a scratch checkout it can't pollute the main tree with:

```bash
DIR=$(scripts/agent-worktree.sh create)   # prints a temp worktree path on the current HEAD
# ... point the agent/workflow at "$DIR" ...
scripts/agent-worktree.sh remove "$DIR"   # clean up when done
```

## Repo conventions

- Default branch `main`; commit messages end with the `Co-Authored-By: Claude …` trailer.
- Build artifacts (`.build/`, ~hundreds of MB), `.DS_Store`, and `.claude/` are gitignored. `.claude/` is ignored, so **shared agent guidance belongs here in `CLAUDE.md`**, not under `.claude/`.
- `docs/ENGINEERING_GUIDE.md` records the current architecture, render/resource boundaries, persistence, masking, and contributor invariants. It is durable guidance, not an implementation plan; per-change transcripts belong in the PR or DispatchGraph issue.
- `docs/APP_ARCHITECTURE.md` records the current application ownership boundaries and coordinator extraction.
- `docs/AUTO_EXPOSURE_POLICY.md`, `docs/AUTO_PERFORMANCE.md`, and `docs/COMPARISON_MODE.md` record the current Auto and comparison contracts; performance numbers in the Auto guide are dated baseline evidence, not universal product claims.
- `docs/LOOKS.md`, `docs/PACKAGING.md`, and `docs/TESTING.md` are the current workflow guides for Looks/LUTs, release packaging, and verification/profiling.
