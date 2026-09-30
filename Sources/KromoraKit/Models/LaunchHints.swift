import Foundation

/// Device-local launch accelerator. It never participates in library selection or query truth.
struct LaunchHints: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let maximumVisibleIDs = 64

    let schemaVersion: Int
    let libraryID: UUID
    let activeAssetID: PortablePhotoAssetID?
    let visibleAssetIDs: [PortablePhotoAssetID]

    init(libraryID: UUID, activeAssetID: PortablePhotoAssetID?, visibleAssetIDs: [PortablePhotoAssetID]) {
        schemaVersion = Self.currentSchemaVersion
        self.libraryID = libraryID
        self.activeAssetID = activeAssetID
        var seen = Set<PortablePhotoAssetID>()
        self.visibleAssetIDs = Array(visibleAssetIDs.filter { seen.insert($0).inserted }.prefix(Self.maximumVisibleIDs))
    }

    var isValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && visibleAssetIDs.count <= Self.maximumVisibleIDs
            && Set(visibleAssetIDs).count == visibleAssetIDs.count
    }
}

enum LaunchHintsReadResult: Sendable, Equatable {
    case missing
    case valid(LaunchHints)
    case invalid
}

/// Coalesces small operational-state writes and atomically replaces the on-disk record.
actor LaunchHintsStore {
    static let writeDelay: Duration = .milliseconds(300)
    static let maximumRecordBytes = 16 * 1024

    private let url: URL
    private var pending: LaunchHints?
    private var writeTask: Task<Void, Never>?

    init(url: URL) { self.url = url }

    func load(for libraryID: UUID) -> LaunchHintsReadResult {
        guard let data = try? Data(contentsOf: url) else { return .missing }
        guard data.count <= Self.maximumRecordBytes,
              let hints = try? JSONDecoder().decode(LaunchHints.self, from: data),
              hints.isValid, hints.libraryID == libraryID else { return .invalid }
        return .valid(hints)
    }

    func scheduleWrite(_ hints: LaunchHints) {
        pending = hints
        guard writeTask == nil else { return }
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.writeDelay)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    func flush() {
        writeTask?.cancel()
        writeTask = nil
        guard let hints = pending, let data = try? JSONEncoder().encode(hints),
              data.count <= Self.maximumRecordBytes else { return }
        pending = nil
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            var excludedURL = url
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? excludedURL.setResourceValues(resourceValues)
        } catch {
            // Operational hints are disposable; the next viewport update can retry the write.
            pending = hints
        }
    }

    func shutdown() { flush() }
}

enum LaunchHintReadPolicy {
    static let maxConcurrentReads = 2
    static let maximumHintedIDs = LaunchHints.maximumVisibleIDs
}

struct LaunchHydrationMetrics: Sendable, Equatable {
    var validation: String = "not-read"
    var usefulHits = 0
    var superseded = 0
    var bytesRead: UInt64 = 0
    var readCount = 0
    var timeToVisibleWindowMilliseconds: Double?
    var timeToFirstIndexPageMilliseconds: Double?

    var hasRequiredMeasurements: Bool {
        validation != "not-read" && usefulHits >= 0 && superseded >= 0 && readCount >= 0
            && bytesRead >= 0 && timeToVisibleWindowMilliseconds != nil
            && timeToFirstIndexPageMilliseconds != nil
    }
}
