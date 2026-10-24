import XCTest
@testable import KromoraKit

/// Keeps the standalone Xcode project as a packaging layer over the Swift package.
final class XcodeProjectInvariantTests: XCTestCase {

    private static let invariant = "All application functionality belongs in KromoraKit"

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testSandboxEntitlementsAllowPhotoKit() throws {
        guard let text = readText(at: packageRoot.appendingPathComponent("Kromora/Kromora.entitlements")) else { return }
        XCTAssertTrue(text.contains("com.apple.security.personal-information.photos-library"),
                      "PhotoKit is denied in the sandbox without the Photos library entitlement.")
    }

    // MARK: Strict entitlement checker contract

    private static let intendedEntitlements: [String: Bool] = [
        "com.apple.security.app-sandbox": true,
        "com.apple.security.files.user-selected.read-write": true,
        "com.apple.security.files.removable-media.read-only": true,
        "com.apple.security.files.bookmarks.app-scope": true,
        "com.apple.security.assets.pictures.read-write": true,
        "com.apple.security.personal-information.photos-library": true,
    ]

    func testEntitlementCheckerAcceptsSourceEntitlementsAndIntendedSet() throws {
        let source = packageRoot.appendingPathComponent("Kromora/Kromora.entitlements")
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        XCTAssertEqual(try runEntitlementChecker(on: source).status, 0)
        XCTAssertEqual(try runEntitlementChecker(on: writeEntitlements(Self.intendedEntitlements)).status, 0)
    }

    func testEntitlementCheckerRejectsUnexpectedMissingAndFalseEntitlements() throws {
        var extra = Self.intendedEntitlements
        extra["com.apple.security.network.client"] = true
        let unexpected = try runEntitlementChecker(on: writeEntitlements(extra))
        XCTAssertNotEqual(unexpected.status, 0)
        XCTAssertTrue(unexpected.output.contains("network.client"))

        var missing = Self.intendedEntitlements
        missing["com.apple.security.personal-information.photos-library"] = nil
        XCTAssertNotEqual(try runEntitlementChecker(on: writeEntitlements(missing)).status, 0)

        var disabled = Self.intendedEntitlements
        disabled["com.apple.security.personal-information.photos-library"] = false
        XCTAssertNotEqual(try runEntitlementChecker(on: writeEntitlements(disabled)).status, 0)
    }

