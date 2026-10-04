# App Store Sandbox Audit

This document records a source review of Kromora's App Sandbox access paths. Section 1 references
the code reviewed for KRMA-783; section 2 references the write/output paths reviewed for KRMA-784.
A static review cannot confirm the entitlements embedded in a signed app or the sandbox extensions
macOS grants at runtime; the required sandboxed checks are listed at the end of each section.

## 1. Import, open, and persistent file access

### Entitlements and system panels

The checked-in app entitlements enable App Sandbox, user-selected read/write access, read-only
removable-media access, app-scoped bookmarks, and read/write access to Pictures
([`Kromora.entitlements`](../App/Kromora.entitlements):5-14). Apple's current App
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
the signed entitlement or package I/O under App Sandbox. Evidence: [`KromoraStorage.swift`:89-96](../Sources/KromoraKit/Models/KromoraStorage.swift), [`AppViewModel.swift`:971-992, 1044-1058](../Sources/KromoraKit/ViewModels/AppViewModel.swift), [`PortableLibrarySession.swift`:90-124](../Sources/KromoraKit/Models/PortableLibrarySession.swift), [`Kromora.entitlements`:5-14](../App/Kromora.entitlements).

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
Evidence: [`Kromora.entitlements`:7-14](../App/Kromora.entitlements),
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

## 2. Export, Photos, storage, caches

This section audits output destinations, Photos delivery, durable and rebuildable storage, and
temporary files. Application Support, Caches, and temporary-directory locations resolve to the
sandbox container in the signed app. The default library and app-owned export/Look folders are in
Pictures; selected external locations rely on the system panel grant or a persisted
security-scoped bookmark.

### Export destinations, staging, and collisions

| Path | What the code writes | Sandbox and collision assessment |
| --- | --- | --- |
| Single rendered export | An NSSavePanel chooses a file URL, initially in the configured export folder. ExportOptions carries that URL as a file destination. | ExportCoordinator starts access to the selected file URL and stops it when the asynchronous export finishes. It creates a UUID-named .partial sibling in the destination's parent, writes atomically to that sibling, then moves it to the final URL. The parent directory must allow creation of that sibling; code only explicitly starts access on the selected file URL, so verify that the panel grant covers this staging operation. A pre-existing final file is not replaced: moveItem fails and the existing export remains. KRMA-818 tracks selected-output access ownership. [ExportCoordinator.swift:191-225, 267-287](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift), [ExportOptions.swift:55-59, 131-145](../Sources/KromoraKit/Models/ExportOptions.swift), [ExportCoordinator.swift:606-623](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift) |
| Batch rendered export | An NSOpenPanel chooses the output folder. Outputs use the configured format and the selected folder. | The worker starts access to the folder and defers its stop until the serial batch ends. Existing names receive a numbered suffix, and a reservation set prevents same-batch collisions. Each file is staged as a .partial sibling inside the selected folder and is moved into place without replacing an existing item. [ExportCoordinator.swift:331-366, 475-483, 512-523](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift), [ExportCoordinator.swift:606-623, 872-883](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift) |
| Original + settings bundle | An NSOpenPanel chooses a parent folder; Kromora creates a named .kromora-original package below it. | Bundle creation runs asynchronously after the panel returns. It writes a .partial directory beside the destination, verifies the original, settings, and manifest, then moves the directory into place. An existing destination causes moveItem to fail rather than overwrite it; the temporary directory is cleaned up on exit. The bundle worker has no explicit security-scope owner for the selected parent, tracked by KRMA-818. [AppViewModel.swift:4631-4659](../Sources/KromoraKit/ViewModels/AppViewModel.swift), [OriginalSettingsBundle.swift:31-46, 73-83](../Sources/KromoraKit/Models/OriginalSettingsBundle.swift) |
| Saved Looks | Save Look uses an NSSavePanel; the owned Pictures/Kromora Looks folder is its starting location. A user may choose another destination. | LookSaveCoordinator refuses an existing destination and CubeLUT writes the new text atomically. It does not explicitly start or stop selected-URL access; KRMA-818 covers that lifetime. DeriveCoordinator creates its scratch .cube in the system temporary directory, then its save path removes an existing selected destination before copying the replacement. A failed copy can therefore leave no prior file; tracked by KRMA-819. [LookSaveCoordinator.swift:92-140](../Sources/KromoraKit/ViewModels/LookSaveCoordinator.swift), [CubeLUT.swift:507-522](../Sources/KromoraKit/Models/CubeLUT.swift), [DeriveCoordinator.swift:120-150, 175-212](../Sources/KromoraKit/ViewModels/DeriveCoordinator.swift), [KromoraSettings.swift:219-220, 381-389](../Sources/KromoraKit/Models/KromoraSettings.swift) |
| Share exports | Single and batch Share render TIFFs under unique subdirectories of FileManager.temporaryDirectory. | These are app-owned temporary outputs in the sandbox container; they are not written to a user-selected external location. Photos import similarly stages transferred bytes in the temporary directory and removes the file after package import. [AppViewModel.swift:4487-4519, 4522-4552](../Sources/KromoraKit/ViewModels/AppViewModel.swift), [PortableLibrarySession.swift:950-995](../Sources/KromoraKit/Models/PortableLibrarySession.swift) |

