# Sandboxed App Store acceptance

This checklist is for a signed **Xcode Release** build of Kromora on an Apple Silicon Mac running
macOS 26 or later. `swift run` is a development runtime and does not prove the signed app's sandbox,
entitlements, or file grants. Do not record a SwiftPM run as a pass.

Run the end-to-end pass from a disposable macOS user account when practical. Use copies of test
photos, an expendable removable volume, and output folders outside `~/Pictures`. Do not use valuable
photos or files for the collision and failure cases. Keep the app open for the complete log-capture
window in A4.

The exact behavior of selected-file grants, file drops, Photos authorization, signed resources,
bookmarks, and TestFlight installation can only be confirmed on the packaged app. This checklist
records observations; it does not claim that those checks have already been run.

## 1. Prepare and identify the build

1. Use Xcode 27 or later on an arm64 Mac with macOS 26 or later. Sign in to the Apple Developer team
   that owns `com.last8.kromora.photo`, and configure that team under **Xcode > Settings > Accounts**.
2. Build the shared scheme with the Release configuration and automatic Apple Development signing.
   Replace `YOUR_TEAM_ID` with the team identifier shown in Xcode:

   ```sh
   xcodebuild \
     -project Xcode/Kromora.xcodeproj \
     -scheme Kromora \
     -configuration Release \
     -destination 'platform=macOS,arch=arm64' \
     -derivedDataPath "$PWD/.build/KRMA-059-DerivedData" \
     -allowProvisioningUpdates \
     CODE_SIGN_STYLE=Automatic \
     CODE_SIGN_IDENTITY='Apple Development' \
     DEVELOPMENT_TEAM=YOUR_TEAM_ID \
     build
   ```

   In Xcode, the equivalent is selecting the **Kromora** scheme, **Release** configuration, and
   **My Mac**, then choosing **Product > Build**. Ensure the Release product is signed with the
   configured team; an unsigned or ad-hoc build is not an acceptance build.
3. Set the path to the just-built app and verify its signature and entitlements:

   ```sh
   KROMORA_APP="$PWD/.build/KRMA-059-DerivedData/Build/Products/Release/Kromora.app"
   codesign --verify --deep --strict "$KROMORA_APP"
   codesign -d --entitlements :- "$KROMORA_APP" 2>&1
   /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$KROMORA_APP/Contents/Info.plist"
   /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$KROMORA_APP/Contents/Info.plist"
   ```

   **Expected:** signature verification succeeds. The embedded entitlements include
   `com.apple.security.app-sandbox = true`, user-selected read/write, removable-media read-only,
   app-scope bookmarks, and Pictures read/write. There are no unexpected `com.apple.security.*`
   entitlements. Record version and build number.
4. Prepare disposable fixtures and a folder layout outside Pictures:

   ```sh
   KROMORA_ACCEPTANCE="$HOME/Desktop/Kromora Sandbox Acceptance"
   NESTED_FIXTURES="$KROMORA_ACCEPTANCE/Fixtures/Nested"
   OUTPUT_FOLDER="$KROMORA_ACCEPTANCE/Exports"
   DESTINATION_FILE="$OUTPUT_FOLDER/sentinel.jpg"
   mkdir -p "$NESTED_FIXTURES" "$OUTPUT_FOLDER"
   ```

   Copy test inputs into the fixture folders using Finder. Create `sentinel.jpg` in the output
   folder with disposable contents and record its hash with `shasum -a 256 "$DESTINATION_FILE"`.

   - A readable JPEG and a supported RAW file, copied outside Pictures.
   - A matched RAW/JPG pair for the derive-Look flow.
   - A nested folder containing several readable images, a duplicate supported JPEG named
     `unreadable.jpg` for the source-read case, and an optional corrupt/unsupported image copy.
   - A Finder-accessible removable volume containing copies of images. Keep it read-only for this
     pass; preserve an empty expendable volume if a write attempt needs to be ruled out.
   - A Finder-accessible output folder outside Pictures, with a sentinel file whose contents and
     SHA-256 hash are recorded before collision tests.
   - A disposable RAW with a neighboring `.xmp` (or camera sidecar) and another neighboring file.
   - A small disposable Photos library selection for PhotosPicker and Photos export checks.
   - Record the SHA-256 of at least one source photo before import, for the end-to-end original
     integrity check.
