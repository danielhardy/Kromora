import XCTest
import SwiftUI
import CoreImage
@testable import KromoraKit

/// Behavior of the keyboard dispatch table (`KeyboardCommandRouter`) that replaced the `NSEvent`
/// local monitor in KRMA-920. Responder-chain behavior (no alert beep, text fields keep typing) is
/// covered with a real window in `KeyRoutingProbeTests`.
@MainActor
final class KeyboardCommandRouterTests: TempDirectoryTestCase {

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

    private func waitForAutoAvailability(in viewModel: AppViewModel) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !viewModel.canRunAutoAdjustment {
            guard Date() < deadline else {
                throw TestSynchronizationError.timedOut(
                    "Auto to become available", "previewState=\(viewModel.previewState)"
                )
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func router(_ viewModel: AppViewModel) -> KeyboardCommandRouter {
        KeyboardCommandRouter(viewModel: viewModel)
    }

    private func press(
        _ router: KeyboardCommandRouter, _ key: KeyInput.Key,
        modifiers: EventModifiers = [], phase: KeyInput.Phase = .down
    ) -> Bool {
        router.perform(KeyInput(key, modifiers: modifiers, phase: phase))
    }

    private func grayImage() -> CIImage {
        CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
    }

    func testModifierMaskIgnoresCapsLockAndNumericPad() {
        let input = KeyInput(.arrow(.left), modifiers: [.capsLock, .numericPad])
        XCTAssertTrue(input.isPlain)
        XCTAssertFalse(input.hasSystemModifier)
        XCTAssertTrue(KeyInput(.arrow(.left), modifiers: .command).hasSystemModifier)
        XCTAssertFalse(KeyInput(.arrow(.left), modifiers: .shift).hasSystemModifier)
        XCTAssertFalse(KeyInput(.arrow(.left), modifiers: .shift).isPlain)
    }

    func testSurfaceMapsOnlyTheKeysItOwns() {
        // Letters are menu key equivalents, never claimed by the surface.
        XCTAssertNil(KeyboardSurface.input(key: "c", modifiers: [], phase: .down))
        XCTAssertEqual(
            KeyboardSurface.input(key: .leftArrow, modifiers: .shift, phase: .up),
            KeyInput(.arrow(.left), modifiers: .shift, phase: .up)
        )
        XCTAssertEqual(
            KeyboardSurface.input(key: .rightArrow, modifiers: [], phase: .repeat)?.phase, .down,
            "auto-repeat navigates like a key-down"
        )
        XCTAssertEqual(
            KeyboardSurface.input(key: "\\", modifiers: .command, phase: .down),
            KeyInput(.character("\\"), modifiers: .command)
        )
        XCTAssertEqual(KeyboardSurface.input(key: .space, modifiers: [], phase: .down)?.key, .space)
        XCTAssertEqual(KeyboardSurface.input(key: .deleteForward, modifiers: [], phase: .down)?.key, .forwardDelete)
    }

    func testOwnershipLeavesTextAndValueEditorsTheirKeys() {
        for key in [KeyInput.Key.arrow(.left), .space, .return, .delete, .escape, .character("\\")] {
            XCTAssertFalse(KeyboardOwnership.surfaceOwns(key, firstResponder: NSText()), "\(key)")
            XCTAssertFalse(KeyboardOwnership.surfaceOwns(key, firstResponder: NSTextField()), "\(key)")
            XCTAssertTrue(KeyboardOwnership.surfaceOwns(key, firstResponder: NSView()), "\(key)")
            XCTAssertTrue(KeyboardOwnership.surfaceOwns(key, firstResponder: nil), "\(key)")
        }
        for slider in [NSSlider(), NSStepper()] as [NSControl] {
            XCTAssertFalse(KeyboardOwnership.surfaceOwns(.arrow(.right), firstResponder: slider))
            XCTAssertTrue(KeyboardOwnership.surfaceOwns(.delete, firstResponder: slider))
        }
        // Buttons, pickers and lists do not edit with arrows, so photo/Look navigation keeps them.
        for control in [NSButton(), NSSegmentedControl(), NSPopUpButton(), NSTableView()] as [NSResponder] {
            XCTAssertTrue(KeyboardOwnership.surfaceOwns(.arrow(.right), firstResponder: control))
            XCTAssertTrue(KeyboardOwnership.surfaceOwns(.arrow(.down), firstResponder: control))
        }
        // …but Space/Return activate a focused button.
        XCTAssertFalse(KeyboardOwnership.surfaceOwns(.space, firstResponder: NSButton()))
        XCTAssertFalse(KeyboardOwnership.surfaceOwns(.return, firstResponder: NSPopUpButton()))
        XCTAssertFalse(KeyboardOwnership.surfaceOwns(.space, firstResponder: NSTableView()), "a focused list handles Space itself")
    }

    func testArrowNavigationClaimsKeyDownAndKeyUpAtMiddleAndCollectionBoundaries() async throws {
        for name in ["first.png", "middle.png", "third.png"] {
            try Fixtures.writeGradientPNG(width: 8, height: 8, named: name, in: tempDirectory)
        }
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        XCTAssertEqual(viewModel.collection.items.count, 3)
        viewModel.collection.setSelection(at: 1)
        XCTAssertTrue(viewModel.navigate(to: .edit))
        let router = router(viewModel)

        XCTAssertTrue(press(router, .arrow(.left)))
        XCTAssertEqual(viewModel.collection.selectedIndex, 0, "Left should move once")
        XCTAssertTrue(press(router, .arrow(.left), phase: .up))
        XCTAssertEqual(viewModel.collection.selectedIndex, 0, "key-up must not navigate again")
        XCTAssertTrue(press(router, .arrow(.left)))
        XCTAssertEqual(viewModel.collection.selectedIndex, 0, "Left at the first image is a claimed no-op")

        viewModel.collection.setSelection(at: 2)
        XCTAssertTrue(press(router, .arrow(.right)))
        XCTAssertEqual(viewModel.collection.selectedIndex, 2, "Right at the last image is a claimed no-op")
        XCTAssertTrue(press(router, .arrow(.right), phase: .up))
    }

    func testSystemModifiedArrowsBelongToAppKit() throws {
        let router = router(makeAppViewModel(engine: FakeRenderEngine()))
        for modifier in [EventModifiers.command, .option, .control] {
            XCTAssertFalse(press(router, .arrow(.left), modifiers: modifier))
            XCTAssertFalse(press(router, .arrow(.down), modifiers: modifier))
        }
    }

    func testUpAndDownAuditionLooksIncludingNone() async throws {
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
        let router = router(viewModel)

        XCTAssertTrue(press(router, .arrow(.right)))
        XCTAssertEqual(viewModel.collection.selectedIndex, 1)

        XCTAssertNil(viewModel.selectedLookID)
        XCTAssertTrue(press(router, .arrow(.down)))
        XCTAssertEqual(viewModel.selectedLookID, firstLook.lutID)
        XCTAssertTrue(press(router, .arrow(.down)))
        XCTAssertEqual(viewModel.selectedLookID, secondLook.lutID)
        XCTAssertTrue(press(router, .arrow(.up)))
        XCTAssertEqual(viewModel.selectedLookID, firstLook.lutID)
        XCTAssertTrue(press(router, .arrow(.up)))
        XCTAssertNil(viewModel.selectedLookID, "Up from the first Look must land on None")
        XCTAssertTrue(press(router, .arrow(.up), phase: .up))
        XCTAssertTrue(viewModel.isLookNoneSelected)
    }

    func testCommandBackslashKeyDownAndKeyUpFlashOriginal() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.sourceImage = grayImage()
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        let router = router(viewModel)

        XCTAssertTrue(press(router, .character("\\"), modifiers: .command))
        XCTAssertTrue(viewModel.isShowingOriginal)
        XCTAssertTrue(router.commandBackslashIsHeld)

        // Release Command first: the held-shortcut state still restores Edited on the Backslash
        // key-up instead of leaving the transient preview armed.
        XCTAssertTrue(press(router, .character("\\"), phase: .up))
        XCTAssertFalse(viewModel.isShowingOriginal)
        XCTAssertFalse(router.commandBackslashIsHeld)
    }

    func testUnavailableOrBareBackslashDoesNotChangeOriginalState() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let router = router(viewModel)

        XCTAssertFalse(press(router, .character("\\"), modifiers: .command))
        XCTAssertFalse(viewModel.isShowingOriginal)
        XCTAssertFalse(press(router, .character("\\")))
        XCTAssertFalse(viewModel.isShowingOriginal)
        XCTAssertFalse(press(router, .character("\\"), phase: .up), "a stray key-up is not ours")
    }