ExportFormat selects an encoding and suffix, while ExportOptions models a file or folder URL;
neither writes independently of ExportCoordinator. A clean profile's default export folder is Pictures/Kromora
Exports and is created before the save panel opens. A configured export folder is restored from a
security-scoped bookmark. Both the default export folder and the default Kromora Looks folder are
user-visible Pictures locations rather than hidden Application Support output.
[ExportFormat.swift:12-35](../Sources/KromoraKit/Models/ExportFormat.swift),
[KromoraSettings.swift:223-245](../Sources/KromoraKit/Models/KromoraSettings.swift),
[AppViewModel.swift:1503](../Sources/KromoraKit/ViewModels/AppViewModel.swift),
[KromoraStorage.swift:14-17, 71-78](../Sources/KromoraKit/Models/KromoraStorage.swift)

### Photos import and delivery

Photos import uses SwiftUI PhotosPicker for image selection, then PhotosPickerItem
loadTransferable(Data.self). Kromora does not enumerate the Photos library or run its own
read-authorization state machine for this picker path. An empty/cancelled selection starts no
import; a nil transfer is counted as skipped, and a transfer failure is recorded per item while
later selections continue. The transferred bytes are staged in the app temporary directory only
long enough for the package importer to copy them into the library. Info.plist has a Photos usage
description for the import and add-to-Photos actions.
[ContentView.swift:57-65, 177-184](../Sources/KromoraKit/Views/ContentView.swift),
[PhotosImportCoordinator.swift:50-70, 140-186, 269-301](../Sources/KromoraKit/ViewModels/PhotosImportCoordinator.swift),
[PortableLibrarySession.swift:950-995](../Sources/KromoraKit/Models/PortableLibrarySession.swift),
[Info.plist:44-45](../App/Info.plist)

Optional post-export delivery uses PhotoKit read/write authorization. It requests authorization
only while status is notDetermined, maps authorized, limited, denied, and restricted (plus
notDetermined) explicitly, and permits asset creation for authorized or limited access. Denied or
restricted access becomes a PhotosDeliveryError with recovery text; the already-committed export
file remains safe on disk and the failure is surfaced to the user. A limited grant may still fail
the optional album update, which is reported as a warning without undoing the saved Photos asset.
[PhotosDelivery.swift:4-24, 89-130, 185-193](../Sources/KromoraKit/Models/PhotosDelivery.swift),
[ExportCoordinator.swift:287-303, 547-562](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift)

### Package, index, caches, and persisted paths

