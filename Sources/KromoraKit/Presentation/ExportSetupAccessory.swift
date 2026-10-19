import AppKit
import ImageIO

/// One row of the export review list. A value, so the table needs no model objects and a large
/// selection costs only these small structs until a row scrolls into view.
struct ExportSetupEntry: Sendable {
    let name: String
    let url: URL?
    let data: Data?
}

/// Step 1 of Export: the exact target set (count, names, lazy thumbnails) above the shared
/// settings accessory. It owns no export logic; the coordinator reads the settings back from
/// `settings` after the user continues.
@MainActor
final class ExportSetupAccessoryView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    let settings: ExportFormatAccessoryView
    let entries: [ExportSetupEntry]
    private let countLabel: NSTextField
    private let table = NSTableView()

    /// "1 photo will be exported" / "12 photos will be exported".
    nonisolated static func countText(for count: Int) -> String {
        count == 1 ? "1 photo will be exported" : "\(count) photos will be exported"
    }

    var countText: String { countLabel.stringValue }

    init(entries: [ExportSetupEntry], settings: ExportFormatAccessoryView) {
        self.entries = entries
        self.settings = settings
        countLabel = NSTextField(labelWithString: Self.countText(for: entries.count))
        super.init(frame: .zero)

        countLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        countLabel.setAccessibilityLabel("Photos to export")

        let column = NSTableColumn(identifier: .init("photo"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 36
        table.allowsEmptySelection = true
        table.selectionHighlightStyle = .none
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("Photos to export")

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        settings.translatesAutoresizingMaskIntoConstraints = false
        addSubview(countLabel)
        addSubview(scroll)
        addSubview(settings)
        let listHeight = CGFloat(min(max(entries.count, 1), 5)) * table.rowHeight + 4
        NSLayoutConstraint.activate([
            countLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            countLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            countLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            scroll.heightAnchor.constraint(equalToConstant: listHeight),
            settings.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 4),
            settings.leadingAnchor.constraint(equalTo: leadingAnchor),
            settings.trailingAnchor.constraint(equalTo: trailingAnchor),
            settings.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row) else { return nil }
        let entry = entries[row]
        let cell = tableView.makeView(withIdentifier: ExportSetupCell.identifier, owner: nil)
            as? ExportSetupCell ?? ExportSetupCell()
        cell.configure(with: entry)
        return cell
    }
}

/// A name plus a small thumbnail decoded only when the row is created, off the main actor, and
/// discarded if the cell was reused for another row in the meantime.
@MainActor
private final class ExportSetupCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("exportSetupCell")
    private let thumbnail = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var loadTask: Task<Void, Never>?
    private var token = UUID()

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbnail)
        addSubview(nameLabel)
        NSLayoutConstraint.activate([
            thumbnail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            thumbnail.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnail.widthAnchor.constraint(equalToConstant: 28),
            thumbnail.heightAnchor.constraint(equalToConstant: 28),
            nameLabel.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with entry: ExportSetupEntry) {
        loadTask?.cancel()
        let token = UUID()
        self.token = token
        nameLabel.stringValue = entry.name
        thumbnail.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        loadTask = Task { [weak self] in
            let image = await Self.decodeThumbnail(url: entry.url, data: entry.data)
            guard let self, !Task.isCancelled, self.token == token, let image else { return }
            self.thumbnail.image = NSImage(cgImage: image, size: .zero)
        }
    }

    /// A small embedded or downsampled preview; never decodes the full image.
    @concurrent private static func decodeThumbnail(url: URL?, data: Data?) async -> CGImage? {
        let source: CGImageSource?
        if let url {
            source = CGImageSourceCreateWithURL(url as CFURL, nil)
        } else if let data {
            source = CGImageSourceCreateWithData(data as CFData, nil)
        } else {
            source = nil
        }
        guard let source else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 96,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Step 2's only accessory: a Back button that dismisses the folder panel and tells the
/// coordinator to reopen Step 1 with the same settings. It carries no export settings.
@MainActor
final class ExportBackAccessoryView: NSView {
    private(set) var didRequestBack = false
    let backButton = NSButton(title: "Back", target: nil, action: nil)

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 36))
        backButton.target = self
        backButton.action = #selector(back)
        backButton.bezelStyle = .rounded
        backButton.setAccessibilityLabel("Back to export settings")
        backButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backButton)
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            backButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Also the test seam: marks the request, then closes the hosting panel if there is one.
    @objc func back() {
        didRequestBack = true
        (window as? NSSavePanel)?.cancel(nil)
    }
}
