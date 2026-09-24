import XCTest
import CoreImage
import AppKit
@testable import KromoraKit

/// The one behaviour Step 8 changed.
///
/// `KeyMonitor` removed its `NSEvent` monitor in `deinit`. Swift 6 language mode makes a `deinit`
/// `nonisolated` — it can run on any thread — so it may not touch the `Any?` token AppKit hands back,
/// which is not `Sendable`. The escape hatches are `nonisolated(unsafe)` and `@unchecked Sendable`,
/// and this module uses neither, so teardown became an explicit `stop()` on the main actor.
///
/// That is the *better* shape regardless of the compiler: `NSEvent.removeMonitor` is an AppKit call
/// that wants the main thread, and reaching it from a `deinit` that could run anywhere was always
/// the wrong place for it.
///
/// **What this cannot cover:** that `KeyboardShortcuts.onDisappear` actually calls `stop()`. That is
/// a SwiftUI view body, and `docs/ENGINEERING_GUIDE.md` already records that views are exercised only
/// insofar as the view model is. The lifecycle contract below is the testable half; the wiring was
/// checked by hand in the running app.
@MainActor
final class KeyMonitorTests: TempDirectoryTestCase {

    /// Records what was torn down. `isMonitoring` on its own is not enough: it reports whether the
    /// token was cleared, and a `stop()` that cleared the token *without* calling
    /// `NSEvent.removeMonitor` would leak the monitor and still pass. A mutation proved exactly that,
    /// which is why `KeyMonitor` takes the removal as a parameter.
    private final class Removals {
        var tokens: [Any] = []
        var count: Int { tokens.count }
    }

    private func makeMonitor(_ removals: Removals) -> KeyMonitor {
        KeyMonitor(
            viewModel: makeAppViewModel(engine: FakeRenderEngine()),
            removeMonitor: { removals.tokens.append($0) }
        )
    }

