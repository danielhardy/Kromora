import Foundation
import UniformTypeIdentifiers

/// The Look browser's folder and file pickers. Choosing hands the result to the `LUTLibrary`,
/// which owns parsing, security-scoped access, and persistence.
@MainActor
final class LookLibrarySheets {
    private let sheets: any SheetPresenting
    private let library: LUTLibrary

    init(sheets: any SheetPresenting, library: LUTLibrary) {
        self.sheets = sheets
        self.library = library
    }

    @discardableResult
    func chooseFolder() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            let urls = await self.sheets.chooseOpenURLs { panel in
                panel.title = "Select Look Folder"
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
            }
            guard let url = urls?.first else { return }
            self.library.setFolder(url, access: .systemGranted(for: url))
        }
    }

    /// Import one or more external `.cube`/text-based `.look` files from ordinary Finder locations.
    @discardableResult
    func chooseFiles() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            let urls = await self.sheets.chooseOpenURLs { panel in
                panel.title = "Import Look"
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = true
                panel.allowedContentTypes = [
                    UTType(filenameExtension: "cube"),
                    UTType(filenameExtension: "look"),
                ].compactMap { $0 }
            }
            for url in urls ?? [] {
                self.library.importLUT(from: url, access: .systemGranted(for: url))
            }
        }
    }
}
