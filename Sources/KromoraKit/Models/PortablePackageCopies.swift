import Foundation

extension PortableLibraryPackage {
    /// Links an imported duplicate to its source while keeping the copy's asset ID and edits
    /// independent. Membership and identity are committed together.
    func markVirtualCopy(
        _ copyID: PortablePhotoAssetID,
        of sourceID: PortablePhotoAssetID,
        displayName: String,
        lease: PortablePackageLease,
        now: Date = Date()
    ) throws {
        guard copyID != sourceID else {
            throw PortablePackageError.invalidVirtualCopy("a photo cannot copy itself")
        }
        var record = try readAssetRecord(for: copyID)
        _ = try readAssetRecord(for: sourceID)
        record.copyOfAssetID = sourceID
        let shardName = Self.shard(for: copyID)
        var shard = try readMembershipShard(shardName)
        guard let index = shard.entries.firstIndex(where: { $0.assetID == copyID }) else {
            throw PortablePackageError.duplicateAsset("missing copy membership: \(copyID.raw)")
        }
        shard.entries[index].summary.displayName = displayName

        var transaction = try beginTransaction(lease: lease, now: now)
        do {
            try transaction.stage(
                data: try encodedAssetRecord(record),
                at: "Assets/\(Self.shard(for: copyID))/\(copyID.raw)/asset.json"
            )
            try transaction.stage(
                data: try encodedMembershipShard(shard),
                at: "Catalog/Membership/\(shardName).json"
            )
            try transaction.commit(now: now)
        } catch {
            try? transaction.abort()
            throw error
        }
    }
}
