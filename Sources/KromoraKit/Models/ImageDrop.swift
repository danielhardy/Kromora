import AppKit
import Foundation
import UniformTypeIdentifiers

/// The material a library drop can carry.
///
/// File promises stay on the main actor because `NSFilePromiseReceiver` is an AppKit object
/// without Sendable semantics. Once a promise is redeemed, only its resulting URLs enter the
/// ordinary library import path.
@MainActor
enum ImageDrop {
    enum Payload {
        case urls([URL])
        case promises([NSFilePromiseReceiver])
        case image(data: Data, name: String)
    }

    struct PromiseReceiveResult: Sendable, Equatable {
        let urls: [URL]
        let failures: [String]
    }

    /// SwiftUI's item providers cannot redeem file promises, so advertise the promise identifiers
    /// explicitly and let the drop delegate inspect the AppKit drag pasteboard.
    static let acceptedTypes: [UTType] = {
        let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.compactMap { UTType($0) }
        return [.fileURL, .image] + promiseTypes
    }()

    private static let imageDataTypes: [NSPasteboard.PasteboardType] = [.tiff, .png]

    static func canAccept(_ pasteboard: NSPasteboard) -> Bool {
        payload(from: pasteboard) != nil
    }

    /// Promises intentionally win over URLs. Photos may publish a derivative `file-url` beside a
    /// promise; opening that URL would import the wrong asset or fail inside the app sandbox.
    static func payload(from pasteboard: NSPasteboard) -> Payload? {
        if let receivers = pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self]
        ) as? [NSFilePromiseReceiver], !receivers.isEmpty {
            return .promises(receivers)
        }

        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: fileOptions
        ) as? [URL], !urls.isEmpty {
            return .urls(urls)
        }

        for type in imageDataTypes {
            if let data = pasteboard.data(forType: type), !data.isEmpty {
                let extensionName = UTType(type.rawValue)?.preferredFilenameExtension ?? "img"
                return .image(data: data, name: "Dropped Image.\(extensionName)")
            }
        }
        return nil
    }

    /// Redeem every promised file into the supplied app-writable directory. The reader callback is
    /// deliberately scheduled on `.main`: AppKit's promise receiver invokes the callback on the
    /// supplied queue, and a private queue violates Swift 6's main-actor isolation here.
    static func receive(
        _ receivers: [NSFilePromiseReceiver],
        into directory: URL
    ) async -> PromiseReceiveResult {
        let expected = receivers.reduce(0) {
            $0 + max($1.fileTypes.count, $1.fileNames.count)
        }
        guard expected > 0 else { return PromiseReceiveResult(urls: [], failures: []) }

        let expectedNames = receivers.flatMap(\.fileNames)
        let stream = AsyncStream<(URL?, String?)> { continuation in
            for receiver in receivers {
                receiver.receivePromisedFiles(
                    atDestination: directory,
                    options: [:],
                    operationQueue: .main
                ) { url, error in
                    continuation.yield((error == nil ? url : nil, error?.localizedDescription))
                }
            }
        }

        var urls: [URL] = []
        var failures: [String] = []
        var received = 0
        for await (url, errorDescription) in stream {
            let fallbackName = "Promised item \(received + 1)"
            let name = expectedNames.indices.contains(received)
                ? expectedNames[received]
                : fallbackName
            if let url {
                urls.append(url)
            } else {
                let reason = errorDescription ?? "The promised file could not be redeemed."
                failures.append("\(name): \(reason)")
            }
            received += 1
            if received == expected { break }
        }
        return PromiseReceiveResult(urls: urls, failures: failures)
    }

    private static var dropsRoot: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Kromora Drops", isDirectory: true)
    }

    static func makeDropDirectory() throws -> URL {
        let directory = dropsRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        return directory
    }

    /// Drop directories are transport only. Once the library has adopted the originals, remove all
    /// old directories so failed or abandoned drags cannot accumulate under the temporary folder.
    static func purgeDropDirectories(except keep: URL? = nil) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: dropsRoot, includingPropertiesForKeys: nil
        ) else { return }
        for entry in entries where entry.standardizedFileURL != keep?.standardizedFileURL {
            try? fileManager.removeItem(at: entry)
        }
    }
}
