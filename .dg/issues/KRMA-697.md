---
id: KRMA-697
title: Dock sidebar and inspector below unified toolbar (remove titlebar bleed hacks)
type: task
status: backlog
priority: high
creation_provenance:
  runner: pi
  model: unknown
  actor: pi
labels:
  - app-shell
  - tahoe
  - toolbar
  - layout
created: 2026-09-28T22:19:35.575Z
updated: 2026-09-28T22:20:14.013Z
depends_on:
  - KRMA-694
blockers: []
order: z
board: product
---

## Objective

Dock the sidebar and inspector below the unified toolbar, Xcode-style, by deleting the transparent-titlebar bleed hacks. After this ticket the toolbar spans the full width uninterrupted (per `.context/Screenshot 2026-09-28 at 4.07.42 PM.png`); navigator and inspector start underneath it.

Parent: KRMA-693. Sequencing: after KRMA-694; coordinate with KRMA-696 — that ticket owns the `.toolbar` block, this one owns everything that bleeds under it.

## Context

Today the bar goes *through* the content:

- `ContentView.swift:591-670` — `TitlebarSeparatorSuppression` (`NSViewRepresentable` + `TitlebarSeparatorSuppressionView`): forces `fullSizeContentView`, `titlebarAppearsTransparent=true`, `titlebarSeparatorStyle=.none`, re-applies on move/key/layout/draw. ~80 lines plus observers.
- `ContentView.swift:80` — `.background(TitlebarSeparatorSuppression())`.
- `ContentView.swift:216-235` — `mainContent`: `NavigationStack { detailContent.ignoresSafeArea(.trailing) }` + `.inspector { InfoInspectorView.ignoresSafeArea(.top).inspectorColumnWidth(240/280/360) }` — the histogram deliberately occupies the band beside the toolbar controls (`InfoInspectorView.swift:3,102`).
- `ContentView.swift:259` — `SourceBrowserView` as a manual `HStack` column inside detail rather than a split column, with custom `sourceBrowserTransition` / `bottomChromeTransition`.

Xcode does none of this: `NSToolbarStyle.unified` draws an opaque bar; split columns dock below.

## Acceptance criteria

- [ ] `TitlebarSeparatorSuppression` and its view class deleted; no `fullSizeContentView` / `titlebarAppearsTransparent` / `titlebarSeparatorStyle=.none` manipulation remains in the app target.
- [ ] Inspector histogram relocated below the toolbar (remove `.ignoresSafeArea(.container, edges:.top)`); no plot under glass, no vibrancy washout, no 1px drag gap through the plot.
- [ ] Sidebar evaluated against `NavigationSplitView`: either migrate `SourceBrowserView` to a real sidebar column (preferred if collapse/toggle comes free and focus behavior in `KeyboardShortcuts.swift:6` stays correct) or keep the `HStack` with a written justification; either way it starts below the toolbar and the existing show/hide animations still respect reduce-motion.
- [ ] `KromoraTheme.swift` surface-role comment rewritten: toolbar = visible unified glass, inspector = system material below bar, canvas = recessed stage. No "hide the separator" language.
- [ ] `LibraryChromeLayoutTests`, `KromoraWindowAppearanceControllerTests`, and any snapshot asserting transparent separators updated to the docked geometry; `scripts/ci-tests.sh fast` + `serial` clean.
- [ ] Manual pass: open/close sidebar and inspector at 800x500 and 1200x800, light/dark, drag/resize/tab — no transparency flashes, no separator lines through pills, traffic lights stay aligned.

## Implementation notes

Deletion-first diff: remove the representable, the `.background(...)`, the `.ignoresSafeArea(.top)`, then re-verify the histogram section (`InfoInspectorView.swift:252-290`) in its new home — it may want a small top inset to replace the band it lost. Keep `inspectorColumnWidth` and the crop-owns-inspector gating in `mainContent` unchanged. Watch `PreviewSurface.swift:798` (`NavigationSplitView` replacing selected image) if migrating the sidebar.


### Comment — codex @ 2026-09-29T00:33:03.216Z

Implemented and committed as 1e26938: removed titlebar bleed suppression and inspector top safe-area override, documented the optional editor pane rationale, and added native toolbar geometry coverage. Verification: scripts/ci-tests.sh fast (1,332 tests), scripts/ci-tests.sh serial (443 tests, 1 skipped), and LibraryChromeLayoutTests (3 tests) passed. A visible manual pass is still needed for the requested window-size, appearance, resize/drag, and tab checks.

## Comment - human @2026-09-29
Reviewed and it is functional and has the correct glass effect. The sidebar currently covers the content breaking teh usability a fair bit. You can see in the attached screenshot that the thumbnails and image goes under the controls. This is not ideal and should be corrected.  

I have attached two additional images that demonstrate how xcode solves this. The first shows the sidebar (right) open. You can see the sidebar button aligned all the way to the right at the top of the sidebar. The second is the sidebar closed. You can see the button is still aligned to the right but now appears on the top bar. I think this model could be good for Kromora.

![Xcode reference with the right sidebar open](../assets/KRMA-697/xcode-sidebar-open.png)

![Xcode reference with the sidebar closed and its toggle remaining at the right edge of the toolbar](../assets/KRMA-697/xcode-sidebar-closed.png)