5. Before launching Kromora, start log capture in Terminal and leave it running in a separate
   window for the whole pass:

   ```sh
   log stream --style compact --info --debug --predicate 'sender == "Sandbox"' 2>&1 \
     | tee "$HOME/Desktop/Kromora-sandbox.log"
   ```

   Keep it running through all acceptance cases; stop it with Control-C after the last case. Keep
   the log file with the completed results.
6. Launch this exact app (`open "$KROMORA_APP"`). In **Activity Monitor**, choose **View > Columns
   > Sandbox**, find Kromora, and confirm **Sandbox: Yes**. If more than one Kromora process is
   listed, identify the PID for the app launched from the path above. Apple's verification steps
   are documented in [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox).

## 2. Run the sandboxed acceptance cases

Record an outcome and evidence for every row in the Results template. “Not run” and “N/A” are not
passes. A restricted or limited authorization case that macOS or the test account cannot offer must
be marked N/A with the macOS version and reason.

Run A30 in a clean disposable macOS user account with an empty default library, before other
functional cases populate that profile. The signature and resource checks A1–A3 can be done first.

### End-to-end clean-profile pass (KRMA-059)

| ID | Action and UI path / command | Expected result |
| --- | --- | --- |
| A30 | In the clean test account, import the copied photo set from outside Pictures (**Import > Open Source Folder...**). In Library, pick one frame (`P`) and reject another (`X`); open the picked frame in Edit (`E`), make an adjustment and commit it, then switch on **Comparison view** (or press `V`). Export the edited photo with **File > Export...** (⌘S) to the disposable output folder. Quit and relaunch Kromora. Reopen the library and verify the cull states, edit, comparison workflow, and exported image. Compare the source-photo hash with the pre-import hash. | Import, cull, edit, comparison, relaunch, and export all work in the signed sandboxed app. The chosen/rejected states and committed edit remain attached to the correct photo; the export is readable; and the input original still matches its pre-import SHA-256. |

### Build, sandbox, and packaged resources

| ID | Action and UI path / command | Expected result |
| --- | --- | --- |
| A1 | Complete preparation steps 1–3 and 5–6. Check `codesign -d --entitlements :- "$KROMORA_APP"` and Activity Monitor's Sandbox column. | Signed Release app verifies; the five expected sandbox entitlements are present; Activity Monitor reports **Sandbox: Yes** for the launched process. |
| A2 | In the editor, open **Edit** and the Look inspector. Search/browse the starter Looks, apply one, and render a photo. | Bundled Looks appear without selecting an external Look folder; a starter Look applies, and the image renders without missing resource/shader errors. This checks the packaged SwiftPM resource bundle as well as the starter Look manifest and Metal libraries (KRMA-813 audit item). |
| A3 | Inspect built resources with `find "$KROMORA_APP/Contents/Resources" -maxdepth 8 \( -name 'Kromora_KromoraKit.bundle' -o -name 'manifest.json' -o -name '*.cube' -o -name '*.metallib' \) -print`. | The app contains `Kromora_KromoraKit.bundle`, `StarterLooks/manifest.json` and its `.cube` files, `KromoraCIKernels.ci.metallib`, and `KromoraPresentation.metallib`. Record the bundle path; A2 verifies these resources resolve and work at runtime. |

### Import, drops, bookmarks, and removable media