| Artifact | Sandbox location and persistence |
| --- | --- |
| Portable library package | Production opens the fixed Pictures/Kromora Library.kromoralibrary package. Originals, metadata, edit revisions, and Look blobs are package-owned; current embedded source locators and edit revision pointers use package-relative paths. The schema reserves a bookmark field for a future referenced-source mode, but no production call uses it. No current package record persists an absolute container path. [KromoraStorage.swift:89-96](../Sources/KromoraKit/Models/KromoraStorage.swift), [PortableLibraryPackage.swift:216-278, 292-354, 528-556](../Sources/KromoraKit/Models/PortableLibraryPackage.swift), [PortablePackageImport.swift:432-446](../Sources/KromoraKit/Models/PortablePackageImport.swift), [PackagePath.swift:11-30](../Sources/KromoraKit/Models/PackagePath.swift) |
| Library index and launch hints | The rebuildable index and launch hints live below the Application Support location returned by FileManager, in Kromora/Indexes/<library-id>/LibraryIndex.store and Kromora/LaunchHints.json. In the sandboxed app this is container storage. The projection records package-relative recordPath values and summaries, not absolute URLs; the package membership shards rebuild it. [KromoraStorage.swift:19-22, 33-61](../Sources/KromoraKit/Models/KromoraStorage.swift), [LibraryQueryController.swift:43-75, 120-143, 425-435](../Sources/KromoraKit/Models/LibraryQueryController.swift), [PortableLibrarySession.swift:124-143](../Sources/KromoraKit/Models/PortableLibrarySession.swift) |
| Edit database | There is no separate production edit database. EditDocumentStore is a bounded in-memory cache; canonical edit revisions are committed as package sidecars. Existing standalone EditStore files are not opened as a fallback. [EditDocumentStore.swift:84-92, 180-214](../Sources/KromoraKit/Models/EditDocumentStore.swift), [STORAGE_POLICY.md:25-35, 101-103](STORAGE_POLICY.md) |
| Presentation frames | Latest previews live under package Derived/Previews. Packed thumbnails live under package Derived/Thumbnails; the packed index stores asset keys, shard numbers, offsets, and lengths. Both are disposable package-derived caches, not absolute filesystem references. Latest-preview staging is beside the cache destination; thumbnail maintenance writes into the package transaction. [LatestPreviewFrameStore.swift:6-16, 73-85, 370-392](../Sources/KromoraKit/Models/LatestPreviewFrameStore.swift), [PortablePackageMaintenance.swift:75-80, 107-117, 332-362, 558-563](../Sources/KromoraKit/Models/PortablePackageMaintenance.swift) |
| Device caches | Masks, photo analysis, and current-edit measurements use the Caches directory under the Kromora subdirectory. This location is rebuildable and resolves within the sandbox container. [KromoraStorage.swift:25-46](../Sources/KromoraKit/Models/KromoraStorage.swift), [MaskStore.swift:4-6, 195](../Sources/KromoraKit/Models/PhotoAnalysis/MaskStore.swift), [PhotoAnalysisCache.swift:98-111, 189](../Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCache.swift), [CurrentEditMeasurement.swift:1331-1335, 1382](../Sources/KromoraKit/Models/PhotoAnalysis/CurrentEditMeasurement.swift), [STORAGE_POLICY.md:25-35](STORAGE_POLICY.md) |

Current production data flow does not serialize an absolute path string into package or index
records. The package schema has a future referenced-source case with opaque bookmark data, but the
importer writes embedded relative paths and no production call constructs that referenced case.
The local index stores package-relative recordPath values. UserDefaults does contain operational
paths for selected default folders and imported external Look files, alongside security-scoped
bookmark data; these are external-resource preferences, not package or index paths. They can become
stale if a user moves a selected folder or Look, and the bookmark restore paths report unavailable
access.
[KromoraSettings.swift:80-84, 261-280, 302-349](../Sources/KromoraKit/Models/KromoraSettings.swift),
[LUTLibrary.swift:154-159, 456-493](../Sources/KromoraKit/Models/LUTLibrary.swift)

