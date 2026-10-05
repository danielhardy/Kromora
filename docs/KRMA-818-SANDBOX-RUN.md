# KRMA-818 signed sandbox run

- **Run date:** 2026-10-05
- **Host:** macOS 27.2 (26B5091g), Apple M4 Pro, Xcode 27.0
- **Build:** `.build/xcode/Build/Products/Release/Kromora.app`, version 0.1 (1)
- **Signing:** `Developer ID Application: Last8 LLC (FNB49PXFFU)`, team `FNB49PXFFU`
- **Entitlements:** App Sandbox; user-selected read/write; Pictures read/write; app-scoped bookmarks; removable media read-only.

This records the KRMA-818 signed sandbox cases, not the full `APP_STORE_ACCEPTANCE` A1–A30 run.

| Case | Result | Evidence |
| --- | --- | --- |
| Panel-selected files | Pass | Selected `panel-one.png` and `panel-two.png` together. Both appeared in the package library after the panel closed. |
| Recursive folder panel import | Pass | Selected `Nested`, containing `folder-root.png` and `Deeper/folder-nested.png`. The app reported two imports and both appeared in the package library. |
| Removable-media fallback grant | Pass | Mounted the generated APFS image read-only as `KRMA818Media`; `diskutil` confirmed `Volume Read-Only: Yes` and `Removable Media: Removable`. Granted access through the fallback panel and imported `removable.png`. Source and imported SHA-256 values matched; the source volume remained read-only. |
| Output save | Partial | A signed build exported `KRMA-818-export2.tif` into the user-selected external `Exports` folder, and the result was a valid 48×48 TIFF. That run preceded the final exclusive-create write implementation. Repeating the save against the final signed build remains pending. |
| Finder file and folder drops | Pending | The available CUA drag operation returned `noWindowsAvailable`, so neither drop case could be run. Manual verification on the final signed build is required. |

The final source revision passed the fast and serial test lanes and the signed app build verification. The final signed app process later had no window discoverable by CUA (`cgWindowNotFound`), which prevented rerunning the output-save case and cleaning up the last test-only `removable.png` library import. Four other generated import fixtures were removed through Kromora's normal Delete-to-Trash flow. The generated source fixtures and read-only disk image are local `.build` artifacts, not project assets.
