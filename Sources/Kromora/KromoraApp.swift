import SwiftUI
import AppKit
import KromoraKit

// The whole app lives in KromoraKit; this target is only the entry point, so the
// code can be unit-tested (`@testable` cannot import an executable target).

@main
struct KromoraApp: App {
    @NSApplicationDelegateAdaptor(KromoraAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            KromoraRootView(viewModel: appDelegate.viewModel)
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
            KromoraCommands(settings: appDelegate.viewModel.settings)
        }

        Settings {
            KromoraSettingsScene(viewModel: appDelegate.viewModel)
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
