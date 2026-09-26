import XCTest
@testable import KromoraKit

final class OnboardingTests: XCTestCase {
    func testBundledSampleLibraryHasTwoReadablePhotosAndLicenseManifest() throws {
        let urls = StarterSampleLibrary.urls
        XCTAssertEqual(urls.count, 2)
        for url in urls {
            XCTAssertTrue(FileManager.default.isReadableFile(atPath: url.path))
            XCTAssertGreaterThan(try Data(contentsOf: url).count, 10_000)
        }
        let manifestURL = KromoraKitResourceBundle.bundle.url(
            forResource: "manifest", withExtension: "json", subdirectory: "Resources/SamplePhotos")
        XCTAssertNotNil(manifestURL)
        let manifest = try XCTUnwrap(manifestURL)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        XCTAssertEqual(json["license"] as? String, "CC0 1.0 Universal Public Domain Dedication")
        XCTAssertEqual((json["photos"] as? [[String: Any]])?.count, 2)
    }

    @MainActor
    func testGuidedEditStepsMakeBoundedSingleDocumentAdjustments() {
        XCTAssertEqual(GuidedEditStep.all.map(\.id), ["exposure", "shadows", "contrast"])
        var document = EditDocument()
        for step in GuidedEditStep.all { step.apply(&document) }
        XCTAssertEqual(document.light.exposure, 0.35, accuracy: 0.0001)
        XCTAssertEqual(document.light.shadows, 22, accuracy: 0.0001)
        XCTAssertEqual(document.light.contrast, 0.12, accuracy: 0.0001)
    }

    func testLightControlsHaveContextualExplanations() {
        for control in LightControl.allCases {
            XCTAssertFalse(control.explanation.isEmpty, "Missing help for \(control.title)")
        }
    }
}
