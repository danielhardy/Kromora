import Foundation

/// What the inspector needs to know about the active photo's copy relationship.
enum VirtualCopyPresentation: Equatable, Sendable {
    /// No source, or the relationship has not been read yet. Presents nothing and disables the action.
    case unknown
    /// The package record exists; `copyOf` is the parent for a virtual copy and nil for an original.
    case available(copyOf: PortablePhotoAssetID?)
}

/// Owns the presentation snapshot behind `AppViewModel.virtualCopySourceDescription` and
/// `canCreateVirtualCopy`. The package record is read once per active-asset change, off the main
/// actor, so view getters stay pure in-memory reads. The snapshot is presentation only: the
/// create command still validates against package truth.
@MainActor
final class VirtualCopyMetadataCoordinator {
    typealias Reader = @Sendable (PortablePhotoAssetID) async -> VirtualCopyPresentation

    private(set) var presentation: VirtualCopyPresentation = .unknown
    private let reader: Reader
    private let willChange: @MainActor () -> Void
    private var assetID: PortablePhotoAssetID?
    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?
    private var isShutDown = false

    init(reader: @escaping Reader, willChange: @escaping @MainActor () -> Void) {
        self.reader = reader
        self.willChange = willChange
    }

    /// Reads the record with a detached package read. Missing or invalid records are unavailable.
    static func packageReader(_ package: PortableLibraryPackage) -> Reader {
        { assetID in
            await Task.detached(priority: .utility) {
                guard let record = try? package.readAssetRecord(for: assetID) else {
                    return VirtualCopyPresentation.unknown
                }
                return .available(copyOf: record.copyOfAssetID)
            }.value
        }
    }

    var sourceDescription: String? {
        guard case .available(let parent?) = presentation else { return nil }
        return "Virtual copy of \(parent.raw.prefix(8))"
    }

    var canCreate: Bool {
        if case .available = presentation { return true }
        return false
    }

    /// Call when the active package asset changes. Repeated calls for the same asset do not reread.
    func activeAssetChanged(to newID: PortablePhotoAssetID?) {
        guard !isShutDown, newID != assetID else { return }
        assetID = newID
        generation &+= 1
        task?.cancel()
        task = nil
        setPresentation(.unknown)
        guard let newID else { return }
        let expected = generation
        let reader = self.reader
        task = Task { [weak self] in
            let result = await reader(newID)
            guard let self, !Task.isCancelled, self.generation == expected, !self.isShutDown
            else { return }
            self.setPresentation(result)
        }
    }

    var pendingReadForTest: Task<Void, Never>? { task }

    /// Rejects late publication and waits for an in-flight read.
    func shutdown() async {
        isShutDown = true
        generation &+= 1
        assetID = nil
        let pending = task
        task = nil
        pending?.cancel()
        setPresentation(.unknown)
        await pending?.value
    }

    private func setPresentation(_ value: VirtualCopyPresentation) {
        guard value != presentation else { return }
        willChange()
        presentation = value
    }
}
