import Foundation

/// Resolves KromoraKit's SwiftPM resources in both a packaged macOS app and
/// normal SwiftPM/test executions.
enum KromoraKitResourceBundle {
    static let bundle: Bundle = {
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent(
            "Kromora_KromoraKit.bundle",
            isDirectory: true
        ), let appBundle = Bundle(url: resourceURL) {
            return appBundle
        }

        return .module
    }()
}
