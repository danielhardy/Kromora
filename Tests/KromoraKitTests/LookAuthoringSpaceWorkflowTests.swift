import XCTest
import CoreImage
import simd
@testable import KromoraKit

/// Save as Look and Derive sample, fit, and stamp one explicit authoring space (KRMA-1117).
/// The default is `WorkingSpace.current` (Display P3 since KRMA-1121).
@MainActor
final class LookAuthoringSpaceWorkflowTests: TempDirectoryTestCase {

    // MARK: - Save as Look

    func testSaveAsLookDefaultsToTheWorkingSpaceAndStampsIt() throws {
        let conversion = try LookLUTConverter.convert(document: EditDocument(), lut: nil, size: 3)
        XCTAssertEqual(conversion.workingSpace, .displayP3)
        XCTAssertTrue(conversion.cubeText(title: "t").contains(CubeLUT.authoringSpaceHeader(.displayP3)))
    }

    func testSaveAsLookCanSampleAndStampP3() throws {
        let lut = TestImages.warmLUT(size: 8, name: "base")
        let document = EditDocument(
            light: LightAdjustments(exposure: 0.3, contrast: 10),
            lut: LUTSettings(lutID: lut.lutID, intensity: 1)
        )
        let srgb = try LookLUTConverter.convert(document: document, lut: lut, space: .sRGB)
        let p3 = try LookLUTConverter.convert(document: document, lut: lut, space: .displayP3)

        XCTAssertEqual(p3.workingSpace, .displayP3)
        XCTAssertTrue(p3.verification.passed, p3.qualitySummary)
        XCTAssertNotEqual(srgb.cube, p3.cube, "P3 is sampled in P3, not relabelled sRGB values")

        // Save → embed (verbatim bytes) → load round trip.
        let url = tempDirectory.appendingPathComponent("p3.cube")
        try CubeLUT.write(text: p3.cubeText(title: "p3"), to: url)
        let bytes = try Data(contentsOf: url)
        let loaded = try CubeLUT(url: url)
        XCTAssertEqual(loaded.authoringSpace, .displayP3)
        XCTAssertEqual(loaded.contentHash, PortablePackageLookReference(data: bytes).contentHash)
    }

    func testLookSaveCoordinatorSamplesInItsConfiguredSpace() async throws {
        let coordinator = LookSaveCoordinator(authoringSpace: .displayP3)
        coordinator.present(document: EditDocument(light: LightAdjustments(exposure: 0.2)), lut: nil)
        for _ in 0..<200 where coordinator.conversion == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        let conversion = try XCTUnwrap(coordinator.conversion)
        XCTAssertEqual(conversion.workingSpace, .displayP3)
        let url = tempDirectory.appendingPathComponent("saved.cube")
        try coordinator.performSave(name: "saved", to: url)
        XCTAssertEqual(try CubeLUT(url: url).authoringSpace, .displayP3)
        await coordinator.shutdown()
    }

    // MARK: - Derive

    func testDeriveDefaultsToTheWorkingSpaceAndCarriesTheFitSpaceToTheStamp() async throws {
        XCTAssertEqual(RecipeExtractor.Options().authoringSpace, .displayP3)
        for space in WorkingSpace.allCases {
            let cube = [SIMD3<Float>](repeating: SIMD3(0.25, 0.5, 0.75), count: 8)
            let coordinator = DeriveCoordinator(
                extractor: { _, _, _, _ in
                    RecipeExtractor.Result(
                        cube: cube, size: 2,
                        report: RecipeReport(
                            toneCurve: [], saturationRatio: 1, sharpeningRatio: 1, sampleCount: 1,
                            cubeCoveragePercent: 0, alignmentShift: (dx: 0, dy: 0), cameraInfo: nil
                        ),
                        authoringSpace: space
                    )
                },
                scratchRoot: tempDirectory.appendingPathComponent("scratch-\(space.rawValue)")
            )
            let jpg = try Fixtures.writeJPEG(
                width: 8, height: 8, orientation: 1, named: "\(space.rawValue).jpg", in: tempDirectory)
            coordinator.derive(rawURL: tempDirectory.appendingPathComponent("a.dng"), jpgURL: jpg)
            for _ in 0..<200 where coordinator.derivedLUT == nil {
                try await Task.sleep(for: .milliseconds(25))
            }
            let derived = try XCTUnwrap(coordinator.derivedLUT)
            XCTAssertEqual(derived.authoringSpace, space)

            let saved = tempDirectory.appendingPathComponent("derived-\(space.rawValue).cube")
            try coordinator.performSave(to: saved)
            XCTAssertEqual(try CubeLUT(url: saved).authoringSpace, space)
            await coordinator.shutdown()
        }
    }
}
