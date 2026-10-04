# App Store Sandbox Audit

This document records a source review of Kromora's App Sandbox access paths. Line references point
to the code reviewed for KRMA-783. A static review cannot confirm the entitlements embedded in a
signed app or the sandbox extensions macOS grants at runtime; the required sandboxed checks are
listed at the end of section 1.

## 1. Import, open, and persistent file access

### Entitlements and system panels

The checked-in app entitlements enable App Sandbox, user-selected read/write access, read-only
removable-media access, app-scoped bookmarks, and read/write access to Pictures
([`Kromora.entitlements`](../Sources/Kromora/Kromora.entitlements):5-14). Apple's current App
Sandbox guide says standard `NSOpenPanel`/`NSSavePanel` interactions extend the sandbox to selected
URLs and start security-scoped access; the app must stop that access when finished. It also documents
recursive access under a folder selected through a standard system interaction
([Apple: Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)).

| Path | What the code does | Sandbox assessment and evidence |
| --- | --- | --- |
| Open image files | `AppKitFileDialog.chooseFiles` presents `NSOpenPanel` and returns its URLs. `AppViewModel.openImageDialog` passes them into the package import path. | Relies on `com.apple.security.files.user-selected.read-write`. The package importer copies each selected original into `Assets/.../Original/`, then opens the package copy. This is safe in principle while the selected URL's PowerBox access is active. No import caller visibly releases the system-granted panel access after reading; see KRMA-818. [`AppKitFileDialogAdapter.swift`:39-53](../Sources/KromoraKit/Presentation/AppKitFileDialogAdapter.swift), [`AppViewModel.swift`:2656-2665](../Sources/KromoraKit/ViewModels/AppViewModel.swift), [`PortablePackageImport.swift`:350-365, 388-407, 432-446](../Sources/KromoraKit/Models/PortablePackageImport.swift) |
| Import a folder | `chooseFolder` returns one directory URL; the coordinator forwards it to `openSourceFolder`, which recursively enumerates supported images and schedules package copying. | Relies on `user-selected.read-write` and the system's folder grant for descendants. Enumeration starts before the asynchronous import, but the package worker consumes the resulting file URLs later. The workflow has no retained folder scope spanning both operations and no visible release; see KRMA-818. [`AppKitFileDialogAdapter.swift`:55-72](../Sources/KromoraKit/Presentation/AppKitFileDialogAdapter.swift), [`LibraryMediaWorkflowCoordinator.swift`:74-79](../Sources/KromoraKit/ViewModels/LibraryMediaWorkflowCoordinator.swift), [`AppViewModel.swift`:3046-3065, 3099-3113](../Sources/KromoraKit/ViewModels/AppViewModel.swift), [`PortableLibrarySession.swift`:696-707, 835-864](../Sources/KromoraKit/Models/PortableLibrarySession.swift) |
| Import from Photos | SwiftUI presents `PhotosPicker`; `PhotosPickerItem.loadTransferable(type: Data.self)` supplies bytes, which are imported into the package as data. | Does not open a filesystem URL and does not rely on the Pictures entitlement for reading the Photos original. PhotosUI mediates the user's selection. The package destination still relies on Pictures write access. [`ContentView.swift`:57-65, 177-184](../Sources/KromoraKit/Views/ContentView.swift), [`PhotosImportCoordinator.swift`:53-70](../Sources/KromoraKit/ViewModels/PhotosImportCoordinator.swift), [`PortableLibrarySession.swift`:950-995](../Sources/KromoraKit/Models/PortableLibrarySession.swift) |
| Choose a Look folder or import Look files | `AppViewModel` uses `NSOpenPanel` to select a folder or `.cube`/`.look` files; `LUTLibrary` stores bookmarks and retains access for external Look sources. | Relies on `user-selected.read-write`. Folder and file bookmarks are persisted and refreshed when stale on restore; the library holds active access while those sources are in use. [`AppViewModel.swift`:4797-4829](../Sources/KromoraKit/ViewModels/AppViewModel.swift), [`LUTLibrary.swift`:232-271, 449-493](../Sources/KromoraKit/Models/LUTLibrary.swift) |
| Save exported images or choose an export folder | `ExportCoordinator` uses `NSSavePanel` for one image and `NSOpenPanel` for batch-export folders. Its worker explicitly calls `startAccessing...` and defers a stop for the destination and any bookmark-backed source. | Relies on `user-selected.read-write`; the explicit starts have matching `defer` releases on success, thrown errors, and cancellation. Because standard panels also start security-scoped access, the effective panel-grant count and its release still need sandbox verification. [`ExportCoordinator.swift`:191-225, 267-272, 331-367, 480-483, 526-529](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift) |
| Save a derived or generated Look | `DeriveCoordinator` and `LookSaveCoordinator` present `NSSavePanel` and synchronously copy/write to the chosen destination. | Relies on `user-selected.read-write`. No visible stop follows these writes. `exportOriginalWithSettings` also selects a destination directory and starts asynchronous bundle creation without an explicit scope owner. These panel-returned output paths are included in KRMA-818. [`DeriveCoordinator.swift`:177-212](../Sources/KromoraKit/ViewModels/DeriveCoordinator.swift), [`LookSaveCoordinator.swift`:92-140](../Sources/KromoraKit/ViewModels/LookSaveCoordinator.swift), [`AppViewModel.swift`:4631-4654](../Sources/KromoraKit/ViewModels/AppViewModel.swift) |

