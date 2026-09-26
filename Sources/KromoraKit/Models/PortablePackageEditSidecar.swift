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

    init(
        assetID: PortablePhotoAssetID,
        revision: UInt64,
        createdAt: Date = Date(),
        document: EditDocument,
        lookReferences: [PortablePackageLookReference] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.assetID = assetID
        self.revision = revision
        self.createdAt = createdAt
        self.document = document
        self.lookReferences = lookReferences
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

extension PortableLibraryPackage {
    /// Appends one immutable edit revision and its XMP companion through the package transaction
    /// protocol. A new revision is always chosen; an existing revision path is never overwritten.
    @discardableResult
    func appendEditRevision(
        for assetID: PortablePhotoAssetID,
        document: EditDocument,
        lookBytes: [Data] = [],
        lease: PortablePackageLease,
        now: Date = Date(),
        isCancelled: @Sendable () -> Bool = { false },
        faultInjector: PortablePackageFaultInjector? = nil
    ) throws -> PortablePackageEditSidecar {
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
        let shard = PortableLibraryPackage.shard(for: assetID)
        let base = "Assets/\(shard)/\(assetID.raw)"
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
            document: document, lookReferences: references
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

            record.currentRevision = max(record.currentRevision + 1, nextRevision)
            record.editHistory.currentRevision = nextRevision
            record.editHistory.edits.append(
                .init(revision: nextRevision, relativePath: nativePath, xmpRelativePath: xmpPath)
            )
            try transaction.stage(data: try encodedAssetRecord(record), at: assetRecordPath(for: assetID))
            try transaction.commit(now: now, isCancelled: isCancelled)
        } catch {
            try? transaction.abort()
            throw error
        }
        return PortablePackageEditSidecar(native: persistedRevision, xmp: xmp)
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
