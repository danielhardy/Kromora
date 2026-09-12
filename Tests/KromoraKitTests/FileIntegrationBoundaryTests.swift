import XCTest
import UniformTypeIdentifiers

@testable import KromoraKit

@MainActor
final class FileIntegrationBoundaryTests: TempDirectoryTestCase {

    private final class StubFileDialog: FileDialogProviding {
        var imageResult: [URL]?
        var folderResult: URL?
        var imageStartingURL: URL?
        var folderStartingURL: URL?

        func chooseFiles(
            title: String,
            allowedContentTypes: [UTType],
            allowsMultipleSelection: Bool,
            startingAt directoryURL: URL?
        ) -> [URL]? {
            imageStartingURL = directoryURL
            return imageResult
        }

        func chooseFolder(
            title: String,
            prompt: String,
            startingAt directoryURL: URL?,
            canCreateDirectories: Bool
        ) -> URL? {
            folderStartingURL = directoryURL
            return folderResult
        }
    }

    private final class StubWorkspace: WorkspaceRevealing {
        var revealedURLs: [URL] = []

        func reveal(_ urls: [URL]) -> Bool {
            revealedURLs = urls
            return true
        }
    }

    func testDropPolicyClassifiesFileFolderAndInvalidURL() throws {
        let image = try Fixtures.writeGradientPNG(
            width: 12, height: 8, named: "drop.png", in: tempDirectory
        )
        let folder = tempDirectory.appendingPathComponent("Dropped Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let missing = tempDirectory.appendingPathComponent("missing.png")
        let policy = FileDropActionPolicy()

        XCTAssertEqual(policy.action(for: image), .openImage(image))
        XCTAssertEqual(policy.action(for: folder), .openFolder(folder))
        XCTAssertEqual(policy.action(for: missing), .invalid(missing))
    }

    func testCancelledImageDialogLeavesCurrentEditUntouched() async throws {
        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "existing.png", in: tempDirectory
        )
        let dialog = StubFileDialog()
        let viewModel = makeAppViewModel(fileDialog: dialog)
        viewModel.openImages(urls: [image])
        try await waitUntilSourceIsLoaded(viewModel)

        let existingIDs = viewModel.collection.items.map(\.id)
        let existingSource = viewModel.sourceName
        viewModel.openImageDialog()

        XCTAssertEqual(viewModel.collection.items.map(\.id), existingIDs)
        XCTAssertEqual(viewModel.sourceName, existingSource)
        XCTAssertEqual(dialog.imageStartingURL, viewModel.settings.defaultSourceFolderURL)
    }

    func testInvalidDropLeavesCurrentEditUntouched() throws {
        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "existing.png", in: tempDirectory
        )
        let viewModel = makeAppViewModel()
        viewModel.openImages(urls: [image])
        let existingIDs = viewModel.collection.items.map(\.id)
        let missing = tempDirectory.appendingPathComponent("missing.png")

        viewModel.handleDroppedURL(missing)

        XCTAssertEqual(viewModel.collection.items.map(\.id), existingIDs)
    }

    func testWorkspaceRevealIsInjectedForUserLooksFolder() {
        let workspace = StubWorkspace()
        let settings = KromoraSettings(
            preferences: UserDefaults(suiteName: "FileIntegrationBoundaryTests-\(UUID())")!,
            userLookFolderURL: tempDirectory.appendingPathComponent("User Looks", isDirectory: true)
        )

        XCTAssertTrue(settings.revealUserLookFolder(using: workspace))
        XCTAssertEqual(workspace.revealedURLs, [settings.userLookFolderURL])
    }

    private func waitUntilSourceIsLoaded(_ viewModel: AppViewModel) async throws {
        let deadline = Date().addingTimeInterval(5)
        while viewModel.sourceImage == nil {
            if Date() > deadline {
                return XCTFail("timed out waiting for the source image")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