### Drag-and-drop

The drop target is attached to the editor preview. It accepts file URLs, image data, and file
promises. File URLs are extracted from the drag pasteboard and passed to `LibraryMediaWorkflowCoordinator`;
that coordinator classifies a directory as a folder import and a regular file as an image. There is
no explicit `startAccessingSecurityScopedResource`, bookmark creation, or access-lifetime owner on
the file-URL drop route. Image data is already in memory, and Photos file promises are redeemed into
Kromora's temporary drop directory before package import.

The code therefore proves how drops are routed, but does not prove that a URL dropped on this window
receives a usable sandbox grant or how long that grant lasts. Apple's guide explicitly describes
system-started access for items dragged to the app's Dock icon; it does not establish this preview
window's pasteboard path. Verify Finder file drops and folder drops with the signed sandboxed app.
The access-lifetime risk is tracked in KRMA-818. Evidence: [`PreviewView.swift`:135-138](../Sources/KromoraKit/Views/PreviewView.swift), [`ImageDrop.swift`:23-60, 63-119](../Sources/KromoraKit/Presentation/ImageDrop.swift), [`ImageDropDelegate.swift`:11-29](../Sources/KromoraKit/Views/ImageDropDelegate.swift), [`FileDropActionPolicy.swift`:19-25](../Sources/KromoraKit/Presentation/FileDropActionPolicy.swift), [`LibraryMediaWorkflowCoordinator.swift`:82-109](../Sources/KromoraKit/ViewModels/LibraryMediaWorkflowCoordinator.swift), [`AppViewModel.swift`:2982-3024](../Sources/KromoraKit/ViewModels/AppViewModel.swift).

### Security-scoped bookmarks and start/stop ownership

- `PhotoAssetSource.bookmarkData(for:)` attempts to create an app-scoped bookmark with
  `.withSecurityScope`; failure is intentionally non-fatal. `PhotoAssetSource` can encode bookmark
  data, and `PhotoAsset.discoveredFile` supplies such a bookmark by default. Current portable-package
  materialization explicitly stores `bookmarkData: nil`: the imported original is owned by the
  package and does not need a persistent bookmark back to its original location. Evidence:
  [`PhotoAsset.swift`:188-222, 345-353](../Sources/KromoraKit/Models/PhotoAsset.swift),
  [`PhotoAssetImageMetadataAdapter.swift`:30-38](../Sources/KromoraKit/Platform/PhotoAssetImageMetadataAdapter.swift),
  [`PortableLibrarySession.swift`:1088-1097, 1200-1211](../Sources/KromoraKit/Models/PortableLibrarySession.swift).
- `KromoraSettings` persists selected default source/export folders in `UserDefaults`, resolves
  those bookmarks with `.withSecurityScope`, starts access while they are in use, refreshes stale
  bookmarks after a usable resolution, and stops access when replaced, reset, or the settings owner
  is destroyed. This is the relaunch-persistent bookmark path. Evidence: [`KromoraSettings.swift`:80-84, 213-217, 261-350, 451-459](../Sources/KromoraKit/Models/KromoraSettings.swift).
- `MediaVolume` creates a bookmark for a discovered mount or a user-selected recovery folder and
  resolves it before scanning. `resolvedAccessURL` captures but ignores the stale flag, and this
  value is held only in the current workflow rather than persisted for relaunch. Evidence:
  [`MediaVolume.swift`:10-32, 42-53, 178-195](../Sources/KromoraKit/Models/MediaVolume.swift),
  [`LibraryMediaWorkflowCoordinator.swift`:322-332](../Sources/KromoraKit/ViewModels/LibraryMediaWorkflowCoordinator.swift).
