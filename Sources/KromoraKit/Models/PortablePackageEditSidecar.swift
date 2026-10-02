import CryptoKit
import Foundation

/// The native, immutable payload for one edit revision.
///
/// A revision is intentionally a value rather than an update to an `EditDocument` in place. The
/// package can therefore recover the last known-good revision after a failed commit, and an older
/// package copy can still reproduce the exact render graph even if a user Look is later removed.
struct PortablePackageEditRevision: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let assetID: PortablePhotoAssetID
    let revision: UInt64
    let createdAt: Date
    let document: EditDocument
    let lookReferences: [PortablePackageLookReference]
    /// User-authored snapshot label. Nil for ordinary edit commits.
    var snapshotName: String? = nil

    init(
        assetID: PortablePhotoAssetID,
        revision: UInt64,
        createdAt: Date = Date(),
        document: EditDocument,
        lookReferences: [PortablePackageLookReference] = [],
        snapshotName: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.assetID = assetID
        self.revision = revision
        self.createdAt = createdAt
        self.document = document
        self.lookReferences = lookReferences
        self.snapshotName = snapshotName
    }
}

/// A content-addressed Look/LUT blob referenced by an edit revision.
///
/// The bytes are kept in `Looks/<sha256>.cube`; the revision stores only this small reference. This
/// is still embedding, not a dependency on the user-facing Look browser: the package owns the
/// blob and deleting or moving a source `.cube` cannot invalidate an edit.
struct PortablePackageLookReference: Codable, Equatable, Sendable, Hashable {
    let contentHash: String
    let relativePath: String
    let byteCount: UInt64

    init(contentHash: String, relativePath: String, byteCount: UInt64) {
        self.contentHash = contentHash
        self.relativePath = relativePath
        self.byteCount = byteCount
    }

    init(data: Data) {
        let hash = SHA256.hash(data: data).portableHexString
        self.init(
            contentHash: hash,
            relativePath: "Looks/\(hash).cube",
            byteCount: UInt64(data.count)
        )
    }
}

/// The successfully parsed interoperable half of an edit revision.
struct PortablePackageXMPRepresentation: Equatable, Sendable {
    let rawData: Data
    let assetID: PortablePhotoAssetID
    let revision: UInt64
    let document: EditDocument

    /// Packet formatting and xpacket padding are not semantic edit state. The raw bytes remain
    /// available for foreign-packet preservation/export, while value equality compares the parsed
    /// representation that must survive a round-trip.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.assetID == rhs.assetID && lhs.revision == rhs.revision && lhs.document == rhs.document
    }
}

/// Both durable representations of one immutable revision.
struct PortablePackageEditSidecar: Equatable, Sendable {
    let native: PortablePackageEditRevision
    let xmp: PortablePackageXMPRepresentation
}

enum PortablePackageXMPCodec {
    private static let namespace = "https://kromora.app/ns/1.0/"

