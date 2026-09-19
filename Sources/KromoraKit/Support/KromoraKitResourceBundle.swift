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

    /// SwiftPM `.copy("Resources")` preserves that directory, so shader sources live at
    /// `Resources/<name>.metal` in packaged and `swift run` bundles. Some SwiftPM module
    /// layouts also expose them at the resource root. Try both.
    static func url(forMetalSource named: String) -> URL? {
        if let url = bundle.url(
            forResource: named, withExtension: "metal", subdirectory: "Resources"
        ) {
            return url
        }
        return bundle.url(forResource: named, withExtension: "metal")
    }

    static func metalSource(named: String) -> String? {
        guard let url = url(forMetalSource: named) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
