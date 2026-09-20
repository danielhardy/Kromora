import XCTest
@testable import KromoraKit

final class EditClipboardTests: XCTestCase {
    func testClipboardKeepsFutureCopyCategoriesSeparate() throws {
        let document = EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 0.75, neutralTemperature: 5900),
            adjustments: [
                .vibrance(amount: 0.4),
                .highlightShadow(highlights: 0.8, shadows: 0.2),
                .exposure(ev: 1.1),
            ],
            lut: LUTSettings(lutID: LUTID(raw: "look.cube"), intensity: 0.65)
        )

        let clipboard = EditClipboardPayload(document: document)
        XCTAssertEqual(
            clipboard.light.adjustments,
            [.exposure(ev: 1.1), .highlightShadow(highlights: 0.8, shadows: 0.2)]
        )
        XCTAssertEqual(clipboard.color.adjustments, [.vibrance(amount: 0.4)])
        XCTAssertTrue(clipboard.effects.adjustments.isEmpty)
        XCTAssertEqual(clipboard.crop, .neutral)
        XCTAssertEqual(clipboard.lut, document.lut)
        XCTAssertEqual(clipboard.develop, document.rawDevelop)
        XCTAssertEqual(clipboard.developPolicy, .copyExplicitSettings)

        let data = try JSONEncoder().encode(clipboard)
        XCTAssertEqual(try JSONDecoder().decode(EditClipboardPayload.self, from: data), clipboard)
    }

    func testSelectiveApplicationReplacesOnlyTheChosenCategories() {
        let clipboard = EditClipboardPayload(
            light: .init(adjustments: [.exposure(ev: 1)]),
            color: .init(adjustments: [.vibrance(amount: 0.5)]),
            lut: LUTSettings(lutID: LUTID(raw: "copied.cube"), intensity: 0.8)
        )
        let destination = EditDocument(
            adjustments: [.exposure(ev: -1), .vibrance(amount: -0.5)],
            lut: LUTSettings(lutID: LUTID(raw: "old.cube"), intensity: 0.2)
        )

        let result = clipboard.applying(
            to: destination,
            destinationIsRAW: false,
            categories: [.light]
        )
        XCTAssertEqual(result.adjustments, [.exposure(ev: 1), .vibrance(amount: -0.5)])
        XCTAssertEqual(result.lut, destination.lut)
    }

    func testRAWDevelopCopiesExplicitEditsButPreservesThemForJPEGDestinations() {
        let clipboard = EditClipboardPayload(
            develop: RAWDevelopSettings(exposure: 1.25, baselineExposure: nil),
            developPolicy: .copyExplicitSettings
        )
        let rawDestination = EditDocument(
            rawDevelop: RAWDevelopSettings(baselineExposure: 0.42)
        )
        let rawResult = clipboard.applying(to: rawDestination, destinationIsRAW: true)
        XCTAssertEqual(rawResult.rawDevelop, clipboard.develop)
        XCTAssertNil(rawResult.rawDevelop.baselineExposure,
                     "a source nil means decoder default, not a source-specific seed")

        let jpegDestination = EditDocument(
            rawDevelop: RAWDevelopSettings(baselineExposure: 0.42)
        )
        let jpegResult = clipboard.applying(to: jpegDestination, destinationIsRAW: false)
        XCTAssertEqual(jpegResult.rawDevelop, jpegDestination.rawDevelop,
                       "RAW controls must not be written to a JPEG destination")
    }

    func testClipboardSchemaDefaultsMissingFieldsAndRejectsNewerVersions() throws {
        let legacy = try JSONDecoder().decode(
            EditClipboardPayload.self,
            from: Data("{\"version\":1}".utf8)
        )
        XCTAssertEqual(legacy, EditClipboardPayload())

        let newer = Data("{\"version\":\(EditClipboardPayload.currentVersion + 1)}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(EditClipboardPayload.self, from: newer))
    }

    func testLegacyCropClipboardDefaultsToFreeform() throws {
        let legacy = Data("{\"version\":1,\"crop\":{\"normalizedRect\":null}}".utf8)
        let clipboard = try JSONDecoder().decode(EditClipboardPayload.self, from: legacy)
        XCTAssertEqual(clipboard.crop.aspectRatio, .freeform)
    }
}