### Look folders and Settings folder selection

Bundled starter Looks are read from the KromoraKit resource bundle and are not copied out of the
application. The app-owned writable Look folder defaults to Pictures/Kromora Looks. For an
external Look folder, Choose Look Folder presents NSOpenPanel and LUTLibrary saves an app-scoped
bookmark. The panel-selection path begins scanning after setting the URL without a visible explicit
startAccess call. Restoring the folder on a later launch resolves that bookmark and starts scoped
access. Imported .cube/.look files also retain bookmark records, with stored paths as a UserDefaults
fallback. The Settings Choose folder actions use an Open panel and KromoraSettings stores the
security-scoped bookmark, keeps access while the configured folder is in use, and refreshes stale
bookmarks after successful resolution. The AppKitSettingsFolderAdapter only creates/reveals the
app-owned Look folder in Finder; it does not grant access to another folder.
[BundledLookLibrary.swift:32-37, 57-85, 108-122](../Sources/KromoraKit/Models/BundledLookLibrary.swift),
[AppViewModel.swift:4797-4829](../Sources/KromoraKit/ViewModels/AppViewModel.swift),
[LUTLibrary.swift:232-269, 449-493](../Sources/KromoraKit/Models/LUTLibrary.swift),
[KromoraSettingsView.swift:244-260](../Sources/KromoraKit/Views/KromoraSettingsView.swift),
[AppKitFileDialogAdapter.swift:55-72](../Sources/KromoraKit/Presentation/AppKitFileDialogAdapter.swift),
[KromoraSettings.swift:261-350, 381-389, 451-459](../Sources/KromoraKit/Models/KromoraSettings.swift),
[AppKitSettingsFolderAdapter.swift:22-31](../Sources/KromoraKit/Presentation/AppKitSettingsFolderAdapter.swift)

### Path and entitlement conclusions

The source contains no /Users/ literal and no NSHomeDirectory() call. The only
homeDirectoryForCurrentUser use is a dynamic fallback to Pictures when FileManager has no Pictures
URL. All urls(for:in:) calls are centralized in KromoraStorage: Application Support, Caches, and
Pictures; Application Support and Caches fall back to FileManager.temporaryDirectory if the
directory lookup returns no URL. There are no hard-coded user-home paths in the reviewed source.
[KromoraStorage.swift:19-39, 64-78](../Sources/KromoraKit/Models/KromoraStorage.swift)

| Entitlement | Conclusion |
| --- | --- |
| com.apple.security.assets.pictures.read-write | YES, required by current filesystem code: production creates/opens the default library package and the default export/Look folders under Pictures. This entitlement grants filesystem access to Pictures. PhotoKit import and delivery do not rely on it; PhotosPicker mediates import and PhotoKit handles delivery authorization. [Kromora.entitlements:5-14](../App/Kromora.entitlements), [KromoraStorage.swift:64-96](../Sources/KromoraKit/Models/KromoraStorage.swift), [AppViewModel.swift:971-992](../Sources/KromoraKit/ViewModels/AppViewModel.swift), [PortableLibrarySession.swift:106-124](../Sources/KromoraKit/Models/PortableLibrarySession.swift), [PhotosDelivery.swift:89-130](../Sources/KromoraKit/Models/PhotosDelivery.swift) |
| com.apple.security.files.removable-media.read-only | YES, exercised: MountedMediaVolumeProvider discovers removable/ejectable mounts, enumerates and reads supported images and metadata, and the production provider does not write to the source volume. Imports write their copies into the Pictures package. [Kromora.entitlements:5-14](../App/Kromora.entitlements), [MediaVolume.swift:141-149, 155-195, 214-259](../Sources/KromoraKit/Models/MediaVolume.swift), [PortableLibrarySession.swift:886-925](../Sources/KromoraKit/Models/PortableLibrarySession.swift) |

### Findings

