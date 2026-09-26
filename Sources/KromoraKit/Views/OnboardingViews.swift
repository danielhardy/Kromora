import SwiftUI

enum StarterSampleLibrary {
    static var urls: [URL] {
        ["Monterey-Beach", "Golden-Hour"].compactMap { name in
            KromoraKitResourceBundle.bundle.url(
                forResource: name, withExtension: "jpg", subdirectory: "Resources/SamplePhotos")
        }
    }
}

struct WelcomeView: View {
    let onImport: () -> Void
    let onPhotos: () -> Void
    let onSamples: () -> Void
    let onTour: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Welcome to Kromora", systemImage: "camera.aperture")
                .font(.largeTitle.weight(.semibold))
            Text("Build a portable photo library, make a first edit, and export a finished image.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Button(action: onImport) { Label("Import photos…", systemImage: "photo.badge.plus") }
                    .buttonStyle(.borderedProminent)
                Button(action: onPhotos) { Label("Import from Photos…", systemImage: "photo.on.rectangle") }
                    .buttonStyle(.bordered)
                Button(action: onSamples) { Label("Try the sample library", systemImage: "sparkles.rectangle.stack") }
                    .buttonStyle(.bordered)
            }

            HStack {
                Button("Take the quick tour", action: onTour)
                    .buttonStyle(.link)
                Spacer()
                Button("Start with an empty library", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 440)
    }
}

struct WorkflowTourView: View {
    enum Page: Int, CaseIterable {
        case library, edit, export

        var title: String {
            switch self {
            case .library: "Library"
            case .edit: "Edit"
            case .export: "Export"
            }
        }

        var detail: String {
            switch self {
            case .library: "Import photos into your open library, then browse, rate, and pick the frames you want to develop."
            case .edit: "Choose a photo to open the editor. Adjustments are non-destructive and each guided step can be undone."
            case .export: "Export the edited photo with ⌘S. Your library keeps the original and edit history together."
            }
        }

        var symbol: String {
            switch self {
            case .library: "square.grid.2x2"
            case .edit: "slider.horizontal.3"
            case .export: "square.and.arrow.up"
            }
        }

        var actionTitle: String {
            switch self {
            case .library: "Show Library"
            case .edit: "Show Edit"
            case .export: "Open Export…"
            }
        }
    }

    @State private var page: Page = .library
    let onAction: (Page) -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Quick tour")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("\(page.rawValue + 1) of \(Page.allCases.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Label(page.title, systemImage: page.symbol)
                .font(.title3.weight(.medium))
            Text(page.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(page.actionTitle) { onAction(page) }
                .buttonStyle(.bordered)
            HStack {
                if page != .library {
                    Button("Back") { page = Page(rawValue: page.rawValue - 1) ?? .library }
                }
                Spacer()
                if page == .export {
                    Button("Done", action: onDone).keyboardShortcut(.defaultAction)
                } else {
                    Button("Next") { page = Page(rawValue: page.rawValue + 1) ?? .export }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(26)
        .frame(width: 400)
    }
}

struct KeyboardShortcutReferenceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private struct Entry: Identifiable {
        let action: String
        let keys: String
        let area: String
        var id: String { action }
    }

    private let entries = [
        Entry(action: "Open photos", keys: "⌘O", area: "Library"),
        Entry(action: "Import from Photos", keys: "⌘⇧I", area: "Library"),
        Entry(action: "Open source folder", keys: "⌘⌥I", area: "Library"),
        Entry(action: "Refresh library", keys: "⌘R", area: "Library"),
        Entry(action: "Delete selected photos", keys: "Delete", area: "Library"),
        Entry(action: "Move between Library and Edit", keys: "G / E", area: "Navigation"),
        Entry(action: "Select previous / next photo", keys: "← / →", area: "Library and Edit"),
        Entry(action: "Pick / reject photo", keys: "P / X", area: "Library"),
        Entry(action: "Rate photo", keys: "0–5", area: "Library"),
        Entry(action: "Undo / redo edit", keys: "⌘Z / ⇧⌘Z", area: "Edit"),
        Entry(action: "Reset photo", keys: "⇧⌘R", area: "Edit"),
        Entry(action: "Show original", keys: "Space or ⌘\\", area: "Edit"),
        Entry(action: "Toggle comparison", keys: "V", area: "Edit"),
        Entry(action: "Export edited photo", keys: "⌘S", area: "Edit")
    ]

    private var filtered: [Entry] {
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.action.localizedCaseInsensitiveContains(query)
                || $0.keys.localizedCaseInsensitiveContains(query)
                || $0.area.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search shortcuts", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(14)
            List(filtered) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.action)
                        Text(entry.area).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(entry.keys).font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 460, height: 480)
    }
}

@MainActor
struct GuidedEditStep: Identifiable {
        let id: String
        let title: String
        let note: String
        let symbol: String
        let apply: (inout EditDocument) -> Void

    static let all: [GuidedEditStep] = [
        GuidedEditStep(id: "exposure", title: "Brighten the image", note: "Exposure moves the whole image up or down.", symbol: "sun.max") {
            $0.light.exposure = min(LightAdjustments.exposureRange.upperBound, $0.light.exposure + 0.35)
        },
        GuidedEditStep(id: "shadows", title: "Open the shadows", note: "Shadows bring detail out of darker areas.", symbol: "sun.haze") {
            $0.light.shadows = min(LightAdjustments.shadowsRange.upperBound, $0.light.shadows + 22)
        },
        GuidedEditStep(id: "contrast", title: "Add a little contrast", note: "Contrast increases separation between dark and bright tones.", symbol: "circle.lefthalf.filled") {
            $0.light.contrast = min(LightAdjustments.contrastRange.upperBound, $0.light.contrast + 0.12)
        }
    ]
}

struct GuidedEditCards: View {
    @ObservedObject var viewModel: AppViewModel
    @AppStorage("guidedEditCardsDismissed") private var dismissed = false

    var body: some View {
        if !dismissed {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label("Try a first edit", systemImage: "wand.and.stars")
                        .font(.headline)
                    Spacer()
                    Button { dismissed = true } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss guided edit cards")
                }
                Text("Each step makes one normal, undoable edit.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(GuidedEditStep.all) { step in
                    Button {
                        viewModel.updateDocument(step.apply)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: step.symbol).frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title).font(.subheadline.weight(.medium))
                                Text(step.note).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Apply as a single undoable edit")
                    Divider()
                }
                HStack {
                    Spacer()
                    Button("Undo the last step") { viewModel.undo() }
                        .disabled(!viewModel.canUndo)
                        .buttonStyle(.link)
                }
            }
            .padding(14)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12)))
            .padding(16)
        }
    }
}