    private func importedPhoto(named name: String) throws -> (name: String, data: Data) {
        let url = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: name, in: tempDirectory
        )
        return (name, try Data(contentsOf: url))
    }

    private func makeKeyboardViewModel(libraryName: String) -> AppViewModel {
        makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: makeInMemoryEditStore(),
            portablePackageURL: tempDirectory.appendingPathComponent(
                "\(libraryName).kromoralibrary", isDirectory: true
            )
        )
    }

    private func waitForSource(_ name: String, in viewModel: AppViewModel) async throws {
        let deadline = Date().addingTimeInterval(5)
        while viewModel.sourceName != name {
            guard Date() < deadline else {
                throw TestSynchronizationError.timedOut(
                    "source \(name) to open", "sourceName=\(viewModel.sourceName)"
                )
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func keyEvent(
        _ type: NSEvent.EventType,
        keyCode: UInt16,
        isARepeat: Bool = false,
        modifierFlags: NSEvent.ModifierFlags = [],
        characters: String = "",
        charactersIgnoringModifiers: String? = nil
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers ?? characters,
            isARepeat: isARepeat,
            keyCode: keyCode
        ))
    }

    func testAMonitorIsInstalledOnInitAndRemovedByStop() {
        let removals = Removals()
        let monitor = makeMonitor(removals)
        XCTAssertTrue(monitor.isMonitoring, "the monitor should be live as soon as it exists")
        XCTAssertEqual(removals.count, 0, "nothing should have been torn down yet")

        monitor.stop()
        XCTAssertFalse(monitor.isMonitoring, "stop() must clear the token")
        XCTAssertEqual(removals.count, 1, "…and must actually remove the monitor, not just forget it")
    }

    /// `onDisappear` can fire more than once, and a released view could stop a monitor that a
    /// later one already stopped. `NSEvent.removeMonitor` on a stale token is not something to find
    /// out about at runtime.
    func testStopIsIdempotent() {
        let removals = Removals()
        let monitor = makeMonitor(removals)
        monitor.stop()
        monitor.stop()
        XCTAssertFalse(monitor.isMonitoring)
        XCTAssertEqual(removals.count, 1, "a second stop() must not remove a stale token")
    }

    /// Dropping the last reference without stopping must not crash — it simply leaks the monitor
    /// until the process exits, which is the trade the `deinit` removal makes explicit.
    func testDroppingAMonitorWithoutStoppingIsSafe() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        for _ in 0..<3 {
            let monitor = KeyMonitor(viewModel: viewModel)
            XCTAssertTrue(monitor.isMonitoring)
        }
        // Reaching here at all is the assertion: a `deinit` that still touched AppKit state from
        // an arbitrary thread is what Swift 6 was objecting to.
        XCTAssertTrue(true)
    }

    func testGlobalShortcutsDeferToTextInputAndSystemModifiers() {
        XCTAssertTrue(KeyMonitorPolicy.textInputOwnsKeyboard(NSText()))
        XCTAssertFalse(KeyMonitorPolicy.textInputOwnsKeyboard(NSView()))

        XCTAssertFalse(KeyMonitorPolicy.globalShortcutsOwnKeyboard(NSText()))
        XCTAssertFalse(KeyMonitorPolicy.globalShortcutsOwnKeyboard(NSTextField()))
        XCTAssertFalse(KeyMonitorPolicy.globalShortcutsOwnKeyboard(NSSlider()))
        XCTAssertFalse(KeyMonitorPolicy.globalShortcutsOwnKeyboard(NSButton()))
        XCTAssertFalse(KeyMonitorPolicy.globalShortcutsOwnKeyboard(NSSegmentedControl()))
        XCTAssertTrue(KeyMonitorPolicy.globalShortcutsOwnKeyboard(NSView()))
        XCTAssertTrue(KeyMonitorPolicy.globalShortcutsOwnKeyboard(nil))

        XCTAssertTrue(KeyMonitorPolicy.isPlainSpace(modifiers: []))
        XCTAssertFalse(KeyMonitorPolicy.isPlainSpace(modifiers: .shift))
        XCTAssertFalse(KeyMonitorPolicy.isPlainSpace(modifiers: .option))
        XCTAssertFalse(KeyMonitorPolicy.isPlainSpace(modifiers: .control))

        XCTAssertFalse(KeyMonitorPolicy.hasSystemModifier(.shift))
        XCTAssertTrue(KeyMonitorPolicy.hasSystemModifier(.option))
        XCTAssertTrue(KeyMonitorPolicy.hasSystemModifier(.control))
        XCTAssertTrue(KeyMonitorPolicy.hasSystemModifier(.command))

        XCTAssertTrue(KeyMonitorPolicy.isPlainCharacterShortcut(modifiers: []))
        XCTAssertFalse(KeyMonitorPolicy.isPlainCharacterShortcut(modifiers: .shift))
        XCTAssertFalse(KeyMonitorPolicy.isPlainCharacterShortcut(modifiers: .command))
    }

    func testPlainCommandCopyAndPasteRouteOnlyWhenGlobalSurfaceOwnsKeyboard() async throws {
        let viewModel = makeKeyboardViewModel(libraryName: "keyboard-copy")
        viewModel.importPhotosData([try importedPhoto(named: "keyboard-copy.png")])
        try await waitForSource("keyboard-copy.png", in: viewModel)

        let copyEvent = try keyEvent(
            .keyDown, keyCode: 8, modifierFlags: .command,
            characters: "c", charactersIgnoringModifiers: "c"
        )
        let pasteEvent = try keyEvent(
            .keyDown, keyCode: 9, modifierFlags: .command,
            characters: "v", charactersIgnoringModifiers: "v"
        )
        let sourceEdits = EditDocument(adjustments: [.exposure(ev: 0.4)])
        viewModel.updateDocument { $0 = sourceEdits }

        let globalMonitor = KeyMonitor(viewModel: viewModel)
        defer { globalMonitor.stop() }
        XCTAssertNil(globalMonitor.handle(copyEvent))
        XCTAssertTrue(viewModel.isSelectiveCopyDialogPresented)

        // Confirming the dialog supplies the clipboard state that ⌘V consumes below.
        viewModel.confirmSelectiveCopy()
        viewModel.updateDocument { $0 = EditDocument() }
        XCTAssertNil(globalMonitor.handle(pasteEvent))
        XCTAssertEqual(viewModel.document, sourceEdits)

        let textViewModel = makeKeyboardViewModel(libraryName: "keyboard-text-focus")
        textViewModel.importPhotosData([try importedPhoto(named: "keyboard-text-focus.png")])
        try await waitForSource("keyboard-text-focus.png", in: textViewModel)
        let textMonitor = KeyMonitor(
            viewModel: textViewModel,
            firstResponderProvider: { _ in NSText() }
        )
        defer { textMonitor.stop() }
        XCTAssertNotNil(textMonitor.handle(copyEvent))
        XCTAssertFalse(textViewModel.isSelectiveCopyDialogPresented)
        XCTAssertNotNil(textMonitor.handle(pasteEvent))

        // A native control also keeps plain ⌘C/⌘V. There is no plain-⌘C menu binding, so the
        // event falls through unchanged; the explicit toolbar/menu Copy Edits… action remains
        // available. This is intentional AppKit focus behavior, not a silent copy failure.
        let controlViewModel = makeKeyboardViewModel(libraryName: "keyboard-control-focus")
        controlViewModel.importPhotosData([try importedPhoto(named: "keyboard-control-focus.png")])
        try await waitForSource("keyboard-control-focus.png", in: controlViewModel)
        let controlMonitor = KeyMonitor(
            viewModel: controlViewModel,
            firstResponderProvider: { _ in NSButton() }
        )
        defer { controlMonitor.stop() }
        XCTAssertNotNil(controlMonitor.handle(copyEvent))
        XCTAssertFalse(controlViewModel.isSelectiveCopyDialogPresented)
        XCTAssertNotNil(controlMonitor.handle(pasteEvent))
    }

    func testImageNavigationOwnershipConsumesDownAndUpIncludingBoundaries() {
        for keyCode in [UInt16(123), UInt16(124)] {
            XCTAssertTrue(KeyMonitorPolicy.imageNavigationOwnsKeyboard(
                keyCode: keyCode, eventType: .keyDown, responder: nil
            ))
            XCTAssertTrue(KeyMonitorPolicy.imageNavigationOwnsKeyboard(
                keyCode: keyCode, eventType: .keyUp, responder: NSView()
            ))
            XCTAssertTrue(KeyMonitorPolicy.imageNavigationOwnsKeyboard(
                keyCode: keyCode, eventType: .keyDown, responder: NSButton()
            ))
            XCTAssertTrue(KeyMonitorPolicy.imageNavigationOwnsKeyboard(
                keyCode: keyCode, eventType: .keyUp, responder: NSTableView()
            ))
        }

        XCTAssertFalse(KeyMonitorPolicy.imageNavigationOwnsKeyboard(
            keyCode: 36, eventType: .keyDown, responder: nil
        ))
        XCTAssertFalse(KeyMonitorPolicy.imageNavigationOwnsKeyboard(
            keyCode: 123, eventType: .keyDown, responder: NSSlider()
        ))
        XCTAssertFalse(KeyMonitorPolicy.imageNavigationOwnsKeyboard(
            keyCode: 124, eventType: .keyUp, responder: NSTextField()
        ))
    }

    func testLookNavigationOwnershipConsumesListAndButtonFocus() {
        for keyCode in [UInt16(125), UInt16(126)] {
            XCTAssertTrue(KeyMonitorPolicy.lookNavigationOwnsKeyboard(
                keyCode: keyCode, eventType: .keyDown, responder: nil
            ))
            XCTAssertTrue(KeyMonitorPolicy.lookNavigationOwnsKeyboard(
                keyCode: keyCode, eventType: .keyUp, responder: NSButton()
            ))
            XCTAssertTrue(KeyMonitorPolicy.lookNavigationOwnsKeyboard(
                keyCode: keyCode, eventType: .keyDown, responder: NSTableView()
            ))
            XCTAssertFalse(KeyMonitorPolicy.lookNavigationOwnsKeyboard(
                keyCode: keyCode, eventType: .keyDown, responder: NSSlider()
            ))
        }
        XCTAssertFalse(KeyMonitorPolicy.lookNavigationOwnsKeyboard(
            keyCode: 123, eventType: .keyDown, responder: nil
        ))
        XCTAssertTrue(KeyMonitorPolicy.isArrowKey(126))
        XCTAssertFalse(KeyMonitorPolicy.isArrowKey(36))
        XCTAssertTrue(KeyMonitorPolicy.valueEditingControlOwnsArrows(NSSlider()))
        XCTAssertFalse(KeyMonitorPolicy.valueEditingControlOwnsArrows(NSButton()))
        XCTAssertFalse(KeyMonitorPolicy.valueEditingControlOwnsArrows(NSTableView()))
        XCTAssertFalse(KeyMonitorPolicy.valueEditingControlOwnsArrows(NSSegmentedControl()))
        XCTAssertFalse(KeyMonitorPolicy.valueEditingControlOwnsArrows(NSPopUpButton()))
    }

    func testArrowNavigationConsumesKeyDownAndKeyUpAtMiddleAndCollectionBoundaries() async throws {
        for name in ["first.png", "middle.png", "third.png"] {
            try Fixtures.writeGradientPNG(width: 8, height: 8, named: name, in: tempDirectory)
        }

        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        XCTAssertEqual(viewModel.collection.items.count, 3)
        viewModel.collection.setSelection(at: 1)
        XCTAssertTrue(viewModel.navigate(to: .edit))

        let monitor = KeyMonitor(viewModel: viewModel)
        defer { monitor.stop() }

        XCTAssertNil(monitor.handle(try keyEvent(.keyDown, keyCode: 123)))
        XCTAssertEqual(viewModel.collection.selectedIndex, 0, "Left should move once")
        XCTAssertNil(monitor.handle(try keyEvent(.keyUp, keyCode: 123)))
        XCTAssertEqual(viewModel.collection.selectedIndex, 0, "key-up must not navigate again")

        XCTAssertNil(monitor.handle(try keyEvent(.keyDown, keyCode: 123, isARepeat: true)))
        XCTAssertEqual(viewModel.collection.selectedIndex, 0, "repeated Left at the first image is a no-op")

        viewModel.collection.setSelection(at: 2)
        XCTAssertNil(monitor.handle(try keyEvent(.keyDown, keyCode: 124)))
        XCTAssertEqual(viewModel.collection.selectedIndex, 2, "Right at the last image is a no-op")
        XCTAssertNil(monitor.handle(try keyEvent(.keyUp, keyCode: 124)))
        XCTAssertNil(monitor.handle(try keyEvent(.keyDown, keyCode: 124, isARepeat: true)))
        XCTAssertEqual(viewModel.collection.selectedIndex, 2, "repeated Right at the last image is silent and stable")
    }

    func testArrowNavigationDefersToFocusedNativeControl() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let slider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
        let monitor = KeyMonitor(
            viewModel: viewModel,
            firstResponderProvider: { _ in slider }
        )
        defer { monitor.stop() }

        let event = try keyEvent(.keyDown, keyCode: 123)
        XCTAssertNotNil(monitor.handle(event), "a focused slider owns Left and must receive it")
        XCTAssertEqual(viewModel.collection.selectedIndex, 0)
    }

    func testArrowNavigationConsumesEventsWhenWorkspacePickerHasFocus() async throws {
        for name in ["first.png", "second.png"] {
            try Fixtures.writeGradientPNG(width: 8, height: 8, named: name, in: tempDirectory)
        }
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        viewModel.collection.setSelection(at: 0)
        XCTAssertTrue(viewModel.navigate(to: .edit))

        let picker = NSSegmentedControl(
            labels: ["Library", "Edit"], trackingMode: .selectOne, target: nil, action: nil
        )
        let monitor = KeyMonitor(
            viewModel: viewModel,
            firstResponderProvider: { _ in picker }
        )
        defer { monitor.stop() }

        XCTAssertNil(monitor.handle(try keyEvent(.keyDown, keyCode: 124)))
        XCTAssertEqual(viewModel.collection.selectedIndex, 1)
        XCTAssertNil(monitor.handle(try keyEvent(.keyUp, keyCode: 124)))
        XCTAssertNil(monitor.handle(try keyEvent(.keyDown, keyCode: 125)))
        XCTAssertNil(monitor.handle(try keyEvent(.keyUp, keyCode: 125)))
    }

    func testArrowNavigationConsumesEventsWhenAButtonOrListHasFocus() async throws {
        for name in ["first.png", "second.png"] {
            try Fixtures.writeGradientPNG(width: 8, height: 8, named: name, in: tempDirectory)
        }
        let lookFolder = tempDirectory.appendingPathComponent("audition-looks")
        try FileManager.default.createDirectory(at: lookFolder, withIntermediateDirectories: true)
        let firstLookURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "01 First.cube", in: lookFolder
        )
        let secondLookURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "02 Second.cube", in: lookFolder
        )
        let firstLook = try CubeLUT(url: firstLookURL)
        let secondLook = try CubeLUT(url: secondLookURL)

        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        viewModel.collection.setSelection(at: 0)
        XCTAssertTrue(viewModel.navigate(to: .edit))
        viewModel.library.setFolder(lookFolder)
        while viewModel.library.isScanning { try await Task.sleep(for: .milliseconds(10)) }

        let button = NSButton(title: "thumb", target: nil, action: nil)
        let buttonMonitor = KeyMonitor(
            viewModel: viewModel,
            firstResponderProvider: { _ in button }
        )
        defer { buttonMonitor.stop() }

        XCTAssertNil(buttonMonitor.handle(try keyEvent(.keyDown, keyCode: 124)))
        XCTAssertEqual(viewModel.collection.selectedIndex, 1)
        XCTAssertNil(buttonMonitor.handle(try keyEvent(.keyUp, keyCode: 124)))

        let table = NSTableView()
        let listMonitor = KeyMonitor(
            viewModel: viewModel,
            firstResponderProvider: { _ in table }
        )
        defer { listMonitor.stop() }

        XCTAssertNil(viewModel.selectedLookID)
        XCTAssertNil(listMonitor.handle(try keyEvent(.keyDown, keyCode: 125)))
        XCTAssertEqual(viewModel.selectedLookID, firstLook.lutID)
        XCTAssertNil(listMonitor.handle(try keyEvent(.keyDown, keyCode: 125)))
        XCTAssertEqual(viewModel.selectedLookID, secondLook.lutID)
        XCTAssertNil(listMonitor.handle(try keyEvent(.keyDown, keyCode: 126)))
        XCTAssertEqual(viewModel.selectedLookID, firstLook.lutID)
        XCTAssertNil(listMonitor.handle(try keyEvent(.keyDown, keyCode: 126)))
        XCTAssertNil(viewModel.selectedLookID, "Up from the first Look must land on None")
        XCTAssertNil(listMonitor.handle(try keyEvent(.keyUp, keyCode: 126)))
        XCTAssertTrue(viewModel.isLookNoneSelected)
    }

    func testCommandBackslashIsTheOnlyOriginalShortcut() {
        XCTAssertTrue(KeyMonitorPolicy.isCommandBackslashShortcut(keyCode: 42, modifiers: .command))
        XCTAssertFalse(KeyMonitorPolicy.isCommandBackslashShortcut(keyCode: 42, modifiers: []))
        XCTAssertFalse(KeyMonitorPolicy.isCommandBackslashShortcut(keyCode: 42, modifiers: [.command, .shift]))
        XCTAssertFalse(KeyMonitorPolicy.isCommandBackslashShortcut(keyCode: 42, modifiers: [.command, .option]))
        XCTAssertFalse(KeyMonitorPolicy.isCommandBackslashShortcut(keyCode: 41, modifiers: .command))
    }

    func testCommandBackslashKeyDownAndKeyUpFlashOriginal() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.sourceImage = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        let monitor = KeyMonitor(viewModel: viewModel)
        defer { monitor.stop() }

        let down = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\\",
            charactersIgnoringModifiers: "\\",
            isARepeat: false,
            keyCode: 42
        ))
        XCTAssertNil(monitor.handle(down))
        XCTAssertTrue(viewModel.isShowingOriginal)

        // Release Command first: the monitor's held-shortcut state still restores Edited on the
        // Backslash key-up instead of leaving the transient preview armed.
        let up = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0.1,
            windowNumber: 0,
            context: nil,
            characters: "\\",
            charactersIgnoringModifiers: "\\",
            isARepeat: false,
            keyCode: 42
        ))
        XCTAssertNil(monitor.handle(up))
        XCTAssertFalse(viewModel.isShowingOriginal)
    }

    func testUnavailableOrBareBackslashDoesNotChangeOriginalState() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let monitor = KeyMonitor(viewModel: viewModel)
        defer { monitor.stop() }

        let commandBackslash = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\\",
            charactersIgnoringModifiers: "\\",
            isARepeat: false,
            keyCode: 42
        ))
        XCTAssertNotNil(monitor.handle(commandBackslash))
        XCTAssertFalse(viewModel.isShowingOriginal)

        let bareBackslash = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0.1,
            windowNumber: 0,
            context: nil,
            characters: "\\",
            charactersIgnoringModifiers: "\\",
            isARepeat: false,
            keyCode: 42
        ))
        XCTAssertNotNil(monitor.handle(bareBackslash))
        XCTAssertFalse(viewModel.isShowingOriginal)
    }

    func testCropShortcutIsPlainCOnly() {
        XCTAssertTrue(KeyMonitorPolicy.isCropShortcut(characters: "c", modifiers: []))
        XCTAssertTrue(KeyMonitorPolicy.isCropShortcut(characters: "C", modifiers: []))
        XCTAssertFalse(KeyMonitorPolicy.isCropShortcut(characters: "x", modifiers: []))
        XCTAssertFalse(KeyMonitorPolicy.isCropShortcut(characters: "c", modifiers: .shift))
        XCTAssertFalse(KeyMonitorPolicy.isCropShortcut(characters: "c", modifiers: .command))
        XCTAssertFalse(KeyMonitorPolicy.isCropShortcut(characters: "c", modifiers: .option))
        XCTAssertFalse(KeyMonitorPolicy.isCropShortcut(characters: "c", modifiers: .control))
    }

    func testCropEscapeCancelsAndReturnCommitsThroughKeyboardMonitor() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.sourceImage = CIImage(color: .gray).cropped(
            to: CGRect(x: 0, y: 0, width: 8, height: 8)
        )
        let monitor = KeyMonitor(viewModel: viewModel)
        defer { monitor.stop() }

        viewModel.beginCrop()
        viewModel.updateCropDraft(CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6))
        XCTAssertTrue(viewModel.isCropToolActive)
        XCTAssertNil(monitor.handle(try keyEvent(.keyDown, keyCode: 53)))
        XCTAssertFalse(viewModel.isCropToolActive)
        XCTAssertTrue(viewModel.document.crop.isIdentity)

        viewModel.beginCrop()
        viewModel.updateCropDraft(CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6))
        XCTAssertNil(monitor.handle(try keyEvent(.keyDown, keyCode: 36)))
        XCTAssertFalse(viewModel.isCropToolActive)
        XCTAssertEqual(
            viewModel.document.crop,
            CropAdjustments(normalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6))
        )
    }
}