| Severity | Finding | Evidence | Follow-up |
| --- | --- | --- | --- |
| should-fix | Direct Look saves and original-plus-settings bundle creation do not visibly own and release the panel-selected output grant for the complete write. Selecting an external Look folder saves its bookmark, but the immediate scan has no explicit start/stop owner. Single-file export also stages a sibling file in the parent directory while explicitly starting access only on the selected file URL; confirm that the grant covers the parent. | [LookSaveCoordinator.swift:92-140](../Sources/KromoraKit/ViewModels/LookSaveCoordinator.swift), [DeriveCoordinator.swift:183-212](../Sources/KromoraKit/ViewModels/DeriveCoordinator.swift), [AppViewModel.swift:4631-4659, 4799-4808](../Sources/KromoraKit/ViewModels/AppViewModel.swift), [LUTLibrary.swift:232-257](../Sources/KromoraKit/Models/LUTLibrary.swift), [ExportCoordinator.swift:267-272, 606-623](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift) | KRMA-818 (backlog, appstore) |
| should-fix | Saving a derived Look removes an existing destination before copying its replacement. If the copy fails, the previous user file is already gone. | [DeriveCoordinator.swift:204-213](../Sources/KromoraKit/ViewModels/DeriveCoordinator.swift) | KRMA-819 (backlog, appstore) |
| note | The default package is deliberately in Pictures and requires the Pictures filesystem entitlement; PhotoKit authorization is a separate access path. Removable-media read-only access is used for normal mounted-volume discovery and image reads. | [Kromora.entitlements:5-14](../App/Kromora.entitlements), [KromoraStorage.swift:89-96](../Sources/KromoraKit/Models/KromoraStorage.swift), [MediaVolume.swift:170-259](../Sources/KromoraKit/Models/MediaVolume.swift), [PhotosDelivery.swift:89-130](../Sources/KromoraKit/Models/PhotosDelivery.swift) | Verify effective entitlements in the signed app. |
| note | Package records and the local index use stable identities and package-relative paths. External folder and Look paths are operational preferences with bookmarks, not absolute paths embedded in package/index data. | [PortableLibraryPackage.swift:216-278, 292-354](../Sources/KromoraKit/Models/PortableLibraryPackage.swift), [LibraryQueryController.swift:43-75](../Sources/KromoraKit/Models/LibraryQueryController.swift), [KromoraSettings.swift:80-84](../Sources/KromoraKit/Models/KromoraSettings.swift), [LUTLibrary.swift:472-493](../Sources/KromoraKit/Models/LUTLibrary.swift) | No follow-up required for the current package/index format. |
| note | Single rendered exports fail rather than replace when the destination exists; batch exports add numeric suffixes. LookSaveCoordinator refuses collisions, original-plus-settings bundles refuse an existing package destination, and derived Look saves replace the destination by deleting it before copying. | [ExportCoordinator.swift:606-623, 875-883](../Sources/KromoraKit/ViewModels/ExportCoordinator.swift), [LookSaveCoordinator.swift:125-139](../Sources/KromoraKit/ViewModels/LookSaveCoordinator.swift), [OriginalSettingsBundle.swift:73-83](../Sources/KromoraKit/Models/OriginalSettingsBundle.swift), [DeriveCoordinator.swift:204-213](../Sources/KromoraKit/ViewModels/DeriveCoordinator.swift) | Replacement data-loss risk is KRMA-819. |

### Behaviors requiring a sandboxed run

No signed sandboxed run was performed for this static section. Verify with the packaged app and
inspect effective entitlements:

1. Export one rendered file outside Pictures and confirm its sibling .partial staging write works;
   repeat to an existing file and confirm the prior export is preserved.
2. Batch export outside Pictures and verify numbered collisions and cancellation cleanup.
3. Save a generated Look and a derived Look outside Pictures, including an existing derived-Look
   destination and an injected/real copy failure, then confirm the prior file's behavior.