    /// Writes a small, valid XMP packet containing the exact Kromora document as a portable
    /// base64 JSON value. Keeping the Kromora payload in a namespaced XMP property makes the packet
    /// interoperable with XMP readers while avoiding lossy mappings for RAW, masks, crop, and
    /// future edit stages. Unknown/foreign XMP remains outside this writer's fixed subset.
    static func encode(
        assetID: PortablePhotoAssetID,
        revision: UInt64,
        document: EditDocument
    ) throws -> Data {
        let documentData = try PackageJSONCoder.encode(document)
        let payload = documentData.base64EncodedString()
        let asset = escape(assetID.raw)
        let encodedRevision = escape(String(revision))
        let encodedPayload = escape(payload)
        let packet = """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about="" xmlns:kromora="\(namespace)" kromora:assetID="\(asset)" kromora:revision="\(encodedRevision)" kromora:editDocument="\(encodedPayload)"/>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
        return Data(packet.utf8)
    }

    /// Parses only the fixed Kromora properties. XMLParser is deliberately used with external
    /// entity resolution disabled; malformed/truncated input returns a typed error instead of a
    /// neutral edit document.
    static func decode(_ data: Data) throws -> PortablePackageXMPRepresentation {
        guard !data.isEmpty else { throw PortablePackageError.malformedXMP("packet is empty") }
        // `shouldResolveExternalEntities = false` only blocks fetching externally-referenced
        // entities; libxml2 still expands internal <!ENTITY> definitions declared in a packet's own
        // DOCTYPE, which lets a corrupt/malicious sidecar exhaust memory (a "billion laughs" bomb)
        // before a single kromora: attribute is ever read. Valid packets from `encode` never carry a
        // DOCTYPE, so rejecting one here is a detection, not a compatibility loss.
        guard !data.containsDOCTYPE else {
            throw PortablePackageError.malformedXMP("packet declares a DOCTYPE, which is not permitted")
        }
        let probe = XMPProbe()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = probe
        guard parser.parse(), let values = probe.values else {
            let detail = parser.parserError?.localizedDescription ?? "packet is not well-formed"
            throw PortablePackageError.malformedXMP(detail)
        }
        guard let assetUUID = UUID(uuidString: values.assetID) else {
            throw PortablePackageError.malformedXMP("assetID is not a UUID")
        }
        guard let documentData = Data(base64Encoded: values.document) else {
            throw PortablePackageError.malformedXMP("editDocument is not base64")
        }
        guard let revision = UInt64(values.revision) else {
            throw PortablePackageError.malformedXMP("revision is not an unsigned integer")
        }
        let document: EditDocument
        do {
            document = try PackageJSONCoder.decode(EditDocument.self, from: documentData)
        } catch {
            throw PortablePackageError.malformedXMP("editDocument JSON is invalid: \(error.localizedDescription)")
        }
        return PortablePackageXMPRepresentation(
            rawData: data,
            assetID: PortablePhotoAssetID(uuid: assetUUID),
            revision: revision,
            document: document
        )
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private final class XMPProbe: NSObject, XMLParserDelegate {
        struct Values {
            let assetID: String
            let revision: String
            let document: String
        }

        var values: Values?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            guard elementName == "rdf:Description" || qName == "rdf:Description" else { return }
            let asset = attributeDict["kromora:assetID"]
                ?? attributeDict.first(where: { $0.key.hasSuffix(":assetID") })?.value
            let revision = attributeDict["kromora:revision"]
                ?? attributeDict.first(where: { $0.key.hasSuffix(":revision") })?.value
            let document = attributeDict["kromora:editDocument"]
                ?? attributeDict.first(where: { $0.key.hasSuffix(":editDocument") })?.value
            guard let asset, let revision, let document else { return }
            values = Values(assetID: asset, revision: revision, document: document)
        }
    }
}

/// What one edit-revision transaction published: the immutable sidecar and, when the asset has a
/// live membership entry, the membership entry carrying the geometry committed beside it.
struct PortablePackageEditCommit: Sendable {
    let sidecar: PortablePackageEditSidecar
    let membership: PortablePackageMembershipEntry?
}

extension PortablePackageAssetSummary {
    /// The presented ratio for `document` over this summary's source geometry. Nil when the source
    /// aspect is unknown, which leaves cells on the fallback shape until dimensions are read.
    func presentedAspectRatio(for document: EditDocument) -> Double? {
        guard let source = sourceAspectRatio else { return nil }
        return LibraryGridLayout.presentedAspectRatio(
            sourceAspectRatio: source, crop: document.crop, rotation: document.rotation
        )
    }
}

extension PortableLibraryPackage {
    /// Publish a source re-hash atomically with its denormalized membership summary. Callers
    /// compute the fingerprint at the source boundary; this transaction makes that value the
    /// record and grid identity together.
    @discardableResult
    func replaceSourceFingerprint(
        for assetID: PortablePhotoAssetID,
        with fingerprint: PortablePhotoSourceFingerprint,
        lease: PortablePackageLease,
        now: Date = Date()
    ) throws -> LibraryIndexEntry? {
        var record = try readAssetRecord(for: assetID)
        var shard = try readMembershipShard(Self.shard(for: assetID))
        guard let index = shard.entries.firstIndex(where: { $0.assetID == assetID }) else {
            return nil
        }
        if record.identity.sourceFingerprint == fingerprint,
           shard.entries[index].summary.sourceFingerprint == fingerprint {
            return LibraryIndexEntry(from: shard.entries[index])
        }
        if record.identity.sourceFingerprint != fingerprint {
            var updatedRecord = PortablePackageAssetRecord(
                identity: PortablePhotoIdentity(assetID: assetID, sourceFingerprint: fingerprint),
                source: record.source,
                sourceChangeSignature: record.sourceChangeSignature,
                isRemoved: record.isRemoved,
                currentRevision: record.currentRevision,
                editHistory: record.editHistory,
                copyOfAssetID: record.copyOfAssetID
            )
            updatedRecord.unknownJSONFields = record.unknownJSONFields
            record = updatedRecord
        }
        shard.entries[index].summary.sourceFingerprint = fingerprint

        var transaction = try beginTransaction(lease: lease, now: now)
        do {
            try transaction.stage(
                data: try encodedAssetRecord(record),
                at: "Assets/\(Self.shard(for: assetID))/\(assetID.raw)/asset.json"
            )
            try transaction.stage(
                data: try encodedMembershipShard(shard),
                at: "Catalog/Membership/\(Self.shard(for: assetID)).json"
            )
            try transaction.commit(now: now)
            return LibraryIndexEntry(from: shard.entries[index])
        } catch {
            try? transaction.abort()
            throw error
        }
    }

    /// Fill missing membership fingerprints from their canonical asset records. Each small batch
    /// is an independent journalled transaction, so cancellation or process death leaves a valid
    /// package and the next invocation naturally resumes at the remaining nil summaries.
    @discardableResult
    func repairSourceFingerprints(
        lease: PortablePackageLease,
        batchSize: Int = 32,
        isCancelled: @Sendable () -> Bool = { false },
        onBatch: (@Sendable ([LibraryIndexEntry]) async -> Void)? = nil
    ) async throws -> [LibraryIndexEntry] {
        let batchLimit = max(1, batchSize)
        var repaired: [LibraryIndexEntry] = []

        for shardName in Self.allShards {
            try Task.checkCancellation()
            if isCancelled() { throw CancellationError() }
            let shard = try readMembershipShard(shardName)
            let missingIDs = shard.entries
                .filter { !$0.isTombstone && $0.summary.sourceFingerprint == nil }
                .map(\.assetID)

            for start in stride(from: 0, to: missingIDs.count, by: batchLimit) {
                try Task.checkCancellation()
                if isCancelled() { throw CancellationError() }
                let ids = Array(missingIDs[start..<min(start + batchLimit, missingIDs.count)])
                let fingerprints = try await withThrowingTaskGroup(
                    of: (PortablePhotoAssetID, PortablePhotoSourceFingerprint).self
                ) { group in
                    var values: [(PortablePhotoAssetID, PortablePhotoSourceFingerprint)] = []
                    var next = ids.makeIterator()
                    for _ in 0..<min(2, ids.count) {
                        if let id = next.next() {
                            group.addTask {
                                try Task.checkCancellation()
                                return (id, try readAssetRecord(for: id).identity.sourceFingerprint)
                            }
                        }
                    }
                    while let value = try await group.next() {
                        values.append(value)
                        if let id = next.next() {
                            group.addTask {
                                try Task.checkCancellation()
                                return (id, try readAssetRecord(for: id).identity.sourceFingerprint)
                            }
                        }
                    }
                    return values
                }

                // Asset records may take long enough to read that membership changed after the
                // shard scan began. Merge this batch into a fresh shard snapshot so the repair
                // cannot overwrite newer ratings, flags, tombstones, or other summary edits.
                var commitShard = try readMembershipShard(shardName)
                for (assetID, fingerprint) in fingerprints {
                    guard let index = commitShard.entries.firstIndex(where: { $0.assetID == assetID }),
                          !commitShard.entries[index].isTombstone,
                          commitShard.entries[index].summary.sourceFingerprint == nil else { continue }
                    commitShard.entries[index].summary.sourceFingerprint = fingerprint
                }
                let entries = fingerprints.compactMap { assetID, _ in
                    commitShard.entries.first {
                        $0.assetID == assetID && !$0.isTombstone
                            && $0.summary.sourceFingerprint != nil
                    }
                        .map(LibraryIndexEntry.init(from:))
                }
                guard !entries.isEmpty else { continue }

                var transaction = try beginTransaction(lease: lease)
                do {
                    try transaction.stage(
                        data: try encodedMembershipShard(commitShard),
                        at: "Catalog/Membership/\(shardName).json"
                    )
                    try transaction.commit(isCancelled: isCancelled)
                } catch {
                    try? transaction.abort()
                    throw error
                }
                repaired.append(contentsOf: entries)
                await onBatch?(entries)
            }
        }
        return repaired
    }

    /// Appends one immutable edit revision and its XMP companion through the package transaction
    /// protocol. A new revision is always chosen; an existing revision path is never overwritten.
    @discardableResult
    func appendEditRevision(
        for assetID: PortablePhotoAssetID,
        document: EditDocument,
        snapshotName: String? = nil,
        lookBytes: [Data] = [],
        lease: PortablePackageLease,
        now: Date = Date(),
        isCancelled: @Sendable () -> Bool = { false },
        faultInjector: PortablePackageFaultInjector? = nil
    ) throws -> PortablePackageEditSidecar {
        try commitEditRevision(
            for: assetID, document: document, snapshotName: snapshotName, lookBytes: lookBytes,
            lease: lease, now: now, isCancelled: isCancelled, faultInjector: faultInjector
        ).sidecar
    }

    /// The edit-revision transaction. The membership summary's `presentedAspectRatio` is staged in
    /// the same transaction as the asset record that advances the current revision, so a reader
    /// can never observe a new edit beside old geometry, or the reverse.
    func commitEditRevision(
        for assetID: PortablePhotoAssetID,
        document: EditDocument,
        snapshotName: String? = nil,
        lookBytes: [Data] = [],
        lease: PortablePackageLease,
        now: Date = Date(),
        isCancelled: @Sendable () -> Bool = { false },
        faultInjector: PortablePackageFaultInjector? = nil
    ) throws -> PortablePackageEditCommit {
        var record = try readAssetRecord(for: assetID)
        let recordedRevision = max(
            record.currentRevision,
            record.editHistory.currentRevision,
            record.editHistory.edits.map(\.revision).max() ?? 0
        )
        // A crashed or overlapping writer can publish the sidecar files and then lose the race
        // to update this record. The next number taken only from the record then collides with
        // those files and every later save, including quit, fails forever.
        let occupiedRevision = try highestOccupiedEditRevision(for: assetID)
        var nextRevision = max(recordedRevision, occupiedRevision) + 1
        let shardName = PortableLibraryPackage.shard(for: assetID)
        let base = "Assets/\(shardName)/\(assetID.raw)"
        var nativePath = "\(base)/Edits/\(nextRevision).json"
        var xmpPath = "\(base)/Metadata/\(nextRevision).xmp"
        var collisions = 0
        while try FileManager.default.fileExists(atPath: packageURL(for: nativePath).path)
            || FileManager.default.fileExists(atPath: packageURL(for: xmpPath).path) {
            collisions += 1
            guard collisions <= 64 else {
                throw PortablePackageError.immutableRevisionExists(nativePath)
            }
            nextRevision += 1
            nativePath = "\(base)/Edits/\(nextRevision).json"
            xmpPath = "\(base)/Metadata/\(nextRevision).xmp"
        }

        var references: [PortablePackageLookReference] = []
        var seenHashes = Set<String>()
        for bytes in lookBytes {
            let reference = PortablePackageLookReference(data: bytes)
            guard seenHashes.insert(reference.contentHash).inserted else { continue }
            let blobURL = try packageURL(for: reference.relativePath)
            if FileManager.default.fileExists(atPath: blobURL.path) {
                let existing = try Data(contentsOf: blobURL)
                let actual = SHA256.hash(data: existing).portableHexString
                guard existing.count == bytes.count, actual == reference.contentHash else {
                    throw PortablePackageError.lookChecksumMismatch(
                        expected: reference.contentHash, actual: actual
                    )
                }
            }
            references.append(reference)
        }

        let revision = PortablePackageEditRevision(
            assetID: assetID, revision: nextRevision, createdAt: now,
            document: document, lookReferences: references, snapshotName: snapshotName
        )
        // JSON's ISO-8601 representation is the durable clock precision. Return the same decoded
        // value that a later reader will observe, rather than a pre-encoding Date with sub-second
        // precision that would make an otherwise identical in-memory result compare unequal.
        let nativeData = try encodePackageJSON(revision)
        let persistedRevision = try PortablePackageEditRevision.decode(from: nativeData)
        let xmpData = try PortablePackageXMPCodec.encode(
            assetID: assetID, revision: nextRevision, document: document
        )
        let xmp = try PortablePackageXMPCodec.decode(xmpData)
        guard xmp.assetID == assetID, xmp.revision == nextRevision, xmp.document == document else {
            throw PortablePackageError.malformedXMP("writer produced a mismatched packet")
        }

        var transaction = try beginTransaction(
            lease: lease, now: now, faultInjector: faultInjector
        )
        do {
            var stagedLookHashes = Set<String>()
            for bytes in lookBytes {
                let reference = PortablePackageLookReference(data: bytes)
                guard references.contains(reference), stagedLookHashes.insert(reference.contentHash).inserted else {
                    continue
                }
                let blobURL = try packageURL(for: reference.relativePath)
                if !FileManager.default.fileExists(atPath: blobURL.path) {
                    try transaction.stage(data: bytes, at: reference.relativePath)
                }
            }
            try transaction.stage(data: nativeData, at: nativePath)
            if isCancelled() { throw CancellationError() }
            try transaction.stage(data: xmpData, at: xmpPath)
            if isCancelled() { throw CancellationError() }

            // A new edit after history navigation starts a branch at the selected revision.
            // Keep named snapshots as durable, independently restorable states, while removing
            // ordinary forward edits from the active timeline. Immutable sidecar files remain
            // untouched for package recovery and any snapshot references.
            var retainedPointers = record.editHistory.edits.filter {
                $0.revision <= record.editHistory.currentRevision
            }
            for pointer in record.editHistory.edits where
                pointer.revision > record.editHistory.currentRevision {
                let forward = try readEditRevision(for: assetID, revision: pointer.revision)
                if forward.snapshotName != nil { retainedPointers.append(pointer) }
            }
            record.editHistory.edits = retainedPointers
            record.currentRevision = max(record.currentRevision + 1, nextRevision)
            record.editHistory.currentRevision = nextRevision
            record.editHistory.edits.append(
                .init(
                    revision: nextRevision,
                    relativePath: nativePath,
                    xmpRelativePath: xmpPath,
                    isNamedSnapshot: snapshotName != nil
                )
            )
            try transaction.stage(data: try encodedAssetRecord(record), at: assetRecordPath(for: assetID))
            let membership = try stagePresentedAspectRatio(
                for: document, assetID: assetID, in: &transaction
            )
            try transaction.commit(now: now, isCancelled: isCancelled)
            return PortablePackageEditCommit(
                sidecar: PortablePackageEditSidecar(native: persistedRevision, xmp: xmp),
                membership: membership
            )
        } catch {
            try? transaction.abort()
            throw error
        }
    }

    /// Stages the membership shard with `document`'s presented geometry into `transaction`.
    /// Returns the asset's membership entry as it will read after commit, or nil when the asset
    /// has no live membership entry (nothing to denormalize into).
    private func stagePresentedAspectRatio(
        for document: EditDocument,
        assetID: PortablePhotoAssetID,
        in transaction: inout PortablePackageTransaction
    ) throws -> PortablePackageMembershipEntry? {
        let shardName = PortableLibraryPackage.shard(for: assetID)
        // A failure to read a shard is different from an asset with no live membership entry.
        // Swallowing it here would let the asset record publish a new edit revision while the
        // library keeps exposing its old geometry. Propagate the error so the whole transaction
        // aborts; only the absence of a live entry is a legitimate no-op.
        var shard = try readMembershipShard(shardName)
        guard let index = shard.entries.firstIndex(where: {
                  $0.assetID == assetID && !$0.isTombstone
              })
        else { return nil }
        let presented = shard.entries[index].summary.presentedAspectRatio(for: document)
        if shard.entries[index].summary.presentedAspectRatio != presented {
            shard.entries[index].summary.presentedAspectRatio = presented
            try transaction.stage(
                data: try encodedMembershipShard(shard),
                at: "Catalog/Membership/\(shardName).json"
            )
        }
        return shard.entries[index]
    }

    /// Recompute `presentedAspectRatio` for every live asset whose summary lacks the current
    /// edit's geometry, reading each asset's current edit sidecar. This is the explicit repair for
    /// packages written before the field existed; the sidecar remains the truth and the summary is
    /// rebuilt from it. Returns the assets whose summary changed.
    @discardableResult
    func repairPresentedAspectRatios(
        lease: PortablePackageLease,
        now: Date = Date(),
        isCancelled: @Sendable () -> Bool = { false }
    ) throws -> [PortablePhotoAssetID] {
        var repaired: [PortablePhotoAssetID] = []
        for shardName in Self.allShards {
            if isCancelled() { throw CancellationError() }
            var shard = try readMembershipShard(shardName)
            var changed = false
            for index in shard.entries.indices where !shard.entries[index].isTombstone {
                let assetID = shard.entries[index].assetID
                let document: EditDocument
                if let record = try? readAssetRecord(for: assetID), record.currentRevision > 0,
                   let revision = try? readEditRevision(for: assetID) {
                    document = revision.document
                } else {
                    document = EditDocument()
                }
                let presented = shard.entries[index].summary.presentedAspectRatio(for: document)
                guard shard.entries[index].summary.presentedAspectRatio != presented else {
                    continue
                }
                shard.entries[index].summary.presentedAspectRatio = presented
                repaired.append(assetID)
                changed = true
            }
            guard changed else { continue }
            var transaction = try beginTransaction(lease: lease, now: now)
            do {
                try transaction.stage(
                    data: try encodedMembershipShard(shard),
                    at: "Catalog/Membership/\(shardName).json"
                )
                try transaction.commit(now: now, isCancelled: isCancelled)
            } catch {
                try? transaction.abort()
                throw error
            }
        }
        return repaired
    }

    /// The highest revision number already stored as an edit JSON or XMP sidecar.
    ///
    /// Missing directories mean no revisions have been published. Non-revision filenames are
    /// ignored so a stray file cannot make the scan fail.
    private func highestOccupiedEditRevision(for assetID: PortablePhotoAssetID) throws -> UInt64 {
        let shard = PortableLibraryPackage.shard(for: assetID)
        let base = "Assets/\(shard)/\(assetID.raw)"
        var highest: UInt64 = 0
        for directory in ["Edits", "Metadata"] {
            let url = try packageURL(for: "\(base)/\(directory)")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let names = try FileManager.default.contentsOfDirectory(atPath: url.path)
            for name in names {
                let stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
                guard let revision = UInt64(stem) else { continue }
                highest = max(highest, revision)
            }
        }
        return highest
    }

    func readEditRevision(
        for assetID: PortablePhotoAssetID,
        revision requestedRevision: UInt64? = nil
    ) throws -> PortablePackageEditRevision {
        let pointer = try editPointer(for: assetID, revision: requestedRevision)
        let data = try Data(contentsOf: packageURL(for: pointer.relativePath))
        let revision = try PackageJSONCoder.decode(PortablePackageEditRevision.self, from: data)
        guard revision.assetID == assetID, revision.revision == pointer.revision else {
            throw PortablePackageError.invalidEditRevision(pointer.relativePath)
        }
        for reference in revision.lookReferences { try validateLookReference(reference) }
        return revision
    }

    /// Returns durable revisions in package order, including named snapshots and branch points.
    func readEditHistory(for assetID: PortablePhotoAssetID) throws -> [PortablePackageEditRevision] {
        let record = try readAssetRecord(for: assetID)
        return try record.editHistory.edits
            .sorted { $0.revision < $1.revision }
            .map { try readEditRevision(for: assetID, revision: $0.revision) }
    }

    /// Moves the package's current edit position without creating a new revision. Returns the
    /// membership entry carrying the geometry committed with the move, when the asset has one.
    @discardableResult
    func selectEditRevision(
        for assetID: PortablePhotoAssetID,
        revision: UInt64,
        lease: PortablePackageLease,
        now: Date = Date()
    ) throws -> PortablePackageMembershipEntry? {
        var record = try readAssetRecord(for: assetID)
        guard record.editHistory.edits.contains(where: { $0.revision == revision }) else {
            throw PortablePackageError.invalidEditRevision("revision \(revision) is not present")
        }
        record.currentRevision = revision
        record.editHistory.currentRevision = revision
        // The selected revision's crop and rotation become the presented geometry in the same
        // transaction that moves the current-revision pointer.
        let selected = try readEditRevision(for: assetID, revision: revision)
        var transaction = try beginTransaction(lease: lease, now: now)
        do {
            try transaction.stage(
                data: try encodedAssetRecord(record), at: assetRecordPath(for: assetID)
            )
            let membership = try stagePresentedAspectRatio(
                for: selected.document, assetID: assetID, in: &transaction
            )
            try transaction.commit(now: now)
            return membership
        } catch {
            try? transaction.abort()
            throw error
        }
    }

    func readEditSidecar(
        for assetID: PortablePhotoAssetID,
        revision requestedRevision: UInt64? = nil
    ) throws -> PortablePackageEditSidecar {
        let native = try readEditRevision(for: assetID, revision: requestedRevision)
        let pointer = try editPointer(for: assetID, revision: native.revision)
        guard let xmpRelativePath = pointer.xmpRelativePath else {
            throw PortablePackageError.malformedXMP("revision has no XMP pointer")
        }
        let xmpData: Data
        do {
            xmpData = try Data(contentsOf: packageURL(for: xmpRelativePath))
        } catch {
            throw PortablePackageError.malformedXMP("XMP sidecar is unreadable: \(error.localizedDescription)")
        }
        let xmp = try PortablePackageXMPCodec.decode(xmpData)
        guard xmp.assetID == native.assetID, xmp.revision == native.revision,
              xmp.document == native.document else {
            throw PortablePackageError.malformedXMP("XMP does not match the native revision")
        }
        return PortablePackageEditSidecar(native: native, xmp: xmp)
    }

    /// Explicit critical-data recovery action. Reading reports malformed XMP by throwing; callers
    /// may then quarantine the packet for support/rebuild workflows without silently deleting it.
    @discardableResult
    func quarantineMalformedXMP(
        for assetID: PortablePhotoAssetID,
        revision requestedRevision: UInt64? = nil
    ) throws -> URL {
        let pointer = try editPointer(for: assetID, revision: requestedRevision)
        guard let xmpPath = pointer.xmpRelativePath else {
            throw PortablePackageError.malformedXMP("revision has no XMP pointer")
        }
        let source = try packageURL(for: xmpPath)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw PortablePackageError.malformedXMP("XMP sidecar is missing")
        }
        let quarantine = try packageURL(
            for: "Recovery/Quarantine/\(assetID.raw)-\(pointer.revision)-\(UUID().uuidString).xmp"
        )
        try FileManager.default.createDirectory(
            at: quarantine.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: source, to: quarantine)
        return quarantine
    }

    func readEmbeddedLook(_ reference: PortablePackageLookReference) throws -> Data {
        try validateLookReference(reference)
        let url = try packageURL(for: reference.relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PortablePackageError.missingLook(reference.contentHash)
        }
        let data = try Data(contentsOf: url)
        let actual = SHA256.hash(data: data).portableHexString
        guard UInt64(data.count) == reference.byteCount, actual == reference.contentHash else {
            throw PortablePackageError.lookChecksumMismatch(
                expected: reference.contentHash, actual: actual
            )
        }
        return data
    }

    private func editPointer(
        for assetID: PortablePhotoAssetID,
        revision requestedRevision: UInt64?
    ) throws -> PortablePackageEditPointer {
        let record = try readAssetRecord(for: assetID)
        let revision = requestedRevision ?? record.editHistory.currentRevision
        guard revision > 0,
              let pointer = record.editHistory.edits.first(where: { $0.revision == revision }) else {
            throw PortablePackageError.invalidEditRevision("revision \(revision) is not present")
        }
        return pointer
    }

    private func validateLookReference(_ reference: PortablePackageLookReference) throws {
        guard reference.contentHash.count == 64,
              reference.contentHash.allSatisfy({ $0.isHexDigit }),
              reference.relativePath == "Looks/\(reference.contentHash).cube" else {
            throw PortablePackageError.invalidLookReference(reference.relativePath)
        }
    }

    private func assetRecordPath(for assetID: PortablePhotoAssetID) -> String {
        "Assets/\(PortableLibraryPackage.shard(for: assetID))/\(assetID.raw)/asset.json"
    }

    private func encodePackageJSON<T: Encodable>(_ value: T) throws -> Data {
        try PackageJSONCoder.encode(value)
    }
}

private extension PortablePackageEditRevision {
    static func decode(from data: Data) throws -> Self {
        try PackageJSONCoder.decode(Self.self, from: data)
    }
}

private extension SHA256.Digest {
    var portableHexString: String { map { String(format: "%02x", $0) }.joined() }
}

private extension Data {
    var containsDOCTYPE: Bool {
        range(of: Data("<!DOCTYPE".utf8)) != nil
    }
}