    private func writeEntitlements(_ entitlements: [String: Bool]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kromora-entitlements-\(UUID().uuidString).plist")
        try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func runEntitlementChecker(on plist: URL) throws -> (status: Int32, output: String) {
        let script = packageRoot.appendingPathComponent("scripts/check-sandbox-entitlements.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-I", script.path, plist.path, "test"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func testSynchronizedKromoraFolderIsTheTargetsOnlySourceOfFiles() throws {
        guard let project = readText(at: xcodeProjectURL) else { return }
        guard
            let nativeTargets = section("PBXNativeTarget", in: project),
            let targetID = try captures(
                #"(?m)^\s*([A-F0-9]+)\s+/\* Kromora \*/ = \{"#,
                in: nativeTargets
            ).first,
            let target = try objectBody(targetID, in: nativeTargets, isa: "PBXNativeTarget"),
            let synchronizedGroups = try firstCapture(
                #"(?s)fileSystemSynchronizedGroups\s*=\s*\((.*?)\);"#,
                in: target
            ),
            let rootGroups = section("PBXFileSystemSynchronizedRootGroup", in: project)
        else {
            XCTFail("\(Self.invariant): the Kromora target must use a file-system synchronized group.")
            return
        }

        let groupIDs = try captures(#"\b[A-F0-9]{24}\b"#, in: synchronizedGroups, captureGroup: 0)
        XCTAssertEqual(groupIDs.count, 1, "\(Self.invariant): the target may own exactly one synchronized group.")
        for groupID in groupIDs {
            guard let group = try objectBody(groupID, in: rootGroups, isa: "PBXFileSystemSynchronizedRootGroup") else {
                XCTFail("\(Self.invariant): the synchronized group must resolve.")
                continue
            }
            XCTAssertEqual(
                try firstCapture(#"\bpath\s*=\s*"?([^";\n]+)"?;"#, in: group),
                "Kromora",
                "\(Self.invariant): the synchronized group must be the Kromora/ folder."
            )
        }

        // Hand-added file entries would bypass the folder-content invariant, so only the
        // KromoraKit framework link may appear as a build file, and no phase may list sources.
        let buildFileLines = (section("PBXBuildFile", in: project) ?? "")
            .split(whereSeparator: \.isNewline)
            .filter { $0.contains("isa = PBXBuildFile") }
        XCTAssertEqual(
            buildFileLines.count,
            1,
            "\(Self.invariant): project.pbxproj may list only the KromoraKit package product as a build file."
        )
        XCTAssertTrue(buildFileLines.allSatisfy { $0.contains("productRef") })
        for phase in ["PBXSourcesBuildPhase", "PBXResourcesBuildPhase"] {
            guard let phaseSection = section(phase, in: project) else { continue }
            let files = try firstCapture(#"(?s)files\s*=\s*\((.*?)\);"#, in: phaseSection) ?? ""
            XCTAssertTrue(
                files.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(Self.invariant): \(phase) must stay empty; the synchronized folder supplies files."
            )
        }
        let fileReferences = section("PBXFileReference", in: project) ?? ""
        XCTAssertFalse(
            fileReferences.contains(".swift"),
            "\(Self.invariant): project.pbxproj may not reference Swift files directly."
        )
    }

    func testXcodeDependsOnlyOnTheKromoraKitPackageProduct() throws {
        guard let project = readText(at: xcodeProjectURL) else { return }
        guard
            let nativeTargets = section("PBXNativeTarget", in: project),
            let targetID = try captures(
                #"(?m)^\s*([A-F0-9]+)\s+/\* Kromora \*/ = \{"#,
                in: nativeTargets
            ).first,
            let target = try objectBody(targetID, in: nativeTargets, isa: "PBXNativeTarget"),
            let dependencies = try firstCapture(#"(?s)packageProductDependencies\s*=\s*\((.*?)\);"#, in: target),
            let productSection = section("XCSwiftPackageProductDependency", in: project)
        else {
            XCTFail("\(Self.invariant): could not find the Kromora target's Swift package dependencies.")
            return
        }

        let dependencyIDs = try captures(#"\b[A-F0-9]{24}\b"#, in: dependencies, captureGroup: 0)
        var productNames: [String] = []
        for dependencyID in dependencyIDs {
            guard
                let dependency = try objectBody(
                    dependencyID,
                    in: productSection,
                    isa: "XCSwiftPackageProductDependency"
                ),
                let productName = try firstCapture(#"\bproductName\s*=\s*([^;\s]+)\s*;"#, in: dependency)
            else {
                XCTFail("\(Self.invariant): every package dependency must resolve to a product name.")
                continue
            }
            productNames.append(productName)
        }

        XCTAssertEqual(
            productNames,
            ["KromoraKit"],
            "\(Self.invariant): KromoraKit must be the Xcode target's only Swift package product."
        )
    }

    func testBothAppLaunchersRemainThin() throws {
        for relativePath in ["Sources/Kromora/KromoraApp.swift", "Kromora/KromoraApp.swift"] {
            guard let source = readText(at: packageRoot.appendingPathComponent(relativePath)) else { continue }
            let lineCount = source.split(whereSeparator: \.isNewline).count
            XCTAssertLessThanOrEqual(
                lineCount,
                30,
                "\(Self.invariant): \(relativePath) must remain at most 30 lines."
            )
        }
    }

    func testAppFolderContainsNoOtherSwiftFiles() throws {
        let appURL = packageRoot.appendingPathComponent("Kromora", isDirectory: true)
        guard let appSwiftFiles = swiftFiles(under: appURL) else { return }

        XCTAssertEqual(
            appSwiftFiles,
            ["KromoraApp.swift"],
            "\(Self.invariant): Kromora/ may contain no Swift source except KromoraApp.swift."
        )
    }

    func testXcodeConfigurationExistsAndTargetsMacOS26Arm64() throws {
        let configDirectory = packageRoot.appendingPathComponent("Config", isDirectory: true)
        for name in ["Base.xcconfig", "Debug.xcconfig", "Release.xcconfig"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: configDirectory.appendingPathComponent(name).path),
                "\(Self.invariant): Config/\(name) must exist."
            )
        }

        guard let baseConfig = readText(at: configDirectory.appendingPathComponent("Base.xcconfig")) else { return }
        let assignments = baseConfig.split(whereSeparator: \.isNewline).compactMap { line -> (String, String)? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), let equals = trimmed.firstIndex(of: "=") else { return nil }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: equals)...]
                .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            return (key, value)
        }

        XCTAssertEqual(
            assignments.filter { $0.0 == "MACOSX_DEPLOYMENT_TARGET" }.map(\.1),
            ["26.0"],
            "\(Self.invariant): Base.xcconfig must set MACOSX_DEPLOYMENT_TARGET = 26.0."
        )
        XCTAssertEqual(
            assignments.filter { $0.0 == "ARCHS" }.map(\.1),
            ["arm64"],
            "\(Self.invariant): Base.xcconfig must set ARCHS = arm64."
        )
    }

    private var xcodeProjectURL: URL {
        packageRoot.appendingPathComponent("Kromora.xcodeproj/project.pbxproj")
    }

    private func readText(at url: URL) -> String? {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            XCTFail("\(Self.invariant): could not read \(url.path): \(error)")
            return nil
        }
    }

    private func swiftFiles(under directoryURL: URL) -> [String]? {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            XCTFail("\(Self.invariant): could not scan \(directoryURL.path) for Swift files.")
            return nil
        }

        var swiftFiles: [String] = []
        while let item = enumerator.nextObject() as? URL {
            guard item.pathExtension == "swift" else { continue }
            swiftFiles.append(String(item.path.dropFirst(directoryURL.path.count + 1)))
        }
        return swiftFiles.sorted()
    }

    private func section(_ name: String, in text: String) -> String? {
        let opening = "/* Begin \(name) section */"
        let closing = "/* End \(name) section */"
        guard
            let start = text.range(of: opening),
            let end = text.range(of: closing, range: start.upperBound..<text.endIndex)
        else {
            XCTFail("\(Self.invariant): project.pbxproj is missing its \(name) section.")
            return nil
        }
        return String(text[start.upperBound..<end.lowerBound])
    }

    private func objectBody(_ id: String, in section: String, isa: String) throws -> String? {
        let escapedID = NSRegularExpression.escapedPattern(for: id)
        // Xcode may emit nested dictionaries inline (for example, `explicitFileTypes = {};`).
        let pattern = "(?s)(?:^|\\n)\\s*\(escapedID)(?:\\s+/\\*[^\\n]*?\\*/)?\\s*=\\s*\\{((?:[^{}]|\\{[^{}]*\\})*)\\};"
        guard
            let body = try firstCapture(pattern, in: section),
            body.contains("isa = \(isa);")
        else { return nil }
        return body
    }

    private func firstCapture(_ pattern: String, in text: String) throws -> String? {
        try captures(pattern, in: text).first
    }

    private func captures(
        _ pattern: String,
        in text: String,
        captureGroup: Int = 1
    ) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard captureGroup < match.numberOfRanges,
                  let range = Range(match.range(at: captureGroup), in: text) else { return nil }
            return String(text[range])
        }
    }
}
