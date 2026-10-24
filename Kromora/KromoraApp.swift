import SwiftUI
import KromoraKit

@main
struct KromoraApp: App {
    @NSApplicationDelegateAdaptor(KromoraAppDelegate.self) private var appDelegate

    var body: some Scene {
        KromoraScene(delegate: appDelegate)
    }
}
