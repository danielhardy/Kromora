import SwiftUI

/// The updater's compact presentation. It intentionally offers the release page whenever an
/// install cannot be proven safe (for example, an unsigned `swift run` build or a missing DMG).
public struct UpdateSheet: View {
    @ObservedObject private var coordinator: UpdateCoordinator

    public init(coordinator: UpdateCoordinator) {
        _coordinator = ObservedObject(wrappedValue: coordinator)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(24)
        .frame(width: 520)
        .frame(minHeight: 220)
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.phase {
        case .checking:
            ProgressView("Checking for updates…")
        case .upToDate:
            message(title: "Kromora is up to date", detail: currentVersionText)
            actions { Button("Done") { coordinator.dismiss() } }
        case .available(let release):
            releaseContent(release, skipped: false)
        case .skipped(let release):
            releaseContent(release, skipped: true)
        case .downloading(let release):
            ProgressView { Text(verbatim: "Downloading Kromora \(release.version)…") }
        case .installing(let release):
            ProgressView { Text(verbatim: "Installing Kromora \(release.version)…") }
        case .failed(let error):
            message(title: "Kromora could not update", detail: error)
            actions {
                Button("Try Again") { coordinator.checkNow() }
                Button("Done") { coordinator.dismiss() }
            }
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func releaseContent(_ release: KromoraRelease, skipped: Bool) -> some View {
        Text(skipped ? "Update previously skipped" : "Kromora update available")
            .font(.title2.weight(.semibold))
        Text(release.title + " · " + release.version.description)
            .font(.headline)
        if skipped {
            Text("You skipped this version before. You can install it now or keep waiting for a newer release.")
                .foregroundStyle(.secondary)
        }
        ScrollView {
            Text(release.notes.isEmpty ? "No release notes were provided." : release.notes)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 180)
        actions {
            if coordinator.canInstallInPlace, release.diskImageURL != nil {
                Button("Install and Relaunch") { coordinator.installAndRelaunch(release) }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Open Release Page") { coordinator.openReleasePage(release) }
                    .keyboardShortcut(.defaultAction)
            }
            if !skipped { Button("Skip This Version") { coordinator.skip(release) } }
            Button("Remind Me Later") { coordinator.remindLater() }
        }
    }

    @ViewBuilder
    private func message(title: String, detail: String) -> some View {
        Text(title).font(.title2.weight(.semibold))
        Text(detail).foregroundStyle(.secondary).textSelection(.enabled)
    }

    @ViewBuilder
    private func actions(@ViewBuilder content: () -> some View) -> some View {
        HStack { Spacer(); content() }
    }

    private var currentVersionText: String {
        coordinator.currentVersion.map { "You are running Kromora \($0)." } ?? "This development build has no packaged version."
    }
}
