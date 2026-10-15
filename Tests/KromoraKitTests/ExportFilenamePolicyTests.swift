import XCTest
@testable import KromoraKit

final class ExportFilenamePolicyTests: TempDirectoryTestCase {

    private func makeLUT(_ name: String) throws -> CubeLUT {
        let url = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "\(name).cube", in: tempDirectory
        )
        return try CubeLUT(url: url)
    }

    func testPrefixAndSuffixCompose() {
        XCTAssertEqual(
            ExportFilenamePolicy(appendsLook: false, prefix: "Wedding_").baseName(source: "DSC1", look: nil),
            "Wedding_DSC1"
        )
        XCTAssertEqual(
            ExportFilenamePolicy(appendsLook: false, suffix: "_web").baseName(source: "DSC1", look: nil),
            "DSC1_web"
        )
        let both = ExportFilenamePolicy(appendsLook: false, prefix: "Wedding_", suffix: "_web")
        XCTAssertEqual(both.baseName(source: "DSC1", look: "Warm"), "Wedding_DSC1_web")
    }

    func testLookIsAppendedBeforeSuffix() {
        let policy = ExportFilenamePolicy(appendsLook: true, prefix: "A_", suffix: "_web")
        XCTAssertEqual(policy.baseName(source: "DSC1", look: "Warm Look"), "A_DSC1_Warm_Look_web")
        XCTAssertEqual(policy.baseName(source: "DSC1", look: nil), "A_DSC1_web")
    }

    func testSanitizationRemovesIllegalCharactersAndLeadingDots() {
        XCTAssertEqual(ExportFilenamePolicy.sanitized("a/b:c"), "abc")
        XCTAssertEqual(ExportFilenamePolicy.sanitized("..hidden"), "hidden")
        XCTAssertEqual(ExportFilenamePolicy.sanitized("  . "), "")
        XCTAssertEqual(ExportFilenamePolicy.sanitized("///"), "")
        let policy = ExportFilenamePolicy(appendsLook: false, prefix: "../x/", suffix: ":")
        XCTAssertEqual(policy.prefix, "x")
        XCTAssertEqual(policy.suffix, "")
        XCTAssertEqual(policy.baseName(source: "S", look: nil), "xS")
    }

    func testCodableRoundTripAndLegacyDecode() throws {
        let policy = ExportFilenamePolicy(appendsLook: false, prefix: "P_", suffix: "_S")
        let decoded = try JSONDecoder().decode(
            ExportFilenamePolicy.self, from: JSONEncoder().encode(policy)
        )
        XCTAssertEqual(decoded, policy)

        for (raw, expected) in [("sourceName", ExportFilenamePolicy.sourceName),
                                ("sourceNameWithLook", .sourceNameWithLook)] {
            let value = try JSONDecoder().decode(
                ExportFilenamePolicy.self, from: Data("\"\(raw)\"".utf8)
            )
            XCTAssertEqual(value, expected)
        }
        XCTAssertThrowsError(
            try JSONDecoder().decode(ExportFilenamePolicy.self, from: Data("\"nope\"".utf8))
        )
    }

    func testLegacyExportOptionsWithStringPolicyStillDecode() throws {
        let options = ExportOptions(format: .jpeg, filenamePolicy: .sourceName)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(options)) as? [String: Any]
        )
        object["filenamePolicy"] = "sourceName"
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(try JSONDecoder().decode(ExportOptions.self, from: data).filenamePolicy, .sourceName)
    }

    func testPrefixedNamesSkipExistingAndReservedCollisions() throws {
        let policy = ExportFilenamePolicy(appendsLook: false, prefix: "P_")
        let base = policy.baseName(source: "shot", look: nil)
        try Data().write(to: tempDirectory.appendingPathComponent("P_shot.jpg"))
        try Data().write(to: tempDirectory.appendingPathComponent("P_shot 2.jpg"))
        let first = uniqueExportURL(in: tempDirectory, base: base, ext: "jpg")
        XCTAssertEqual(
            first.lastPathComponent,
            "P_shot 3.jpg"
        )
        let second = uniqueExportURL(
            in: tempDirectory, base: base, ext: "jpg",
            reservedPaths: [first.standardizedFileURL.path]
        )
        XCTAssertEqual(second.lastPathComponent, "P_shot 4.jpg")
        XCTAssertNotEqual(first.standardizedFileURL.path, second.standardizedFileURL.path)
    }

    @MainActor
    func testBatchAccessoryShowsSanitizedLiveExampleAndCarriesPolicy() {
        let accessory = ExportFormatAccessoryView(
            selectedFormat: .jpeg,
            batchNaming: (.sourceNameWithLook, "DSC01305", "Warm Look")
        )
        XCTAssertEqual(accessory.namingExample, "DSC01305_Warm_Look.jpg")
        accessory.setNaming(prefix: "Wed/ding_", suffix: "_web", appendsLook: false)
        XCTAssertEqual(accessory.namingExample, "Wedding_DSC01305_web.jpg")
        let options = accessory.exportOptions(destination: .folder(tempDirectory))
        XCTAssertEqual(options.filenamePolicy.prefix, "Wedding_")
        XCTAssertEqual(options.filenamePolicy.suffix, "_web")
        XCTAssertFalse(options.filenamePolicy.appendsLook)
    }

    @MainActor
    func testBatchAccessoryInitialExampleUsesSelectedFormatExtension() {
        let accessory = ExportFormatAccessoryView(
            selectedFormat: .tiff,
            batchNaming: (.sourceName, "DSC01305", nil)
        )
        XCTAssertEqual(accessory.namingExample, "DSC01305.\(ExportFormat.tiff.fileExtension)")
    }

    @MainActor
    func testBatchPanelExampleUsesFirstItemsLookInsteadOfFallbackLook() async throws {
        let firstLook = try makeLUT("First Look")
        let fallbackLook = try makeLUT("Fallback Look")
        let item = ExportCoordinator.BatchItem(
            url: nil, data: Data(), name: "DSC01305", document: EditDocument(), lut: firstLook
        )
        let sheets = FakeSheets()
        let coordinator = ExportCoordinator(photosDelivery: nil, sheets: sheets)

        coordinator.batchExportDialog(items: [item], document: EditDocument(), lut: fallbackLook)

        for _ in 0..<100 where sheets.openCalls == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(sheets.openCalls, 1)
        let accessory = try XCTUnwrap(
            sheets.lastOpenPanel?.accessoryView as? ExportFormatAccessoryView
        )
        let lookComponent = firstLook.name.replacingOccurrences(of: " ", with: "_")
        XCTAssertEqual(accessory.namingExample, "DSC01305_\(lookComponent).jpg")
    }

    @MainActor
    func testSingleExportAccessoryHasNoNamingControls() {
        let accessory = ExportFormatAccessoryView(selectedFormat: .jpeg)
        XCTAssertNil(accessory.namingExample)
    }
}