4. Export an original-plus-settings bundle outside Pictures; repeat with an existing bundle
   destination and confirm cleanup on failure.
5. Exercise PhotosPicker import and optional Photos delivery with denied, restricted, and limited
   authorization states. Confirm denied Photos delivery leaves the rendered disk export usable.
6. Reopen configured source/export and external Look folders after relaunch; confirm bundled Looks
   load without an external folder grant.
7. Confirm package edits, library index rebuild, frame stores, caches, and temporary files remain
   usable or safely rebuildable after container recreation/movement, and inspect the signed app's
   Pictures and removable-media entitlements.

## 3. Runtime, resources, and privacy inventory

### Network and process inventory

| Surface | Current call sites | App Store disposition |
| --- | --- | --- |
| App-initiated network requests | No production app-source calls to `URLSession` or other network APIs were found. | No app-owned network request is part of the current product. |
| User-opened web links | The About view exposes the LUTzy and Kromora GitHub pages; SwiftUI link handling opens them in the user's browser. [`KromoraAboutView.swift`:94-95](../Sources/KromoraKit/Views/KromoraAboutView.swift) | These are explicit browser handoffs, not in-process network calls. Browser navigation does not require the app's network-client entitlement. |

No `Process()`, `dlopen`, `dlsym`, `Bundle.load`, XPC helper, or other dynamic host-code loader was
found in app sources. No helper app or embedded third-party framework/executable is declared.
`Package.swift` links the Apple Accelerate, Photos, PhotosUI, and Vision frameworks. The KromoraKit
resources include `KromoraCIKernels.ci.metallib` and `KromoraPresentation.metallib`; these are
compiled Metal shader libraries consumed by Core Image/Metal, not host executables or helper
processes. [`Package.swift`:131-140](../Package.swift), [`Sources/KromoraKit/Resources`](../Sources/KromoraKit/Resources)

### KromoraKit resource bundle resolution

SwiftPM copies `Sources/KromoraKit/Resources` into the `Kromora_KromoraKit.bundle` resource bundle.
`KromoraKitResourceBundle` first appends that bundle name to `Bundle.main.resourceURL` and loads it;
if it is not there, it falls back to SwiftPM's generated `Bundle.module`. In a standard macOS app
bundle the first lookup expects the package bundle under the app's `Contents/Resources` directory.
[`Package.swift`:131-134](../Package.swift), [`KromoraKitResourceBundle.swift`:3-15](../Sources/KromoraKit/Support/KromoraKitResourceBundle.swift)

Xcode's packaging of a local Swift package may place the generated resource bundle at a different
location. The path assumption must be checked in the Xcode-built `.app`, including the starter Look
manifest and Metal libraries; KRMA-813 owns the packaged-app build and verification. A bundle at a
different location could make bundled Looks or shader resources unavailable if neither lookup
resolves it.

### Protected resources and usage-description strings

| Protected resource or access path | Current API and permission model | Required `Info.plist` usage string |
| --- | --- | --- |
| Photos chosen for import | SwiftUI `PhotosPicker` transfers only user-selected items as `Data`; it does not enumerate the library or request PhotoKit authorization. [`ContentView.swift`:57-65, 177-184](../Sources/KromoraKit/Views/ContentView.swift), [`PhotosImportCoordinator.swift`:53-70](../Sources/KromoraKit/ViewModels/PhotosImportCoordinator.swift) | None for the picker. Apple's [PhotosUI picker documentation](https://developer.apple.com/documentation/swiftui/view/photospicker(ispresented:selection:maxselectioncount:selectionbehavior:matching:preferreditemencoding:photolibrary:)) says authorization is not needed because the person explicitly selects the items. |
| Save exports to Photos and optionally organize an album | `PhotoKit` checks and requests `.readWrite` authorization, creates an asset, and may fetch/create an album and fetch the new asset. [`PhotosDelivery.swift`:82-87, 127-181](../Sources/KromoraKit/Models/PhotosDelivery.swift) | `NSPhotoLibraryUsageDescription`, already present at [`Info.plist`:44-45](../App/Info.plist). The existing read/write level is appropriate for the album fetch/update path; Apple's [PhotoKit authorization guidance](https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app) reserves `NSPhotoLibraryAddUsageDescription` for add-only access. |
| User-selected and dropped files/folders; package and removable-media files | `NSOpenPanel`/`NSSavePanel`, Finder drops, app-scoped bookmarks, and the App Sandbox file entitlements mediate file access. These are filesystem grants, not protected-resource privacy prompts. [`AppKitFileDialogAdapter.swift`:39-72](../Sources/KromoraKit/Presentation/AppKitFileDialogAdapter.swift), [`ImageDrop.swift`:23-60](../Sources/KromoraKit/Presentation/ImageDrop.swift), [`Kromora.entitlements`:5-14](../App/Kromora.entitlements) | None. No file or folder usage-description string is required for the standard panel and sandbox-entitlement paths. |

