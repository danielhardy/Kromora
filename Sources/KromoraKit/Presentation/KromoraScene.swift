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
            KromoraRootView(viewModel: delegate.viewModel)
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
            KromoraCommands(settings: delegate.viewModel.settings)
        }

        Settings {
            KromoraSettingsScene(viewModel: delegate.viewModel)
        }
    }
}

@MainActor
private struct KromoraRootView: View {
    let viewModel: AppViewModel

    var body: some View {
        ContentView(viewModel: viewModel)
    }
}

@MainActor
private struct KromoraSettingsScene: View {
    let viewModel: AppViewModel
    @State private var editDatabaseURL: URL?

    var body: some View {
        KromoraSettingsView(
            settings: viewModel.settings,
            editDatabaseURL: editDatabaseURL
        )
        .task {
            editDatabaseURL = await viewModel.editDatabaseURL
        }
    }
}
