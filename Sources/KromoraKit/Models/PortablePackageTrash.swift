import Foundation

/// Package-native removal is deliberately separate from the current folder-backed Library
/// deletion workflow (KRMA-371). It changes only a portable package and never calls the current
/// library's deletion or Trash code.
enum PortablePackageTrashError: Error, Equatable, CustomStringConvertible {
    case assetNotFound(PortablePhotoAssetID)
    case alreadyRemoved(PortablePhotoAssetID)
    case missingQuarantine(PortablePhotoAssetID)
    case confirmationRequired
    case referencedAssetNotOwned(PortablePhotoAssetID)

    var description: String {
        switch self {
        case .assetNotFound(let assetID): return "Package asset was not found: \(assetID.raw)"
        case .alreadyRemoved(let assetID): return "Package asset is already removed: \(assetID.raw)"
        case .missingQuarantine(let assetID):
            return "Quarantine is missing for package asset: \(assetID.raw)"
        case .confirmationRequired:
            return "Reclaim space requires explicit user confirmation"
        case .referencedAssetNotOwned(let assetID):
            return "Referenced asset is not owned by the package: \(assetID.raw)"
        }
    }
}

struct PortablePackageRemovalResult: Equatable, Sendable {
    let assetID: PortablePhotoAssetID
    let wasReferenced: Bool
    let quarantinedURL: URL?
}

struct PortablePackageRestoreResult: Equatable, Sendable {
    let assetID: PortablePhotoAssetID
    let wasReferenced: Bool
}

struct PortablePackageReclaimResult: Equatable, Sendable {
    let reclaimedAssetIDs: [PortablePhotoAssetID]
    let skippedReferencedAssetIDs: [PortablePhotoAssetID]
    let bytesReclaimed: UInt64
}

extension PortableLibraryPackage {
    /// Removes a package-owned asset by tombstoning membership and moving the complete asset
    /// directory into Recovery/Quarantine. The move is journalled, so a failed commit restores
    /// both the directory and the prior membership shard.
    func removeFromLibrary(
        _ assetID: PortablePhotoAssetID,
        lease: PortablePackageLease,
        now: Date = Date(),
        faultInjector: PortablePackageFaultInjector? = nil
    ) throws -> PortablePackageRemovalResult {
        let shardName = Self.shard(for: assetID)
        var shard = try readMembershipShard(shardName)
        guard let entryIndex = shard.entries.firstIndex(where: { $0.assetID == assetID }) else {
            throw PortablePackageTrashError.assetNotFound(assetID)
        }
        guard !shard.entries[entryIndex].isTombstone else {
            throw PortablePackageTrashError.alreadyRemoved(assetID)
        }
        let record = try readAssetRecord(for: assetID)
        let referenced = record.source.storage == .referenced
        let revision = max(
            record.currentRevision,
            shard.entries[entryIndex].summary.assetRevision
        ) + 1

        var tombstone = shard.entries[entryIndex]
        tombstone.deletedRevision = revision
        tombstone.isTombstone = true
        tombstone.summary.assetRevision = revision
        shard.entries[entryIndex] = tombstone

        var removedRecord = record
        removedRecord.isRemoved = true
        var transaction = try beginTransaction(
            lease: lease, now: now, faultInjector: faultInjector)
        do {
            if referenced {
                try transaction.stage(
                    data: try encodedAssetRecord(removedRecord),
                    at: recordPath(for: assetID)
                )
            } else {
                let activeDirectory = "Assets/\(shardName)/\(assetID.raw)"
                let quarantineDirectory = "Recovery/Quarantine/\(assetID.raw)"
                try transaction.stageMove(from: activeDirectory, to: quarantineDirectory)
                try transaction.stage(
                    data: try encodedAssetRecord(removedRecord),
                    at: "\(quarantineDirectory)/asset.json"
                )
            }
            try transaction.stage(
                data: try encodedMembershipShard(shard),
                at: "Catalog/Membership/\(shardName).json"
            )
            try transaction.commit(now: now)
        } catch {
            try? transaction.abort()
            throw error
        }

        return PortablePackageRemovalResult(
            assetID: assetID,
            wasReferenced: referenced,
            quarantinedURL: referenced ? nil : quarantineDirectoryURL(for: assetID)
        )
    }

