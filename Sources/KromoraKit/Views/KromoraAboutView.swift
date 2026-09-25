import SwiftUI
import Foundation

/// Bundle metadata used by the About window. Missing values identify an unbundled development run.
struct KromoraAboutMetadata: Equatable {
    let version: String
    let build: String

    init(infoDictionary: [String: Any]) {
        version = Self.value(for: "CFBundleShortVersionString", in: infoDictionary)
            ?? "Development build"
        build = Self.value(for: "CFBundleVersion", in: infoDictionary)
            ?? "Unavailable in development build"
    }

    init(bundle: Bundle = .main) {
        self.init(infoDictionary: bundle.infoDictionary ?? [:])
    }

    private static func value(for key: String, in infoDictionary: [String: Any]) -> String? {
        guard let value = infoDictionary[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The app's About window, available from the standard macOS App menu in every build.
public struct KromoraAboutView: View {
    public static let windowID = "kromora-about"

    private let metadata: KromoraAboutMetadata
    private let licenseText: String
    private let starterLookManifest: BundledLookManifest

    public init() {
        metadata = KromoraAboutMetadata()
        licenseText = KromoraKitResourceBundle.data(forResource: "LICENSE", withExtension: "txt")
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "The MIT license text is available from the Kromora project license source."
        starterLookManifest = BundledLookLibrary.load().manifest
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .center, spacing: 6) {
                    Text("Kromora")
                        .font(.largeTitle.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Version \(metadata.version) · Build \(metadata.build)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Version \(metadata.version), build \(metadata.build)")
                }
                .frame(maxWidth: .infinity)

                GroupBox("Developed by") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Daniel Hardy")
                        Text("Kromora began as a fork of LUTzy by tsvb. Original LUTzy copyright attribution to Tim is retained in the license.")
                        Link("View the original LUTzy project", destination: Self.lutzyURL)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }

                GroupBox("MIT License") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Copyright © 2026 Tim and Daniel Hardy")
                            .font(.subheadline)
                        Text(licenseText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Complete MIT License text")
                        Link("Open the canonical license source", destination: Self.licenseURL)
                    }
                    .padding(.top, 4)
                }

                GroupBox("Bundled Starter Looks") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(starterLookManifest.acknowledgement)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(starterLookManifest.looks, id: \.id) { look in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(look.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("License: \(look.license)")
                                Text("Attribution: \(look.attribution)")
                                Text("Redistribution: \(look.redistribution)")
                            }
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.top, 4)
                }
            }
            .padding(20)
        }
        .accessibilityLabel("About Kromora")
    }

    private static let lutzyURL = URL(string: "https://github.com/tsvb/lutzy")!
    private static let licenseURL = URL(string: "https://github.com/danielhardy/Kromora/blob/main/LICENSE")!
}
