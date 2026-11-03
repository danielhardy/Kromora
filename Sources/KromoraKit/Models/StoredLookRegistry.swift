import Foundation
import os.lock

/// The Look a saved package revision was written with, as the package alone can reproduce it.
///
/// `EditDocument` stores only a `LUTID`. A path or starter ID names whatever file currently sits
/// there, so a moved profile, a deleted cube, or a file replaced in place would change an old
/// revision's pixels. The revision's content-addressed `PortablePackageLookReference` names the
/// exact bytes, and the package owns them under `Looks/<sha256>.cube`.
enum StoredLook: Sendable, Equatable {
    /// The embedded bytes were read, verified against the stored hash, and parsed.
    case embedded(CubeLUT)
    /// The revision names embedded bytes that could not be loaded (missing, corrupt, unparsable).
    /// Only a library Look with exactly these bytes may stand in; anything else would present a
    /// different grade as the saved one.
    case unavailable(id: LUTID, contentHash: String)

    var lutID: LUTID {
        switch self {
        case .embedded(let look): return look.lutID
        case .unavailable(let id, _): return id
        }
    }

    var contentHash: String {
        switch self {
        case .embedded(let look): return look.contentHash
        case .unavailable(_, let hash): return hash
        }
    }
}

/// Thread-safe, synchronous view of each asset's current stored Look.
///
/// `EditDocumentStore` (an actor) publishes here whenever it loads, saves or navigates to a
/// revision; the editor, thumbnails, preview admission, warm-up and export read it from the main
/// actor without awaiting. An asset with no entry has no embedded reference (a legacy revision, no
/// Look, or never loaded), so callers fall back to the Look library for it.
final class StoredLookRegistry: Sendable {
    private let entries = OSAllocatedUnfairLock(initialState: [PortablePhotoAssetID: StoredLook]())

    init() {}

    func storedLook(for assetID: PortablePhotoAssetID) -> StoredLook? {
        entries.withLock { $0[assetID] }
    }

    func set(_ look: StoredLook?, for assetID: PortablePhotoAssetID) {
        entries.withLock { $0[assetID] = look }
    }

    var count: Int { entries.withLock { $0.count } }
}