| ID | Action and UI path / command | Expected result |
| --- | --- | --- |
| A4 | After all cases A1–A30 finish, stop the log capture started in preparation with Control-C. Review `$HOME/Desktop/Kromora-sandbox.log` for denials during the full pass; correlate any record with its timestamp and case. | The log file is retained. There are no sandbox denial records attributable to Kromora. Attach any matching denial excerpt and mark the affected case Fail. |
| A5 | In the app's **Import** toolbar menu choose **Open Image...** (or **File > Open Image...**). Select one image outside Pictures; repeat with multiple images. Cancel one open-panel attempt, then perform a successful open/import again. | Selected files import into the library and can be opened. Cancel leaves no partial or misleading library item. Repeating after cancellation succeeds. |
| A6 | Choose **Import > Open Source Folder...**. Select the nested fixture folder outside Pictures. Repeat once, cancel during a sufficiently large import, then test source-read failure with a duplicate fixture: in Terminal run `chmod 000 "$HOME/Desktop/Kromora Sandbox Acceptance/Fixtures/Nested/unreadable.jpg"`, import its folder with readable siblings, and restore the copy using `chmod 600 "$HOME/Desktop/Kromora Sandbox Acceptance/Fixtures/Nested/unreadable.jpg"`. Optionally repeat with a corrupt/unsupported copy. | Supported images in nested folders import. Cancellation stops cleanly without a false success or stranded partial item. An unreadable/corrupt source produces a clear failure or skip and does not prevent valid files from remaining usable. Restore the test fixture permissions and confirm a subsequent folder import works. |
| A7 | In Finder, drag a copied image file onto the app's preview window, then drag a copied folder onto it. Separately drag an image from Photos onto the preview to exercise Photos' file-promise drop. | Each supported drop follows the import flow and the imported image opens from the package. No sandbox denial or unexplained access error occurs. |
| A8 | With the test removable volume mounted, choose **Import > Removable Media** and import a selected image. Then use **File > Import from Removable Media...** or the app's removable-media recovery prompt to select the volume root through the Open panel. Wait until the copy is complete after preflight returns. Inspect the volume afterward. | Mounted discovery and image reads work with read-only removable-media access. The fallback panel grant remains usable through the package copy. The package copy completes after preflight returns, and Kromora has not written to or changed the source volume. Repeat once to check the later operation still works. |
| A9 | Import the disposable RAW with its neighboring `.xmp` and other neighbor using **Open Image...**. In Finder, use **Go > Go to Folder…** and open `~/Pictures/Kromora Library.kromoralibrary`; choose **Show Package Contents** and inspect the imported asset's `Original` folder. | The selected RAW imports and renders; only the selected source file is staged as the managed original. The neighboring external sidecar/file is not imported as a Kromora asset. This verifies the current boundary; it does not claim external sidecar preservation or prove an unobservable read by itself. |
| A10 | Import at least one image into the default library. Quit Kromora normally and relaunch the same signed app. | The default package at `~/Pictures/Kromora Library.kromoralibrary` reopens automatically without another file panel; imported photos and committed edits remain available. The package path is fixed under Pictures and does not depend on a last-library bookmark. |
| A11 | In **Kromora > Settings…**, choose external folders for **Import defaults**, **Export defaults**, and the user Look folder. Quit and relaunch; reopen Settings and use each folder. Then make the external Look folder unavailable (for example, eject its test volume) and reopen the Look inspector. | Each configured folder resolves to the selected path after relaunch and remains usable without reselecting it. Bundled Looks still appear when the external Look folder is unavailable. Note any stale/missing bookmark message. |

### Photos authorization and delivery

PhotosPicker import and PhotoKit delivery are separate paths. **Import > Import from Photos...** uses
the system picker and should not request broad Photos-library authorization. The export dialog's
**Also add to Photos** option uses PhotoKit and is the path for testing allow, deny, restricted, and
limited access. Use a fresh disposable macOS account for the first prompt; change later states in
**Apple menu > System Settings > Privacy & Security > Photos** and relaunch Kromora after changing
access. Do not treat a PhotosPicker selection as proof of PhotoKit authorization.

| ID | Action and UI path / command | Expected result |
| --- | --- | --- |
| A12 | Choose **Import > Import from Photos...**, select a known photo, and import it. Observe whether a broad Photos permission alert appears. | The system Photos picker presents the selection, the selected item imports, and this picker-mediated import does not ask for broad Photos-library access. |
| A13 | From a selected/editable photo choose **File > Export...** (⌘S), select an output outside Pictures, enable **Also add to Photos**, and confirm. On the first run, allow the system Photos prompt. Verify the saved file in Finder and the new item in Photos; if choosing an album is offered, try a new test album. | The rendered file is saved to the chosen folder and the asset appears in Photos. If album organization is requested, it succeeds with adequate access or reports a clear album warning without undoing the saved Photos asset or disk export. |
| A14 | Set Kromora's Photos access to **Deny** in System Settings. Repeat A13 with a new output filename. | The Photos attempt fails with understandable recovery text, while the rendered disk export remains complete and usable. No partial disk export is left behind. |
| A15 | If the OS/test account can provide **Restricted** Photos authorization (for example, an account managed by policy), repeat the Photos delivery action and record the authorization state shown by the app/system. | Delivery is refused or restricted with a clear explanation; any already committed disk export remains usable. If the test Mac cannot enter this state, record N/A and why. |
| A16 | If macOS offers **Limited** / selected-items Photos access, grant limited access and repeat A13. If the UI supports selecting the test photo, exercise delivery with a photo outside that selection too. | Record the system access mode. The rendered disk file remains saved. The newly exported asset may be added to Photos; album lookup/update may report a restriction warning. The operation does not present or enumerate unrelated library items. Record whether limited mode was actually available on this macOS version. |

