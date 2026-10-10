import SwiftUI
import AppKit

/// Image-first picker for a mounted removable volume. It has no folder-navigation affordance on
/// purpose: the volume has already been selected from the Import menu and this sheet is only for
/// choosing files and explicitly adding them to the library.
struct RemovableMediaSelectorView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if viewModel.isRemovableMediaScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Scanning \(viewModel.removableMediaVolume?.name ?? "volume")…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.removableMediaFiles.isEmpty {
                ContentUnavailableView(
                    "No Supported Images",
                    systemImage: "externaldrive",
                    description: Text("This volume has no readable images Kromora can open.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                fileList
            }
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 540)
        .tint(KromoraTheme.primaryAccent)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Label(viewModel.removableMediaVolume?.name ?? "Removable Media", systemImage: "externaldrive.connected.to.line.below")
                    .font(.headline)
                if let accessHint = viewModel.removableMediaVolume?.accessHint {
                    Text(accessHint)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if !viewModel.removableMediaFiles.isEmpty {
                Text("\(viewModel.removableMediaSelection.count) of \(viewModel.removableMediaFiles.count) selected")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .padding(16)
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("Select All") { viewModel.selectAllRemovableMedia() }
                Button("Select None") { viewModel.selectNoRemovableMedia() }
                Spacer()
                Text("Shift-click to select a range. Source files are not changed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if !viewModel.removableMediaWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.removableMediaWarnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                    ForEach(MediaVolumeDayGroup.groups(for: viewModel.removableMediaFiles)) { group in
                        Section {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: Self.cellWidth), spacing: 10)],
                                alignment: .leading,
                                spacing: 10
                            ) {
                                ForEach(group.files) { file in
                                    cell(for: file)
                                }
                            }
                        } header: {
                            dayHeader(for: group)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private static let cellWidth: CGFloat = 128

    private func dayHeader(for group: MediaVolumeDayGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(group.day.map { $0.formatted(.dateTime.weekday(.wide).month(.wide).day().year()) } ?? "Unknown Date")
                .font(.headline)
            Text("\(group.files.count)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func cell(for file: MediaVolumeFile) -> some View {
        let isSelected = viewModel.removableMediaSelection.contains(file)
        return Button {
            if NSEvent.modifierFlags.contains(.shift) {
                viewModel.selectRemovableMediaRange(to: file)
            } else {
                viewModel.toggleRemovableMediaSelection(file)
            }
        } label: {
            RemovableMediaThumbnail(url: file.url)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.85),
                                         isSelected ? KromoraTheme.primaryAccent : Color.black.opacity(0.35))
                        .padding(6)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isSelected ? KromoraTheme.primaryAccent : Color.clear, lineWidth: 3)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(file.filename)
        .accessibilityLabel(file.filename)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var footer: some View {
        HStack {
            if let progress = viewModel.removableMediaImportProgress {
                ProgressView(value: progress.fraction)
                    .frame(width: 130)
                Text(progress.cancelled
                     ? "Import cancelled"
                     : "Imported \(progress.imported), duplicate \(progress.duplicates), skipped \(progress.skipped), failed \(progress.failed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { viewModel.cancelRemovableMediaImport() }
                .keyboardShortcut(.cancelAction)
            Button("Import Selected to Library") { viewModel.importSelectedRemovableMedia() }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isRemovableMediaScanning || viewModel.selectedRemovableMediaFiles.isEmpty)
        }
        .padding(16)
    }
}

private struct RemovableMediaThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .overlay { ProgressView().scaleEffect(0.55) }
            }
        }
        .frame(width: 128, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: url) {
            image = await Task.detached(priority: .utility) {
                Thumbnails.generate(from: url, maxPixelSize: 256)
            }.value
        }
    }
}
