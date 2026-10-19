import AppKit
import Combine
import QuickLookThumbnailing
import SwiftUI

@MainActor
final class WheelModel: ObservableObject {
    @Published var kind: WheelKind = .convert
    @Published var options: [WheelOption] = []
    @Published var message: String?
    @Published var hoverIndex: Int?
    @Published var isOpen = false
    @Published var items: [URL] = []
    @Published var thumbnail: NSImage?
    @Published var sizeText: String = ""
    /// Only for self-rendered snapshots: a wallpaper drawn behind the ring, and a forced appearance.
    @Published var snapshotBackdrop: NSImage?
    @Published var snapshotScheme: ColorScheme?

    var slots: Int { max(Theme.minSlots, min(Theme.maxPetals, options.count)) }

    var hoveredOption: WheelOption? {
        guard let i = hoverIndex, i < options.count, options[i].enabled else { return nil }
        return options[i]
    }

    func load(kind: WheelKind, items: [URL]) {
        self.kind = kind
        let sameItems = items == self.items
        self.items = items
        let result = Catalog.options(for: kind, items: items)
        options = result.options
        message = result.message
        hoverIndex = nil
        if !sameItems { loadThumbnail() }
    }

    private func loadThumbnail() {
        thumbnail = nil
        sizeText = ""
        guard let first = items.first else { return }
        thumbnail = ThumbnailCache.shared.cached(first, side: 96) ?? NSWorkspace.shared.icon(forFile: first.path)
        var total: Int64 = 0
        for u in items {
            if let s = try? u.resourceValues(forKeys: [.totalFileSizeKey, .fileSizeKey]) {
                total += Int64(s.totalFileSize ?? s.fileSize ?? 0)
            }
        }
        let size = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        sizeText = items.count > 1 ? "\(items.count) files · \(size)" : size

        let expected = first
        // Cached thumbnails land synchronously, so a repeat tap on the same file opens with its preview.
        ThumbnailCache.shared.thumbnail(for: first, side: 96) { [weak self] img in
            if self?.items.first == expected { self?.thumbnail = img }
        }
    }
}