- `LUTLibrary` persists bookmarks for its configured external Look folder and imported Look files,
  resolves them on restore, refreshes stale bookmark data where it can, and retains active scopes
  through use. `ExportCoordinator` also resolves an optional source bookmark for batch export, but
  ignores the stale flag; current portable-library materialization supplies no photo-source bookmark.
  Evidence: [`LUTLibrary.swift`:232-271, 238-257, 456-493](../Sources/KromoraKit/Models/LUTLibrary.swift),
  [`ExportCoordinator.swift`:640-665](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift),
  [`PortableLibrarySession.swift`:1088-1097, 1200-1211](../Sources/KromoraKit/Models/PortableLibrarySession.swift).
- The source tree has eight explicit `startAccessingSecurityScopedResource` call sites. Each explicit
  start has a corresponding stop path: `MediaVolume.scanMountedVolume` and the removable preflight
  use `defer`; `ExportCoordinator` uses `defer`; `KromoraSettings` and `LUTLibrary` retain successful
  scopes and release them on replacement, reset, shutdown, or owner destruction. This code-level
  pairing does not account for scopes the system starts for standard panel URLs. The removable
  preflight's explicit pair is syntactically balanced but too short-lived: its callback queues the
  async package copy before the defer runs, so that copy can outlive the grant. Both lifetime cases
  are part of KRMA-818. Evidence:
  [`MediaVolume.swift`:214-224](../Sources/KromoraKit/Models/MediaVolume.swift),
  [`LibraryMediaWorkflowCoordinator.swift`:229-285](../Sources/KromoraKit/ViewModels/LibraryMediaWorkflowCoordinator.swift),
  [`ExportCoordinator.swift`:267-272, 480-483, 526-529](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift),
  [`KromoraSettings.swift`:213-217, 293-299, 451-459](../Sources/KromoraKit/Models/KromoraSettings.swift),
  [`LUTLibrary.swift`:196-221, 238-254, 449-493](../Sources/KromoraKit/Models/LUTLibrary.swift).
- `MediaVolume` does not persist its bookmark; the read-only removable-media entitlement is the
  normal mount path, with a folder Open panel as the recovery path. A fresh sandboxed run must
  establish whether that fallback grant remains effective through the package worker's source read.

### Reopening the library package after relaunch

There is no stored “last library package” URL or bookmark in the production startup path. Both
production `AppViewModel` initializers open the fixed `KromoraStorage.defaultPortableLibraryPackageURL`,
which is `~/Pictures/Kromora Library.kromoralibrary`; `PortableLibrarySession` opens it if present
and creates it if absent. The Pictures read/write entitlement is the code-declared access grant, so
this design does not depend on a security-scoped bookmark surviving relaunch. This is sandbox-safe
in principle if the signed app carries the declared Pictures entitlement. Code review cannot verify
the signed entitlement or package I/O under App Sandbox. Evidence: [`KromoraStorage.swift`:89-96](../Sources/KromoraKit/Models/KromoraStorage.swift), [`AppViewModel.swift`:971-992, 1044-1058](../Sources/KromoraKit/ViewModels/AppViewModel.swift), [`PortableLibrarySession.swift`:90-124](../Sources/KromoraKit/Models/PortableLibrarySession.swift), [`Kromora.entitlements`:5-14](../Sources/Kromora/Kromora.entitlements).

### RAW originals and neighboring sidecars

File-backed decoding opens the supplied URL, including when it selects the RAW decoder. Package
import accepts one source URL/name per item and stages that one file as the managed original; it does
not enumerate or open siblings beside a selected original. External camera `.xmp` sidecars are
therefore not accessed by this import path. Kromora's own edit/XMP sidecars are separate files inside
the Pictures library package and are covered by that package's Pictures entitlement. No sibling
access denial is visible in the reviewed code; preservation/import of external sidecars is not
implemented here and should not be inferred from the package's internal XMP support. Evidence:
[`ImageDecoder.swift`:100-117](../Sources/KromoraKit/Models/ImageDecoder.swift),
[`PortablePackageImport.swift`:4-23, 350-365, 388-407](../Sources/KromoraKit/Models/PortablePackageImport.swift),
[`STORAGE_POLICY.md`:17-22](STORAGE_POLICY.md).

### Removable-volume access

