import CryptoKit
import Foundation

@testable import KromoraKit

enum MaskStoreTestSupport {
    static func filename(for key: MaskCacheKey) -> String {
        let identity = [
            key.identity.cacheKey,
            String(describing: key.kind),
            key.quality.rawValue,
            key.providerVersion
        ].joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "mask-" + digest + ".json"
    }
}
