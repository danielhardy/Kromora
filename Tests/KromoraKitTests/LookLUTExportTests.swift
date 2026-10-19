import XCTest
import CoreImage
@testable import KromoraKit

final class LookLUTExportTests: TempDirectoryTestCase {
    func testSupportMatrixIncludesVerifiedGlobalStagesAndOmitsSourceAndSpatialStages() {
        let document = EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 1),
            light: LightAdjustments(exposure: 0.5),
            color: ColorAdjustments(saturation: 20),
            effects: EffectsAdjustments(texture: 20, vignette: VignetteAdjustments(amount: 15), grain: GrainAdjustments(amount: 10)),
            crop: CropAdjustments(normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)),
            adjustments: [.vibrance(amount: 0.4)]
        )

        let matrix = LUTSupportMatrix.make(for: document)
        XCTAssertEqual(matrix.version, LUTSupportMatrix.currentVersion)
        XCTAssertTrue(matrix.included.map(\.id).contains(contentsOf: ["light", "color", "adjustment-0"]))
        XCTAssertTrue(matrix.omitted.map(\.id).contains(contentsOf: ["raw-develop", "spatial-effects", "vignette", "grain", "crop"]))
        XCTAssertTrue(matrix.omissionMessage?.contains("will be omitted") == true)
    }

    func testSupportMatrixListsTheLookBeforeTheSlidersItIsAdjustedBy() {
        let document = EditDocument(
            light: LightAdjustments(exposure: 0.5),
            adjustments: [.vibrance(amount: 0.4)],
            lut: LUTSettings(lutID: LUTID(raw: "base"), intensity: 1)
        )
        let ids = LUTSupportMatrix.make(for: document).entries.map(\.id)
        let look = ids.firstIndex(of: "look")
        XCTAssertNotNil(look)
        XCTAssertLessThan(look ?? .max, ids.firstIndex(of: "light") ?? 0)
        XCTAssertLessThan(look ?? .max, ids.firstIndex(of: "adjustment-0") ?? 0)
    }

    func testLookPlusSlidersConversionVerifiesWithinTolerance() throws {
        let lut = TestImages.warmLUT(size: 8, name: "base")
        let document = EditDocument(
            light: LightAdjustments(exposure: 0.4, contrast: 15),
            color: ColorAdjustments(saturation: 10),
            lut: LUTSettings(lutID: lut.lutID, intensity: 0.8)
        )
        let conversion = try LookLUTConverter.convert(document: document, lut: lut)
        XCTAssertTrue(conversion.verification.passed)
    }

    func testIdentityConversionProducesValidDocumentedCube() throws {
        let conversion = try LookLUTConverter.convert(document: EditDocument(), lut: nil, size: 2)
        XCTAssertEqual(conversion.cube.count, 8)
        XCTAssertTrue(conversion.verification.passed)
        let text = conversion.cubeText(title: "Identity Look")
        XCTAssertTrue(text.contains("LUT_3D_SIZE 2"))
        XCTAssertTrue(text.contains("Working color space: sRGB"))
        XCTAssertTrue(text.contains("DOMAIN_MIN: 0.0 0.0 0.0"))
        XCTAssertNotNil(try? CubeLUT(url: Fixtures.writeCube(text, named: "identity-look.cube", in: tempDirectory)))
    }

    func testDefaultLatticeUsesExactNormalizedCoordinates() throws {
        let conversion = try LookLUTConverter.convert(document: EditDocument(), lut: nil)
        let firstRedStep = conversion.cube[1].x

        XCTAssertEqual(firstRedStep, Float(1.0 / Float(LookLUTConverter.defaultSize - 1)), accuracy: 0.000001)
    }

    func testGlobalLightConversionRoundTripsThroughCubeWithinTolerance() throws {
        let document = EditDocument(light: LightAdjustments(exposure: 0.75, contrast: 22))
        let conversion = try LookLUTConverter.convert(document: document, lut: nil, size: 9)
        XCTAssertTrue(conversion.verification.passed)
        XCTAssertGreaterThan(conversion.verification.sampleCount, 0)
        XCTAssertFalse(conversion.cube.allSatisfy { $0 == SIMD3<Float>($0.x, $0.y, $0.z) && $0.x == 0 })
    }

    func testDefaultExportResolutionVerifiesARepresentativeColorEdit() throws {
        let document = EditDocument(color: ColorAdjustments(vibrance: 35, saturation: -12))
        let conversion = try LookLUTConverter.convert(document: document, lut: nil)
        XCTAssertEqual(conversion.size, LookLUTConverter.defaultSize)
        XCTAssertTrue(conversion.verification.passed)
    }

    func testDefaultExportKeepsNonlinearLightEditWithinTolerance() throws {
        let document = EditDocument(light: LightAdjustments(exposure: 0.75, contrast: 22, highlights: -18, shadows: 14))
        let conversion = try LookLUTConverter.convert(document: document, lut: nil)

        XCTAssertTrue(conversion.verification.passed)
        XCTAssertLessThanOrEqual(
            conversion.verification.maxAbsoluteChannelError,
            conversion.verification.tolerance
        )
    }

    func testStrongSaturationRetriesAtHighestQualityResolution() throws {
        let document = EditDocument(color: ColorAdjustments(saturation: 30))

        let conversion = try LookLUTConverter.convert(document: document, lut: nil)

        XCTAssertEqual(conversion.size, LookLUTConverter.highestQualitySize)
        XCTAssertTrue(conversion.verification.passed, conversion.qualitySummary)
        XCTAssertTrue(conversion.cubeText(title: "Strong saturation").contains("LUT size: 65^3"))
    }

    func testPersistentApproximationIsReturnedWithMeasuredQuality() throws {
        let document = EditDocument(color: ColorAdjustments(saturation: 100))

        let conversion = try LookLUTConverter.convert(document: document, lut: nil)

        XCTAssertEqual(conversion.size, LookLUTConverter.highestQualitySize)
        XCTAssertTrue(conversion.isApproximate)
        XCTAssertGreaterThan(conversion.verification.maxAbsoluteChannelError, conversion.verification.tolerance)
        XCTAssertTrue(conversion.cubeText(title: "Approximate saturation").contains("explicit confirmation required"))
    }

    @MainActor
    func testSaveRejectsCollisionAndDoesNotOverwriteExistingFile() throws {
        let coordinator = LookSaveCoordinator()
        let conversion = try LookLUTConverter.convert(document: EditDocument(), lut: nil, size: 2)
        coordinator.setConversion(conversion, name: "New Look")
        let destination = tempDirectory.appendingPathComponent("Existing.cube")
        try "sentinel".write(to: destination, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try coordinator.performSave(name: "New Look", to: destination)) { error in
            XCTAssertEqual((error as? LookSaveCoordinator.LookSaveError)?.errorDescription,
                           "A Look with that filename already exists. Choose a different name or destination.")
        }
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "sentinel")
    }

    @MainActor
    func testAcceptedSaveSheetWritesTheLook() async throws {
        let sheets = FakeSheets()
        let coordinator = LookSaveCoordinator(sheets: sheets)
        coordinator.setConversion(
            try LookLUTConverter.convert(document: EditDocument(), lut: nil, size: 2), name: "Sheet Look"
        )
        let destination = tempDirectory.appendingPathComponent("Sheet Look.cube")
        sheets.saveURL = destination
        var saved: URL?
        coordinator.onSaved = { saved = $0 }

        await coordinator.saveDialog().value

        XCTAssertEqual(sheets.lastSavePanel?.title, "Save Look")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(saved, destination)
    }

    @MainActor
    func testCancelledSaveSheetWritesNothing() async throws {
        let sheets = FakeSheets()
        let coordinator = LookSaveCoordinator(sheets: sheets)
        coordinator.setConversion(
            try LookLUTConverter.convert(document: EditDocument(), lut: nil, size: 2), name: "Sheet Look"
        )
        coordinator.onSaved = { _ in XCTFail("cancel must not report a save") }

        await coordinator.saveDialog().value

        XCTAssertEqual(sheets.saveCalls, 1)
        XCTAssertNil(coordinator.saveError)
    }

    @MainActor
    func testSavingRegistersWithoutChangingTheActiveDocument() async throws {
        let source = try Fixtures.writeGradientPNG(width: 8, height: 8, named: "save-look.png", in: tempDirectory)
        let store = makeInMemoryEditStore()
        let viewModel = makeAppViewModel(engine: FakeRenderEngine(), editStore: store)
        viewModel.openImage(url: source)
        let deadline = Date().addingTimeInterval(5)
        while viewModel.sourceName != source.lastPathComponent {
            if Date() > deadline { return XCTFail("timed out opening image") }
            try await Task.sleep(for: .milliseconds(10))
        }
        viewModel.updateDocument { $0.light.exposure = 0.5 }
        let before = viewModel.document
        let conversion = try LookLUTConverter.convert(document: before, lut: nil, size: 9)
        viewModel.lookSave.setConversion(conversion, name: "Saved Look")
        let destination = tempDirectory.appendingPathComponent("Saved Look.cube")
        try viewModel.lookSave.performSave(name: "Saved Look", to: destination)
        XCTAssertEqual(viewModel.document, before)
        XCTAssertEqual(viewModel.undoDepth, 1)
        viewModel.lookSave.onSaved?(destination)
        while viewModel.library.isImporting { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(viewModel.library.allLUTs.contains { $0.url == destination })
    }

    @MainActor
    func testApproximateConversionRequiresExplicitConfirmationBeforeWriting() throws {
        let conversion = try LookLUTConverter.convert(
            document: EditDocument(color: ColorAdjustments(saturation: 100)), lut: nil
        )
        let coordinator = LookSaveCoordinator()
        coordinator.setConversion(conversion, name: "Approximate Look")
        let destination = tempDirectory.appendingPathComponent("Approximate Look.cube")

        XCTAssertThrowsError(try coordinator.performSave(name: "Approximate Look", to: destination)) { error in
            XCTAssertEqual((error as? LookSaveCoordinator.LookSaveError)?.errorDescription,
                           "This Look is approximate. Confirm the measured conversion quality before saving.")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        coordinator.allowsApproximateSave = true
        try coordinator.performSave(name: "Approximate Look", to: destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(try String(contentsOf: destination, encoding: .utf8).contains("Verification result: approximate"))
    }
}

private extension Array where Element: Equatable {
    func contains(contentsOf values: [Element]) -> Bool { values.allSatisfy(contains) }
}