The removable-media entitlement is read-only, matching `MountedMediaVolumeProvider`'s discovery,
enumeration, metadata reads, and image validation. It does not authorize writes to the card; imports
copy source files into the portable package under Pictures. If mount scanning is denied, the
coordinator asks the user to select the volume folder in an Open panel, creates a bookmark, resolves
it, and starts scoped access while scanning. The current import-preflight task rechecks readability
under scope, then sends an asynchronous import request; its `defer` stops the scope as that callback
returns, before the package worker necessarily opens the file. This is a should-fix risk (KRMA-818),
and whether the removable-media entitlement masks it must be tested on the signed sandbox build.
Evidence: [`Kromora.entitlements`:7-14](../Sources/Kromora/Kromora.entitlements),
[`MediaVolume.swift`:141-149, 170-195, 214-259](../Sources/KromoraKit/Models/MediaVolume.swift),
[`LibraryMediaWorkflowCoordinator.swift`:151-188, 229-285, 322-332](../Sources/KromoraKit/ViewModels/LibraryMediaWorkflowCoordinator.swift),
[`AppViewModel.swift`:2910-2959](../Sources/KromoraKit/ViewModels/AppViewModel.swift).

### Findings

| Severity | Finding | Evidence | Follow-up |
| --- | --- | --- | --- |
| should-fix | Panel-selected URLs and removable-volume access are not visibly released/retained for the full read/write lifetime. The removable fallback scope is released immediately after the asynchronous import is queued; file-URL window drops have no explicit access owner. Repeated panel-selected operations also have no visible release in the import or direct Look-save paths. | [`AppKitFileDialogAdapter.swift`:45-72](../Sources/KromoraKit/Presentation/AppKitFileDialogAdapter.swift), [`LibraryMediaWorkflowCoordinator.swift`:229-285](../Sources/KromoraKit/ViewModels/LibraryMediaWorkflowCoordinator.swift), [`PortableLibrarySession.swift`:696-707, 835-864](../Sources/KromoraKit/Models/PortableLibrarySession.swift), [`DeriveCoordinator.swift`:183-212](../Sources/KromoraKit/ViewModels/DeriveCoordinator.swift), [`LookSaveCoordinator.swift`:92-140](../Sources/KromoraKit/ViewModels/LookSaveCoordinator.swift), [`ImageDrop.swift`:36-52](../Sources/KromoraKit/Presentation/ImageDrop.swift) | KRMA-818 (backlog, `appstore`) |
| note | The main package has no “last package” bookmark because production always reopens its fixed Pictures location. Default source/export folders do use persisted, stale-refreshing bookmarks. | [`KromoraStorage.swift`:89-96](../Sources/KromoraKit/Models/KromoraStorage.swift), [`AppViewModel.swift`:971-992](../Sources/KromoraKit/ViewModels/AppViewModel.swift), [`KromoraSettings.swift`:261-350](../Sources/KromoraKit/Models/KromoraSettings.swift) | No follow-up required for the current fixed-path design. |
| note | `MediaVolume.resolvedAccessURL` ignores bookmark staleness, but the volume record and its grant bookmark are transient rather than a relaunch-persistent library reference. | [`MediaVolume.swift`:42-53](../Sources/KromoraKit/Models/MediaVolume.swift) | Confirm the mounted-volume and fallback cases during the sandboxed run. |
| note | The import path reads/copies only the selected original. It does not access an adjacent external RAW sidecar; package-owned edit/XMP files live inside the package. | [`PortablePackageImport.swift`:350-365, 388-407](../Sources/KromoraKit/Models/PortablePackageImport.swift), [`STORAGE_POLICY.md`:17-22](STORAGE_POLICY.md) | Do not treat external sidecar preservation as implemented. |

### Behaviors requiring a sandboxed run

No signed sandboxed run was performed for this static audit. `swift run` does not establish these
runtime behaviors. Verify them with the packaged/signed app and inspect its effective entitlements:

1. Open and import one file and multiple files from outside Pictures; cancel and repeat the operation.
2. Select a folder outside Pictures and import images from nested folders; exercise cancellation and
   a source read error.
3. Drag a file URL and a folder from Finder onto the preview window. Separately drop an image from
   Photos to exercise its file-promise route.
4. Import from a removable volume with the read-only entitlement, then exercise the Open-panel
   access-recovery path. Confirm the package copy completes after preflight returns and confirm no
   write to the source volume is attempted.
5. Save a rendered image, a derived Look, and an original-plus-settings bundle to a location outside
   Pictures; repeat saves to exercise scope release.
6. Quit and relaunch after importing into the default Pictures package, then confirm the package
   opens without another panel.

The code review establishes that imported package assets are embedded and external adjacent RAW
sidecars are not read. If external sidecar preservation becomes a product requirement, audit and
test that as an explicit import feature.