    /// Restores a tombstoned asset before reclaim. The original package directory is moved back
    /// atomically; the external source of a referenced asset is never opened or modified.
    func restoreFromQuarantine(
        _ assetID: PortablePhotoAssetID,
        lease: PortablePackageLease,
        now: Date = Date(),
        faultInjector: PortablePackageFaultInjector? = nil
    ) throws -> PortablePackageRestoreResult {
        let shardName = Self.shard(for: assetID)
        var shard = try readMembershipShard(shardName)
        guard let entryIndex = shard.entries.firstIndex(where: { $0.assetID == assetID }) else {
            throw PortablePackageTrashError.assetNotFound(assetID)
        }
        guard shard.entries[entryIndex].isTombstone else {
            throw PortablePackageTrashError.alreadyRemoved(assetID)
        }

        let activeRecordPath = recordPath(for: assetID)
        let activeURL = rootURL.appendingPathComponent(activeRecordPath)
        let quarantineURL = quarantineDirectoryURL(for: assetID)
        let referenced: Bool
        let record: PortablePackageAssetRecord
        if FileManager.default.fileExists(atPath: activeURL.path) {
            record = try readAssetRecord(for: assetID)
            referenced = record.source.storage == .referenced
        } else {
            guard FileManager.default.fileExists(atPath: quarantineURL.path) else {
                throw PortablePackageTrashError.missingQuarantine(assetID)
            }
            record = try readAssetRecord(
                atRelativePath: "Recovery/Quarantine/\(assetID.raw)/asset.json")
            referenced = record.source.storage == .referenced
        }

        var restoredRecord = record
        restoredRecord.isRemoved = false
        var restoredEntry = shard.entries[entryIndex]
        restoredEntry.isTombstone = false
        restoredEntry.deletedRevision = nil
        shard.entries[entryIndex] = restoredEntry

        var transaction = try beginTransaction(
            lease: lease, now: now, faultInjector: faultInjector)
        do {
            if referenced {
                try transaction.stage(
                    data: try encodedAssetRecord(restoredRecord), at: activeRecordPath)
            } else {
                guard !FileManager.default.fileExists(atPath: activeURL.path) else {
                    throw PortablePackageTrashError.missingQuarantine(assetID)
                }
                try transaction.stageMove(
                    from: "Recovery/Quarantine/\(assetID.raw)",
                    to: "Assets/\(shardName)/\(assetID.raw)"
                )
                try transaction.stage(
                    data: try encodedAssetRecord(restoredRecord),
                    at: activeRecordPath
                )
            }
            try transaction.stage(
                data: try encodedMembershipShard(shard),
                at: "Catalog/Membership/\(shardName).json"
            )
            try transaction.commit(now: now)
        } catch {
            try? transaction.abort()
            throw error
        }
        return PortablePackageRestoreResult(assetID: assetID, wasReferenced: referenced)
    }

    /// Permanently reclaims only package-owned quarantine directories. `confirmed` is required at
    /// the API boundary; no automatic recovery, open, edit, or ordinary remove operation calls
    /// this method. Tombstones remain in membership so an older backup cannot resurrect an asset.
    func reclaimSpace(
        confirmed: Bool,
        lease: PortablePackageLease,
        now: Date = Date(),
        faultInjector: PortablePackageFaultInjector? = nil
    ) throws -> PortablePackageReclaimResult {
        guard confirmed else { throw PortablePackageTrashError.confirmationRequired }

        var reclaimable: [(PortablePhotoAssetID, String, UInt64)] = []
        var referenced: [PortablePhotoAssetID] = []
        for shardName in Self.allShards {
            let shard = try readMembershipShard(shardName)
            for entry in shard.entries where entry.isTombstone {
                let activeRecordURL = rootURL.appendingPathComponent(entry.recordPath)
                let quarantinePath = "Recovery/Quarantine/\(entry.assetID.raw)"
                let quarantineRecordPath = "\(quarantinePath)/asset.json"
                let record: PortablePackageAssetRecord
                if FileManager.default.fileExists(atPath: activeRecordURL.path) {
                    record = try readAssetRecord(for: entry.assetID)
                } else if FileManager.default.fileExists(
                    atPath: rootURL.appendingPathComponent(quarantineRecordPath).path
                ) {
                    record = try readAssetRecord(atRelativePath: quarantineRecordPath)
                } else {
                    throw PortablePackageTrashError.missingQuarantine(entry.assetID)
                }
                if record.source.storage == .referenced {
                    referenced.append(entry.assetID)
                    continue
                }
                let directory = rootURL.appendingPathComponent(quarantinePath)
                guard FileManager.default.fileExists(atPath: directory.path) else {
                    throw PortablePackageTrashError.missingQuarantine(entry.assetID)
                }
                reclaimable.append((entry.assetID, quarantinePath, directoryByteCount(directory)))
            }
        }

        // Reclaim the batch in one journal. A failed/dropped reclaim therefore restores every
        // quarantine directory instead of leaving an unreported partially emptied trash.
        if !reclaimable.isEmpty {
            var transaction = try beginTransaction(
                lease: lease, now: now, faultInjector: faultInjector)
            do {
                for (_, path, _) in reclaimable {
                    try transaction.stageRemoval(at: path)
                }
                try transaction.commit(now: now)
            } catch {
                try? transaction.abort()
                throw error
            }
        }
        let reclaimed = reclaimable.map(\.0).sorted { $0.raw < $1.raw }
        let bytes = reclaimable.reduce(into: UInt64(0)) { $0 += $1.2 }
        return PortablePackageReclaimResult(
            reclaimedAssetIDs: reclaimed,
            skippedReferencedAssetIDs: referenced.sorted { $0.raw < $1.raw },
            bytesReclaimed: bytes
        )
    }

    private func recordPath(for assetID: PortablePhotoAssetID) -> String {
        "Assets/\(Self.shard(for: assetID))/\(assetID.raw)/asset.json"
    }

    private func directoryByteCount(_ url: URL) -> UInt64 {
        let fm = FileManager.default
        guard let urls = fm.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) else { return 0 }
        var total: UInt64 = 0
        for case let item as URL in urls {
            guard let values = try? item.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true else { continue }
            total += UInt64(max(0, values.fileSize ?? 0))
        }
        return total
    }
}