    func testCropShortcutIsPlainCOnly() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let router = router(viewModel)
        XCTAssertFalse(press(router, .character("c")), "no photo, nothing to crop")

        viewModel.sourceImage = grayImage()
        for modifier in [EventModifiers.shift, .command, .option, .control] {
            XCTAssertFalse(press(router, .character("c"), modifiers: modifier))
        }
        XCTAssertFalse(viewModel.isCropToolActive)
        XCTAssertTrue(press(router, .character("c")))
        XCTAssertTrue(viewModel.isCropToolActive)
        XCTAssertFalse(press(router, .character("x")), "culling needs an active collection")
    }

    func testPlainIAndOnlyPlainIWithAnOpenPhotoTogglesCaptureOverlay() async throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let router = router(viewModel)
        let togglePosted = expectation(description: "capture overlay toggle")
        togglePosted.assertForOverFulfill = true
        let token = NotificationCenter.default.addObserver(
            forName: .toggleCaptureMetadataOverlay, object: nil, queue: nil
        ) { _ in togglePosted.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        XCTAssertFalse(press(router, .character("i")), "without a photo, I is not claimed")
        viewModel.sourceImage = grayImage()
        XCTAssertTrue(press(router, .character("i")))
        await fulfillment(of: [togglePosted], timeout: 0.1)

        XCTAssertFalse(press(router, .character("i"), modifiers: .command), "⌘I is the Info Inspector")
        XCTAssertFalse(press(router, .character("i"), modifiers: .shift))
    }

    func testCropEscapeCancelsAndReturnCommits() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.sourceImage = grayImage()
        let router = router(viewModel)

        viewModel.beginCrop()
        viewModel.updateCropDraft(CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6))
        XCTAssertTrue(viewModel.isCropToolActive)
        XCTAssertTrue(press(router, .escape))
        XCTAssertFalse(viewModel.isCropToolActive)
        XCTAssertTrue(viewModel.document.crop.isIdentity)

        viewModel.beginCrop()
        viewModel.updateCropDraft(CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6))
        XCTAssertTrue(press(router, .return))
        XCTAssertFalse(viewModel.isCropToolActive)
        XCTAssertEqual(
            viewModel.document.crop,
            CropAdjustments(normalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6))
        )
        XCTAssertFalse(press(router, .escape), "with nothing to cancel Esc is left to AppKit")
    }

    func testRetouchShortcutsArmCycleOverlayAndExitInTwoSteps() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.sourceImage = grayImage()
        XCTAssertTrue(viewModel.navigate(to: .edit))
        let router = router(viewModel)

        XCTAssertTrue(press(router, .character("q")))
        XCTAssertTrue(viewModel.isRetouchCanvasActive)
        XCTAssertEqual(viewModel.retouchInteractionState.overlayPolicy, .auto)
        XCTAssertTrue(press(router, .character("h")))
        XCTAssertEqual(viewModel.retouchInteractionState.overlayPolicy, .always)
        let initialRadius = viewModel.retouchInteractionState.radius
        XCTAssertTrue(press(router, .character("[")))
        XCTAssertLessThan(viewModel.retouchInteractionState.radius, initialRadius)

        viewModel.retouchInteractionState.select(UUID())
        XCTAssertTrue(press(router, .escape))
        XCTAssertNil(viewModel.retouchInteractionState.selectedSpotID)
        XCTAssertTrue(viewModel.isRetouchCanvasActive)
        XCTAssertTrue(press(router, .escape))
        XCTAssertFalse(viewModel.retouchInteractionState.isArmed)
    }

    func testArmingRetouchClosesAnActiveCropSoOnlyOneCanvasToolOwnsInputAtATime() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.sourceImage = grayImage()
        XCTAssertTrue(viewModel.navigate(to: .edit))
        let router = router(viewModel)

        viewModel.beginCrop()
        viewModel.updateCropDraft(CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6))
        XCTAssertTrue(viewModel.isCropToolActive)

        XCTAssertTrue(press(router, .character("q")))
        XCTAssertTrue(viewModel.isRetouchCanvasActive)
        XCTAssertFalse(viewModel.isCropToolActive)
    }

    func testSheetsSuppressShortcutsButStillClaimTheKey() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.sourceImage = grayImage()
        viewModel.isSelectiveCopyDialogPresented = true
        let router = router(viewModel)

        // Claimed as an intentional no-op: a menu key equivalent that reaches the router while a
        // sheet is up must not fall back to the system alert.
        XCTAssertTrue(press(router, .character("c")))
        XCTAssertFalse(viewModel.isCropToolActive)
        XCTAssertTrue(press(router, .arrow(.left)))
        XCTAssertTrue(press(router, .space))
    }

    func testSpaceComparesOriginalOnlyWhenComparisonIsAvailable() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let router = router(viewModel)
        XCTAssertFalse(press(router, .space), "no photo: Space continues through")
        XCTAssertFalse(press(router, .space, modifiers: .shift))

        viewModel.sourceImage = grayImage()
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        XCTAssertTrue(press(router, .space))
        XCTAssertTrue(viewModel.isShowingOriginal)
        XCTAssertTrue(press(router, .space, phase: .up))
        XCTAssertFalse(viewModel.isShowingOriginal)
    }

    func testCharacterShortcutsDeclineWithSystemModifiers() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.sourceImage = grayImage()
        let router = router(viewModel)
        for modifier in [EventModifiers.command, .option, .control] {
            for character in ["c", "q", "g", "e", "v", "[", "]", "i"] {
                XCTAssertFalse(press(router, .character(character), modifiers: modifier), character)
            }
        }
    }
}
