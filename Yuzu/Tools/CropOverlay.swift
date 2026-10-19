import SwiftUI

/// Crop rectangle editor in normalized coordinates over a fitted image rect.
struct CropOverlay: View {
    @Binding var rect: CGRect
    let frame: CGRect
    /// Width/height in normalized units (pixel ratio × image height / width), nil for free.
    let aspect: CGFloat?
    @State private var start: CGRect?

    var body: some View {
        let r = frame.denormalize(rect)
        ZStack(alignment: .topLeading) {
            Path { p in p.addRect(frame); p.addRect(r) }
                .fill(Color.black.opacity(0.52), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
            Path { p in
                for i in 1...2 {
                    let x = r.minX + r.width * CGFloat(i) / 3, y = r.minY + r.height * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY))
                    p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y))
                }
            }
            .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
            .allowsHitTesting(false)
            Rectangle()
                .strokeBorder(Color.white, lineWidth: 1.5)
                .background(Color.white.opacity(0.001))
                .frame(width: max(r.width, 1), height: max(r.height, 1))
                .offset(x: r.minX, y: r.minY)
                .gesture(DragGesture().onChanged { v in
                    if start == nil { start = rect }
                    guard let s = start else { return }
                    var n = s.offsetBy(dx: v.translation.width / frame.width, dy: v.translation.height / frame.height)
                    n.origin.x = min(max(n.minX, 0), 1 - n.width)
                    n.origin.y = min(max(n.minY, 0), 1 - n.height)
                    rect = n
                }.onEnded { _ in start = nil })
            ForEach(0..<4, id: \.self) { corner in
                let p = CGPoint(x: corner % 2 == 0 ? r.minX : r.maxX, y: corner < 2 ? r.minY : r.maxY)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.35), radius: 2)
                    .position(p)
                    .gesture(DragGesture().onChanged { v in
                        if start == nil { start = rect }
                        guard let s = start else { return }
                        rect = Self.resize(s, corner: corner, dx: v.translation.width / frame.width,
                                           dy: v.translation.height / frame.height, aspect: aspect)
                    }.onEnded { _ in start = nil })
            }
        }
    }

    static func resize(_ s: CGRect, corner: Int, dx: CGFloat, dy: CGFloat, aspect: CGFloat?) -> CGRect {
        let fixed = CGPoint(x: corner % 2 == 0 ? s.maxX : s.minX, y: corner < 2 ? s.maxY : s.minY)
        var moving = CGPoint(x: (corner % 2 == 0 ? s.minX : s.maxX) + dx, y: (corner < 2 ? s.minY : s.maxY) + dy)
        moving.x = min(max(moving.x, 0), 1); moving.y = min(max(moving.y, 0), 1)
        var w = max(abs(moving.x - fixed.x), 0.02), h = max(abs(moving.y - fixed.y), 0.02)
        if let a = aspect {
            if w / h > a { w = h * a } else { h = w / a }
        }
        let x = moving.x < fixed.x ? fixed.x - w : fixed.x
        let y = moving.y < fixed.y ? fixed.y - h : fixed.y
        var r = CGRect(x: x, y: y, width: w, height: h)
        r = r.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        return r
    }

    /// Largest centered rect with the given pixel aspect inside the image.
    static func fitted(aspect pixelRatio: CGFloat?, imageSize: CGSize) -> CGRect {
        guard let pr = pixelRatio, imageSize.width > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let n = pr * imageSize.height / imageSize.width
        var w: CGFloat = 1, h: CGFloat = 1
        if n > 1 { h = 1 / n } else { w = n }
        return CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
    }
}

enum AspectPreset: String, CaseIterable, Identifiable {
    case free = "Free", original = "Original", square = "1:1", fourThree = "4:3", threeTwo = "3:2", wide = "16:9", tall = "9:16"
    var id: String { rawValue }
    func ratio(original: CGSize) -> CGFloat? {
        switch self {
        case .free: return nil
        case .original: return original.height > 0 ? original.width / original.height : nil
        case .square: return 1
        case .fourThree: return 4.0 / 3
        case .threeTwo: return 3.0 / 2
        case .wide: return 16.0 / 9
        case .tall: return 9.0 / 16
        }
    }
}