### Export, collision, cleanup, and repeated access

Use only the disposable external output folder at
`$HOME/Desktop/Kromora Sandbox Acceptance/Exports`. Before each collision case, make a backup copy
of the destination sentinel and record its hash with
`shasum -a 256 "$HOME/Desktop/Kromora Sandbox Acceptance/Exports/sentinel.jpg"`. Afterward,
compare both the file contents and hash. Inspect for leftover staging files with
`find "$HOME/Desktop/Kromora Sandbox Acceptance/Exports" -name '*.partial' -print`.

| ID | Action and UI path / command | Expected result |
| --- | --- | --- |
| A17 | Export one rendered image using **File > Export...** (⌘S) to a new destination outside Pictures. Repeat to a different new destination. | Both writes, including the sibling `.partial` staging write and final move, succeed. No `.partial` remains after completion; the next save also works. |
| A18 | Repeat A17 using the exact path `$HOME/Desktop/Kromora Sandbox Acceptance/Exports/sentinel.jpg`. Compare `shasum -a 256` before/after and inspect the app's message. | A single rendered export does not replace the existing file; the sentinel hash/content is unchanged, the conflict is explained, and no staging file remains. |
| A19 | Select multiple library items and choose **File > Export Originals...** (⇧⌘E). Export to the external folder with a name that already exists; cancel a separate batch while it is running. | Existing files are preserved and new colliding outputs receive numeric suffixes. Cancellation reports/stops cleanly and removes temporary/partial output; another batch succeeds afterward. |
| A20 | Generate and save a Look to a new `.cube` destination, then save another generated Look. Also use **File > Derive Look from JPG…** with the disposable RAW/JPG pair and save the derived Look outside Pictures. Repeat each flow to new paths. | New generated and derived Looks save at the selected destination, show a clear result, and repeated panel-selected writes still work. No `.partial` or temporary output remains. |
| A21 | For the derived Look only, first save to a disposable existing destination and record its contents. If a safe, reproducible copy failure can be induced on throwaway files, repeat and inspect the prior destination. Do not use a valuable file. | On successful save, record replacement behavior. On copy failure, record whether the previous file survives: the audit identifies that current code removes an existing destination before copying, so loss of the disposable prior file is a known failure (KRMA-819), not a pass. If no safe failure can be induced, mark Not run and state why. |
| A22 | Choose **File > Export Original + Settings Bundle…** (⌥⌘B), write a new bundle outside Pictures, and repeat. Repeat with a path that already exists; try cancellation or a safe write failure with a throwaway destination. | A new bundle is complete and opens/contains the source original and settings. Existing bundle destination is not replaced; failure/cancellation leaves no partial bundle, and a later write succeeds. |
| A23 | Export a Look and an image to an external destination three times each, closing the dialogs normally between attempts. | Each operation succeeds or reports its own clear destination error; repeated operations do not start failing from unreleased file access. Record the specific file/destination and whether a sandbox denial appeared. |

### Package, indexes, caches, and relaunch

| ID | Action and UI path / command | Expected result |
| --- | --- | --- |
| A24 | With test data only, edit a photo and commit the edit. Quit and relaunch, then open the edited image. After A25's app-container recreation, refresh the Library view and open that same image again. | Package-owned originals and committed edits remain intact. After container recreation, the library index is rebuilt from package records without losing membership or edits. |
| A25 | In a disposable macOS test account only, quit the app and back up the account's Kromora package and any needed evidence. In Terminal move only that test account's container to the backup path with `mv "$HOME/Library/Containers/com.last8.kromora.photo" "$HOME/Desktop/Kromora Sandbox Acceptance/Kromora-container-backup"`, then relaunch Kromora to let macOS create a fresh container. If testing container movement, use a supported migration/restore of the disposable account when available; do not manually move the live container in Finder. If no supported move scenario is available, mark that subcase Not run. Do not delete or move a primary user's container. | The package under Pictures remains usable; local index, preview/frame stores, and caches are reused when valid or safely rebuilt; temporary files are not required for normal opening/editing/export. Settings/bookmarks stored in the recreated container may need to be selected again; record separately from package data. Record container recreation and movement as separate outcomes. |
| A26 | After the pass, inspect the disposable app temp/output areas and any `.partial` files in the output folder. Repeat a normal open, preview, and export. | Temp artifacts are cleaned up or safely disposable; there is no orphaned `.partial` output, and normal features still work. |

