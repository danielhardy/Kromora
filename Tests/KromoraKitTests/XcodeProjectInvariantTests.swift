import XCTest
@testable import KromoraKit

/// Keeps the standalone Xcode project as a packaging layer over the Swift package.
final class XcodeProjectInvariantTests: XCTestCase {

    private static let invariant = "All application functionality belongs in KromoraKit"

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testXcodeSourcesBuildPhaseContainsOnlyTheAppLauncher() throws {
        guard let project = readText(at: xcodeProjectURL) else { return }
        guard
            let nativeTargets = section("PBXNativeTarget", in: project),
            let targetID = try captures(
                #"(?m)^\s*([A-F0-9]+)\s+/\* Kromora \*/ = \{"#,
                in: nativeTargets
            ).first,
            let target = try objectBody(targetID, in: nativeTargets, isa: "PBXNativeTarget"),
            let buildPhases = try firstCapture(#"(?s)buildPhases\s*=\s*\((.*?)\);"#, in: target),
            let sourcePhaseID = try captures(
                #"([A-F0-9]+)\s+/\*\s*Sources\s*\*/"#,
                in: buildPhases
            ).first,
            let sourceBuildPhases = section("PBXSourcesBuildPhase", in: project),
            let sourcePhase = try objectBody(sourcePhaseID, in: sourceBuildPhases, isa: "PBXSourcesBuildPhase"),
            let files = try firstCapture(#"(?s)files\s*=\s*\((.*?)\);"#, in: sourcePhase),
            let buildFiles = section("PBXBuildFile", in: project),
            let fileReferences = section("PBXFileReference", in: project),
            let groups = section("PBXGroup", in: project)
        else {
            XCTFail("\(Self.invariant): could not find the Kromora target's Sources build phase.")
            return
        }

        let buildFileIDs = try captures(#"\b[A-F0-9]{24}\b"#, in: files, captureGroup: 0)
        var swiftSourcePaths: [String] = []

        for buildFileID in buildFileIDs {
            guard
                let buildFile = try objectBody(buildFileID, in: buildFiles, isa: "PBXBuildFile"),
                let fileReferenceID = try firstCapture(#"\bfileRef\s*=\s*([A-F0-9]+)\b"#, in: buildFile),
                let fileReference = try objectBody(fileReferenceID, in: fileReferences, isa: "PBXFileReference")
            else {
                XCTFail("\(Self.invariant): every Sources build entry must resolve to a file reference.")
                continue
            }

            guard let path = try firstCapture(#"\bpath\s*=\s*"?([^";\n]+)"?;"#, in: fileReference) else {
                XCTFail("\(Self.invariant): every Sources build entry must declare its file path.")
                continue
            }
            guard (path as NSString).pathExtension == "swift" else { continue }

            let parentGroupIDs = try captures(
                #"(?m)^\s*([A-F0-9]+)(?:\s+/\*[^\n]*?\*/)?\s*=\s*\{"#,
                in: groups
            )
            let parentPaths = try parentGroupIDs.compactMap { groupID -> String? in
                guard
                    let group = try objectBody(groupID, in: groups, isa: "PBXGroup"),
                    let children = try firstCapture(#"(?s)children\s*=\s*\((.*?)\);"#, in: group),
                    try captures(#"\b[A-F0-9]+\b"#, in: children, captureGroup: 0).contains(fileReferenceID)
                else { return nil }
                return try firstCapture(#"\bpath\s*=\s*"?([^";\n]+)"?;"#, in: group)
            }

            guard parentPaths.count == 1 else {
                XCTFail("\(Self.invariant): the Xcode launcher must belong to the App group at ../App.")
                continue
            }
            swiftSourcePaths.append("\(parentPaths[0])/\(path)")
        }

        XCTAssertEqual(
            swiftSourcePaths,
            ["../App/KromoraApp.swift"],
            "\(Self.invariant): the Kromora target's Sources build phase may compile only App/KromoraApp.swift."
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
        for relativePath in ["Sources/Kromora/KromoraApp.swift", "App/KromoraApp.swift"] {
            guard let source = readText(at: packageRoot.appendingPathComponent(relativePath)) else { continue }
            let lineCount = source.split(whereSeparator: \.isNewline).count
            XCTAssertLessThanOrEqual(
                lineCount,
                30,
                "\(Self.invariant): \(relativePath) must remain at most 30 lines."
            )
        }
    }

    func testAppAndXcodeContainNoOtherSwiftFiles() throws {
        let appURL = packageRoot.appendingPathComponent("App", isDirectory: true)
        let xcodeURL = packageRoot.appendingPathComponent("Xcode", isDirectory: true)
        // Xcode/build is ignored generated output and may contain DerivedSources/*.swift.
        let generatedBuildURL = xcodeURL.appendingPathComponent("build", isDirectory: true)
        guard
            let appSwiftFiles = swiftFiles(under: appURL),
            let xcodeSwiftFiles = swiftFiles(under: xcodeURL, excluding: generatedBuildURL)
        else {
            return
        }

        XCTAssertEqual(
            appSwiftFiles,
            ["KromoraApp.swift"],
            "\(Self.invariant): App/ may contain no Swift source except KromoraApp.swift."
        )
        XCTAssertEqual(
            xcodeSwiftFiles,
            [],
            "\(Self.invariant): Xcode/ must contain no Swift source files."
        )
    }

    func testXcodeConfigurationExistsAndTargetsMacOS26Arm64() throws {
        let configDirectory = packageRoot.appendingPathComponent("Xcode/Config", isDirectory: true)
        for name in ["Base.xcconfig", "Debug.xcconfig", "Release.xcconfig"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: configDirectory.appendingPathComponent(name).path),
                "\(Self.invariant): Xcode/Config/\(name) must exist."
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
        packageRoot.appendingPathComponent("Xcode/Kromora.xcodeproj/project.pbxproj")
    }

    private func readText(at url: URL) -> String? {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            XCTFail("\(Self.invariant): could not read \(url.path): \(error)")
            return nil
        }
    }

    private func swiftFiles(under directoryURL: URL, excluding excludedURL: URL? = nil) -> [String]? {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            XCTFail("\(Self.invariant): could not scan \(directoryURL.path) for Swift files.")
            return nil
        }

        var swiftFiles: [String] = []
        while let item = enumerator.nextObject() as? URL {
            if let excludedURL, item.standardizedFileURL == excludedURL.standardizedFileURL {
                enumerator.skipDescendants()
                continue
            }
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
        let pattern = "(?s)(?:^|\\n)\\s*\(escapedID)(?:\\s+/\\*[^\\n]*?\\*/)?\\s*=\\s*\\{(.*?)\\};"
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