Do not add `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSLocationUsageDescription`,
`NSContactsUsageDescription`, `NSCalendarsFullAccessUsageDescription`, or
`NSAppleEventsUsageDescription`: there are no corresponding capture, location, address-book,
calendar, or automation API calls in app sources. Do not add
`NSPhotoLibraryAddUsageDescription` for the current read/write PhotoKit flow, and do not treat
PhotosPicker as requiring broad Photos authorization.

### Required-reason API inventory

The table covers production app sources. Apple's current [privacy-manifest guidance](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
covers data-collection practices on all platforms, while required-reason API declarations apply
only to iOS, iPadOS, tvOS, visionOS, and watchOS; it does not list macOS. Kromora targets
native macOS only: SwiftPM declares `.macOS(.v26)` in [`Package.swift`](../Package.swift), and the
Xcode `Kromora` target declares
`SUPPORTED_PLATFORMS = macosx` in [`project.pbxproj`](../Xcode/Kromora.xcodeproj/project.pbxproj).
Therefore, these source calls are not required-reason blockers for the current Mac App Store target.
The approved codes below remain useful context if a covered platform is added. Apple separately
requires privacy manifests for certain third-party SDKs. App Store Connect privacy answers are
based on actual collection practices and remain separate from this required-reason inventory;
neither requirement makes the current macOS file-timestamp calls a blocker.

| Category | Exhaustive source evidence | Apple reason-code fit if a covered platform is added |
| --- | --- | --- |
| `NSPrivacyAccessedAPICategoryUserDefaults` | [`KromoraSettings.swift`:89-207, 298, 394-444](../Sources/KromoraKit/Models/KromoraSettings.swift); [`LUTLibrary.swift`:178-181, 227-267, 492-493](../Sources/KromoraKit/Models/LUTLibrary.swift); [`AppViewModel.swift`:426, 873, 998, 1248](../Sources/KromoraKit/ViewModels/AppViewModel.swift); [`ContentView.swift`:17](../Sources/KromoraKit/Views/ContentView.swift) and [`OnboardingViews.swift`:299](../Sources/KromoraKit/Views/OnboardingViews.swift) use SwiftUI `@AppStorage`. | `CA92.1` — app-private preferences and bookmarks. |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | [`PhotoAsset.swift`:101-108](../Sources/KromoraKit/Models/PhotoAsset.swift) reads a source file's size and modification date; [`ImageSource.swift`:258-267](../Sources/KromoraKit/Models/ImageSource.swift) reads size and modification date for a URL-backed source trace; [`PortablePackageMaintenance.swift`:168-170](../Sources/KromoraKit/Models/PortablePackageMaintenance.swift) reads the thumbnail index stamp; [`LatestPreviewFrameStore.swift`:359, 394-401, 473-487](../Sources/KromoraKit/Models/LatestPreviewFrameStore.swift) writes and reads preview-cache modification dates and file sizes. | No required-reason declaration is needed for the native macOS-only target. If Kromora later targets a covered platform, `3B52.1` applies only to files or directories the user specifically granted access to, and `C617.1` only to files inside app, app-group, or CloudKit containers. The automatically created library and its derived caches are in Pictures and do not fit either code as currently implemented. |
| `NSPrivacyAccessedAPICategorySystemBootTime` | [`NeutralOriginSlider.swift`:210, 220, 271, 280, 291](../Sources/KromoraKit/Views/NeutralOriginSlider.swift) reads `ProcessInfo.systemUptime` for in-app slider animation/timing. | `35F9.1` — measure elapsed time between in-app events and support timers. |
| `NSPrivacyAccessedAPICategoryDiskSpace` | No current app-source calls to `volumeAvailableCapacity*`, `volumeTotalCapacityKey`, `systemFreeSize`, `systemSize`, `statfs`, or `statvfs` were found. `.fileSizeKey` call sites above read individual file metadata, not free/total volume capacity. | No reason to declare unless a broader dependency/binary audit finds an additional use. |
| `NSPrivacyAccessedAPICategoryActiveKeyboards` | No `activeInputModes` call was found. App keyboard shortcuts handle key events and do not inventory active keyboards. | No reason to declare. |

