import AppKit
import UniformTypeIdentifiers
import XCTest

@testable import KromoraKit

@MainActor
final class ImageDropTests: TempDirectoryTestCase {
    @MainActor
    private final class PromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
        func filePromiseProvider(
            _ filePromiseProvider: NSFilePromiseProvider,
            fileNameForType fileType: String
        ) -> String {
            "Original.arw"
        }

        nonisolated func filePromiseProvider(
            _ filePromiseProvider: NSFilePromiseProvider,
            writePromiseTo url: URL,
            completionHandler: @escaping (Error?) -> Void
        ) {
            do {
                try Data([0x01, 0x02, 0x03]).write(to: url)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        return pasteboard
    }

    func testAcceptedTypesIncludeFilesImagesAndPromiseIdentifiers() {
        XCTAssertTrue(ImageDrop.acceptedTypes.contains(.fileURL))
        XCTAssertTrue(ImageDrop.acceptedTypes.contains(.image))
        for identifier in NSFilePromiseReceiver.readableDraggedTypes {
            guard let type = UTType(identifier) else {
                return XCTFail("Could not create UTI for \(identifier)")
            }
            XCTAssertTrue(ImageDrop.acceptedTypes.contains(type))
        }
    }

    func testFileURLsRemainURLPayloads() throws {
        let first = tempDirectory.appendingPathComponent("first.jpg")
        let second = tempDirectory.appendingPathComponent("second.dng")
        try Data([1]).write(to: first)
        try Data([2]).write(to: second)
        let pasteboard = makePasteboard()
        XCTAssertTrue(pasteboard.writeObjects([first as NSURL, second as NSURL]))

        guard case .urls(let urls)? = ImageDrop.payload(from: pasteboard) else {
            return XCTFail("Expected URL payload")
        }
        XCTAssertEqual(urls.map(\.lastPathComponent), ["first.jpg", "second.dng"])
    }

    func testPromisesWinOverURLAndBitmapPayloads() {
        let delegate = PromiseDelegate()
        let provider = NSFilePromiseProvider(
            fileType: UTType.data.identifier, delegate: delegate
        )
        let pasteboard = makePasteboard()
        XCTAssertTrue(pasteboard.writeObjects([
            provider,
            NSURL(fileURLWithPath: "/tmp/Photos-derivative.jpeg")
        ]))
        pasteboard.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)

        guard case .promises(let receivers)? = ImageDrop.payload(from: pasteboard) else {
            return XCTFail("Expected promise payload to outrank URL and bitmap data")
        }
        XCTAssertEqual(receivers.count, 1)
    }

    func testPromiseReceiveKeepsPromisedFilenameAndReportsSuccess() async throws {
        let delegate = PromiseDelegate()
        let provider = NSFilePromiseProvider(
            fileType: UTType.data.identifier, delegate: delegate
        )
        let pasteboard = makePasteboard()
        XCTAssertTrue(pasteboard.writeObjects([provider]))
        guard case .promises(let receivers)? = ImageDrop.payload(from: pasteboard) else {
            return XCTFail("Expected promise payload")
        }

        let directory = try ImageDrop.makeDropDirectory()
        let result = await ImageDrop.receive(receivers, into: directory)
        XCTAssertEqual(result.failures, [])
        XCTAssertEqual(result.urls.map(\.lastPathComponent), ["Original.arw"])
        ImageDrop.purgeDropDirectories()
    }

    func testBitmapPayloadHasStableFilenameAndData() {
        let pasteboard = makePasteboard()
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        pasteboard.setData(data, forType: .png)

        guard case .image(let droppedData, let name)? = ImageDrop.payload(from: pasteboard) else {
            return XCTFail("Expected bitmap payload")
        }
        XCTAssertEqual(droppedData, data)
        XCTAssertEqual(name, "Dropped Image.png")
    }

    func testBitmapDropUsesTheExistingDataImportPath() throws {
        let source = try Fixtures.writeGradientPNG(
            width: 8, height: 8, named: "source.png", in: tempDirectory
        )
        let data = try Data(contentsOf: source)
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.handleDrop(.image(data: data, name: "Dropped Image.png"))

        XCTAssertEqual(viewModel.collection.items.map(\.displayName), ["Dropped Image"])
        XCTAssertEqual(viewModel.collection.items.first?.imageData, data)
    }

    func testWebURLsAreNotAcceptedAsFileDrops() {
        let pasteboard = makePasteboard()
        XCTAssertTrue(pasteboard.writeObjects([NSURL(string: "https://example.com/photo.jpg")!]))
        XCTAssertNil(ImageDrop.payload(from: pasteboard))
        XCTAssertFalse(ImageDrop.canAccept(pasteboard))
    }

    func testDropDirectoriesArePurgedAfterAdoption() throws {
        let first = try ImageDrop.makeDropDirectory()
        let second = try ImageDrop.makeDropDirectory()
        try Data([1]).write(to: first.appendingPathComponent("Original.arw"))

        ImageDrop.purgeDropDirectories(except: second)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        ImageDrop.purgeDropDirectories()
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
    }

    func testEmptyPromiseReceiveIsSafe() async {
        let result = await ImageDrop.receive([], into: tempDirectory)
        XCTAssertEqual(result, .init(urls: [], failures: []))
    }
}