@MainActor
final class CopyPasteTests: TempDirectoryTestCase {
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func photoData(named name: String) throws -> (name: String, data: Data) {
        let url = try Fixtures.writeGradientPNG(width: 32, height: 24, named: name, in: tempDirectory)
        return (name, try Data(contentsOf: url))
    }

    func testSinglePasteIsUndoableAndDoesNotChangeTheSource() async throws {
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: makeInMemoryEditStore()
        )
        viewModel.importPhotosData([
            try photoData(named: "one.png"),
            try photoData(named: "two.png"),
        ])
        try await waitUntil("the first photo") { viewModel.sourceName == "one.png" }

        let sourceEdits = EditDocument(adjustments: [.exposure(ev: 0.8)])
        viewModel.updateDocument { $0 = sourceEdits }
        viewModel.copyAllEdits()

        viewModel.selectCollectionImage(at: 1)
        try await waitUntil("the second photo") { viewModel.sourceName == "two.png" }
        XCTAssertTrue(viewModel.document.isIdentity)
        viewModel.pasteEdits()
        XCTAssertEqual(viewModel.document, sourceEdits)
        XCTAssertEqual(viewModel.undoDepth, 1)

        viewModel.undo()
        XCTAssertTrue(viewModel.document.isIdentity)

        viewModel.selectCollectionImage(at: 0)
        try await waitUntil("the source photo again") { viewModel.sourceName == "one.png" }
        XCTAssertEqual(viewModel.document, sourceEdits, "pasting must not consume or alter the source")
    }

    func testSelectiveCopyMaskLeavesUncheckedDestinationStagesIntact() async throws {
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: makeInMemoryEditStore()
        )
        viewModel.importPhotosData([
            try photoData(named: "source.png"),
            try photoData(named: "destination.png"),
        ])
        try await waitUntil("the source photo") { viewModel.sourceName == "source.png" }

        let sourceEdits = EditDocument(
            adjustments: [.exposure(ev: 0.8), .vibrance(amount: 0.7)],
            lut: LUTSettings(lutID: LUTID(raw: "copied.cube"), intensity: 0.9)
        )
        viewModel.updateDocument { $0 = sourceEdits }
        viewModel.editorDocument.copy(document: sourceEdits, categories: [.light])

        viewModel.selectCollectionImage(at: 1)
        try await waitUntil("the destination photo") { viewModel.sourceName == "destination.png" }
        let destinationLook = LUTSettings(lutID: LUTID(raw: "destination.cube"), intensity: 0.2)
        viewModel.updateDocument {
            $0 = EditDocument(
                adjustments: [.exposure(ev: -0.4), .vibrance(amount: -0.3)],
                lut: destinationLook
            )
        }

        viewModel.pasteEdits()

        XCTAssertEqual(viewModel.document.adjustments, [.exposure(ev: 0.8), .vibrance(amount: -0.3)])
        XCTAssertEqual(viewModel.document.lut, destinationLook)
        XCTAssertTrue(viewModel.statusMessage.contains("Light"))
    }

    func testSelectiveCopyDialogSeedsAndPersistsRememberedCategories() async throws {
        let preferences = makeTestUserDefaults()
        let settings = KromoraSettings(
            preferences: preferences,
            userLookFolderURL: tempDirectory
        )
        settings.lastCopyCategories = [.light, .crop]

        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: makeInMemoryEditStore(),
            preferences: preferences
        )
        viewModel.importPhotosData([try photoData(named: "source.png")])
        try await waitUntil("the source photo") { viewModel.sourceName == "source.png" }

        // The dialog is the VM boundary used by both ⌘C and the Copy Edits… menu item. It must
        // refresh its checklist from the persisted choice each time it opens, rather than from
        // the previous sheet session.
        viewModel.selectiveCopyCategories = [.color]
        viewModel.presentSelectiveCopyDialog()
        XCTAssertTrue(viewModel.isSelectiveCopyDialogPresented)
        XCTAssertEqual(viewModel.selectiveCopyCategories, [.light, .crop])

        viewModel.selectiveCopyCategories = [.color, .lut]
        viewModel.confirmSelectiveCopy()

        XCTAssertFalse(viewModel.isSelectiveCopyDialogPresented)
        XCTAssertEqual(viewModel.editClipboardCategories, [.color, .lut])
        let relaunchedSettings = KromoraSettings(
            preferences: preferences,
            userLookFolderURL: tempDirectory
        )
        XCTAssertEqual(relaunchedSettings.lastCopyCategories, [.color, .lut])
    }

    func testMultiPasteUpdatesOnlySelectedPhotosAndEachDestinationCanUndo() async throws {
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: makeInMemoryEditStore()
        )
        viewModel.importPhotosData([
            try photoData(named: "one.png"),
            try photoData(named: "two.png"),
            try photoData(named: "three.png"),
            try photoData(named: "four.png"),
        ])
        try await waitUntil("the first photo") { viewModel.sourceName == "one.png" }

        let sourceEdits = EditDocument(
            adjustments: [.vibrance(amount: 0.6)]
        )
        viewModel.updateDocument { $0 = sourceEdits }
        viewModel.copyAllEdits()

        // Keep the source out of the destination set. This models command-click selection in the
        // source browser/filmstrip without depending on AppKit event delivery in a unit test.
        viewModel.collection.setSelection(at: 1)
        viewModel.collection.setSelection(at: 2, additive: true)
        XCTAssertEqual(viewModel.collection.selectedIndices, [1, 2])
        viewModel.pasteEdits()

        viewModel.selectCollectionImage(at: 1)
        try await waitUntil("the second photo") { viewModel.sourceName == "two.png" }
        XCTAssertEqual(viewModel.document, sourceEdits)
        XCTAssertEqual(viewModel.undoDepth, 1)
        viewModel.undo()
        XCTAssertTrue(viewModel.document.isIdentity)

        viewModel.selectCollectionImage(at: 2)
        try await waitUntil("the third photo") { viewModel.sourceName == "three.png" }
        XCTAssertEqual(viewModel.document, sourceEdits)
        XCTAssertEqual(viewModel.undoDepth, 1)
        viewModel.undo()
        XCTAssertTrue(viewModel.document.isIdentity)

        viewModel.selectCollectionImage(at: 3)
        try await waitUntil("the unselected photo") { viewModel.sourceName == "four.png" }
        XCTAssertTrue(viewModel.document.isIdentity, "an unselected destination must not change")

        viewModel.selectCollectionImage(at: 0)
        try await waitUntil("the source photo") { viewModel.sourceName == "one.png" }
        XCTAssertEqual(viewModel.document, sourceEdits)
    }

    func testFilmstripShiftSelectionBuildsRangeThatPasteCovers() async throws {
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: makeInMemoryEditStore()
        )
        viewModel.importPhotosData([
            try photoData(named: "filmstrip-one.png"),
            try photoData(named: "filmstrip-two.png"),
            try photoData(named: "filmstrip-three.png"),
            try photoData(named: "filmstrip-four.png"),
        ])
        try await waitUntil("the first filmstrip photo") {
            viewModel.sourceName == "filmstrip-one.png"
        }

        let sourceEdits = EditDocument(adjustments: [.exposure(ev: 0.85)])
        viewModel.updateDocument { $0 = sourceEdits }
        viewModel.copyAllEdits()

        // This is the callback path used by FilmstripView: the first click establishes the
        // anchor and the Shift-click extends the selection in display/source order.
        viewModel.selectCollectionImage(at: 3, modifiers: [.shift])
        try await waitUntil("the Shift-clicked filmstrip photo") {
            viewModel.sourceName == "filmstrip-four.png"
        }
        XCTAssertEqual(viewModel.collection.selectedIndices, [0, 1, 2, 3])

        viewModel.pasteEdits()

        for item in viewModel.collection.items {
            XCTAssertEqual(
                viewModel.editorDocument.session(for: item.id)?.document,
                sourceEdits,
                "the Shift-selected range should receive the paste for \(item.displayName)"
            )
        }
        XCTAssertEqual(viewModel.document, sourceEdits)
    }
}