For a future target on one of Apple's listed platforms, every declared reason must accurately
describe the API use and derived data, not merely match a symbol name. See Apple's [required-reason
API guidance](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

## 4. Recommendations

### Final App Sandbox entitlements

| Final entitlement | Recommendation | Justification |
| --- | --- | --- |
| `com.apple.security.app-sandbox` | Keep enabled. | Required for the Mac App Store sandboxed app. |
| `com.apple.security.files.user-selected.read-write` | Keep enabled. | Supports user-selected image/folder imports, exports, and Look files through standard system panels. |
| `com.apple.security.files.removable-media.read-only` | Keep enabled. | Mounted camera-card discovery and source-image reads are current import paths; imports copy into the Pictures library and do not write to the card. |
| `com.apple.security.files.bookmarks.app-scope` | Keep enabled. | Settings and the Look library persist app-scoped bookmarks for user-selected external folders and files. |
| `com.apple.security.assets.pictures.read-write` | Keep enabled. | The default library package, default exports, and app-owned Looks live under Pictures. |
| `com.apple.security.network.client` | Do not declare. | No app-owned network request is part of the current product; user-opened browser links use the system browser. |

Thus, the minimal final set is the five retained entitlements above; the network-client entitlement
is not part of that set. No Photos entitlement is needed because PhotosPicker and PhotoKit use their
system-mediated selection/authorization paths.

### Usage strings and linked follow-ups

| Item | Recommendation | Follow-up |
| --- | --- | --- |
| `NSPhotoLibraryUsageDescription` | Keep the existing string for the PhotoKit `.readWrite` authorization used by export delivery and album placement. The PhotosPicker import flow itself is picker-mediated and does not need library authorization. | No new issue; retain in the app's final `Info.plist`. |
| Other protected-resource usage strings | Add none. File access is handled through standard panels/bookmarks and entitlements; there are no camera, microphone, location, Contacts, Calendars, or Apple Events APIs. | No new issue. |
| Required-reason privacy manifest | Not required solely for native macOS API use. Revisit if Kromora adds an iOS, iPadOS, tvOS, visionOS, or watchOS target, integrates an SDK subject to a manifest requirement, or otherwise needs a manifest to describe collected data. App Store Connect's data-collection answers are maintained separately from a manifest. | KRMA-798 documents current scope; KRMA-807 prepares App Store Connect answers. |
| Xcode resource-bundle location | Inspect the archived/signed `.app` and verify KromoraKit resource lookup finds the SwiftPM bundle and required resources. | KRMA-813 |

No new blocker or should-fix was identified beyond these existing linked App Store workstream
issues. Sections 1 and 2 above are unchanged from the earlier file and sandbox audits.
