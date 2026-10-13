import SwiftUI

/// The application scenes shared by every Kromora launcher.
@MainActor
public struct KromoraScene: Scene {
    private let delegate: KromoraAppDelegate

    public init(delegate: KromoraAppDelegate) {
        self.delegate = delegate
    }

    public var body: some Scene {
        WindowGroup {
            KromoraRootView(launch: delegate.launch)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)

        Window("About Kromora", id: KromoraAboutView.windowID) {
            KromoraAboutView()
                .frame(minWidth: 360, idealWidth: 420, minHeight: 440, idealHeight: 520)
        }
        .windowResizability(.contentSize)
        .commands {
            KromoraCommands(settings: delegate.launch.settings)
        }

        Settings {
            KromoraSettingsScene(launch: delegate.launch)
        }
    }
}

/// Deliberately not `private`: SwiftUI derives the window-frame autosave key from this type's
/// name, and a private type's name embeds a per-build context address, so the saved frame would
/// never be found again on the next launch.
@MainActor
struct KromoraRootView: View {
    let launch: AppLaunch

    var body: some View {
        if let viewModel = launch.viewModel {
            ContentView(viewModel: viewModel)
        } else {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { await launch.open() }
        }
    }
}

@MainActor
private struct KromoraSettingsScene: View {
    let launch: AppLaunch
    @State private var editDatabaseURL: URL?

    var body: some View {
        KromoraSettingsView(
            settings: launch.settings,
            editDatabaseURL: editDatabaseURL
        )
        .task {
            editDatabaseURL = await launch.open().editDatabaseURL
        }
    }
}