### TestFlight and App Store release path

| ID | Action and UI path / command | Expected result |
| --- | --- | --- |
| A27 | In Xcode choose **Product > Archive** for the Kromora scheme using Release. In Organizer choose **Validate App** and resolve any validation error. Then use **Distribute App > App Store Connect > Upload** with the authorized team. In App Store Connect, wait for processing and make the build available to an internal TestFlight tester. | Xcode creates a valid signed archive; App Store validation and upload report no blocking packaging or entitlement error. App Store Connect processes the expected version/build. If credentials or account access are unavailable, record Not run and the concrete missing requirement. |
| A28 | On the test Mac, accept the internal tester invitation, install the build through TestFlight, launch it, and confirm **Kromora > About Kromora** or the app's version/build matches A27. Locate the installed app in Finder, set `KROMORA_APP` to that app path, and repeat A1's signature/entitlement and Activity Monitor checks plus A5, A10, A13, and A17. If a newer TestFlight build is available, install the update over the disposable test library and relaunch. | TestFlight installs and launches the signed sandboxed build; its own signature and entitlements verify, import, Photos delivery, export, and default-library reopen work. Updating preserves package photos and edits. Record any account, processing, invitation, install, or update failure separately from the local Xcode Release run. |

### Development workflow and CI release gate

These checks cover the SwiftPM and CI success criteria in the release plan. Record evidence for the
same source commit used to make the Xcode archive. They are required release evidence but do not
replace any signed-app cases above.

| ID | Action and UI path / command | Expected result |
| --- | --- | --- |
| A29 | Review the green CI results for the archive's source commit for `swift build`, `swift test`, `scripts/ci-tests.sh fast`, and `scripts/ci-tests.sh serial`. Confirm `swift run Kromora` launches in a disposable development profile on that revision. Record the CI run URL and commit. | All required development and CI checks pass on the archived source revision. `swift run` is recorded only as the development-launcher criterion, never as evidence of sandbox behavior. |

## 3. Results

Copy this section for each run. Use **Pass**, **Fail**, **Not run**, or **N/A** for every case ID;
attach screenshots or command output where useful. An N/A requires the reason and macOS version.

```text
Date and local time:
Tester:
Mac model / Apple Silicon chip:
macOS version and build:
Xcode version:
Build source: Xcode Release / TestFlight
Bundle ID: com.last8.kromora.photo
Marketing version:
Build number:
Signing team / identity:
App path or TestFlight build:
Disposable test account used: Yes / No

Case | Pass / Fail / Not run / N/A | Evidence, notes, or issue ID
A1   |
A2   |
A3   |
A4   |
A5   |
A6   |
A7   |
A8   |
A9   |
A10  |
A11  |
A12  |
A13  |
A14  |
A15  |
A16  |
A17  |
A18  |
A19  |
A20  |
A21  |
A22  |
A23  |
A24  |
A25  |
A26  |
A27  |
A28  |
A29  |
A30  |

Effective entitlement output (attach full `codesign -d --entitlements :-` output):
Activity Monitor Sandbox value and process PID:
Output sentinel hash before/after:
Photos access states available and exercised:
TestFlight version/build and update result:

Sandbox denial log excerpt (paste matching lines with timestamps and case IDs; write
"None observed" if the stream contained no Kromora denials):

Overall result: Pass / Fail / Incomplete
Open defects / DispatchGraph issue IDs:
```

## Source cross-check

- [App Store sandbox audit](APP_STORE_SANDBOX_AUDIT.md), section 1 runtime cases: A5–A10 and
  A17–A23; section 2 runtime cases: A13–A26. Section 3's packaged resource-bundle uncertainty:
  A2. Signed entitlement verification: A1 and A27.
- [Mac App Store release plan](../.context/2026-09-30-app-store-release-plan.md), success criteria:
  Release build/archive and TestFlight upload/install: A1 and A27–A28; sandbox launch, imports,
  exports, Photos, and persistent access: A5–A26 and A30; SwiftPM build/test/run and CI checks: A29. These
  development-lane checks do not substitute for the signed-app checks.
- The sandbox audit states that external adjacent RAW sidecars are not imported by the current
  import path. A9 records this boundary so it is not mistaken for supported sidecar preservation.
- The plan's two structural criteria—no production logic only in the Xcode target, and no retired
  direct-distribution/updater infrastructure—are repository review gates, not runtime sandbox
  behaviors. Confirm them in the release source/project review; a successful manual run cannot
  establish either one.
