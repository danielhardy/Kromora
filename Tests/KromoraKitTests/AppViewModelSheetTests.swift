import XCTest

@testable import KromoraKit

@MainActor
final class AppViewModelSheetTests: TempDirectoryTestCase {
    func testCancelledLookFolderSheetLeavesTheFolderUnset() async {
        let sheets = FakeSheets()
        let viewModel = makeAppViewModel(sheets: sheets)
        let before = viewModel.library.folderURL

        await viewModel.chooseLookFolder().value

        XCTAssertEqual(sheets.openCalls, 1)
        XCTAssertEqual(sheets.lastOpenPanel?.title, "Select Look Folder")
        XCTAssertEqual(viewModel.library.folderURL, before)
    }

    func testAcceptedLookFolderSheetSetsTheFolder() async throws {
        let sheets = FakeSheets()
        let folder = tempDirectory.appendingPathComponent("Looks", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        sheets.openURLs = [folder]
        let viewModel = makeAppViewModel(sheets: sheets)

        await viewModel.chooseLookFolder().value

        XCTAssertEqual(viewModel.library.folderURL?.standardizedFileURL, folder.standardizedFileURL)
    }

    func testCancelledLookFileSheetImportsNothing() async {
        let sheets = FakeSheets()
        let viewModel = makeAppViewModel(sheets: sheets)

        await viewModel.chooseLookFile().value

        XCTAssertEqual(sheets.openCalls, 1)
        XCTAssertTrue(sheets.lastOpenPanel?.allowsMultipleSelection == true)
        XCTAssertFalse(viewModel.library.isImporting)
    }
}
