import AppKit
import QuickLookThumbnailing

/// Quick Look thumbnails keyed by path, size and modification date. The ring, the Float shelf and the
/// tool panels ask for the same files over and over; a hit returns synchronously with no Quick Look round trip.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    private var waiting: [NSString: [(NSImage) -> Void]] = [:]
    private(set) var hits = 0
    private(set) var misses = 0

    private init() { cache.countLimit = 160 }

    private func key(_ url: URL, _ side: CGFloat) -> NSString {
        let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(Int(side))|\(Int(m))" as NSString
    }

    /// The cached thumbnail, if any.
    func cached(_ url: URL, side: CGFloat) -> NSImage? { cache.object(forKey: key(url, side)) }

    /// Calls `done` on the main thread with a thumbnail, immediately when cached.
    func thumbnail(for url: URL, side: CGFloat, done: @escaping (NSImage) -> Void) {
        let k = key(url, side)
        if let img = cache.object(forKey: k) { hits += 1; done(img); return }
        misses += 1
        if waiting[k] != nil { waiting[k]!.append(done); return }
        waiting[k] = [done]
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side),
                                               scale: NSScreen.main?.backingScaleFactor ?? 2,
                                               representationTypes: .thumbnail)
        let ks = k as String
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            let img = rep?.nsImage
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let k = ks as NSString
                    let cbs = self.waiting.removeValue(forKey: k) ?? []
                    guard let img else { return }
                    self.cache.setObject(img, forKey: k)
                    cbs.forEach { $0(img) }
                }
            }
        }
    }
}
