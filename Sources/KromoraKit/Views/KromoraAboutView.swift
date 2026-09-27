import AppKit
import SwiftUI
import Foundation

/// Bundle metadata used by the About window. Missing values identify an unbundled development run.
struct KromoraAboutMetadata: Equatable {
    let version: String
    let commitIdentifier: String?

    init(infoDictionary: [String: Any]) {
        version = Self.value(for: "CFBundleShortVersionString", in: infoDictionary)
            ?? "Development build"
        commitIdentifier = Self.value(for: "KromoraGitCommit", in: infoDictionary)
    }

    init(bundle: Bundle = .main) {
        self.init(infoDictionary: bundle.infoDictionary ?? [:])
    }

    var versionLabel: String {
        guard let commitIdentifier else { return "Version \(version)" }
        return "Version \(version) · \(commitIdentifier)"
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

    public init() {
        metadata = KromoraAboutMetadata()
    }

    public var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 76, height: 76)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Kromora")
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(metadata.versionLabel)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(metadata.versionLabel)
            }

            Divider()
                .padding(.horizontal, 24)

            VStack(spacing: 8) {
                Text("Developed by Daniel Hardy")
                    .font(.body.weight(.medium))
                Text("Kromora began as a fork of LUTzy by tsvb. Original LUTzy copyright attribution to Tim is retained in the license.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Link("View the original LUTzy project", destination: Self.lutzyURL)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)

            Text("All included LUTs are released under the MIT License.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            Link("View the MIT License", destination: Self.licenseURL)
                .font(.callout)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("About Kromora")
    }

    private static let lutzyURL = URL(string: "https://github.com/tsvb/lutzy")!
    private static let licenseURL = URL(string: "https://github.com/danielhardy/Kromora/blob/main/LICENSE")!
}
