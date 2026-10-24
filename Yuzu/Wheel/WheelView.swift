import SwiftUI

struct WheelView: View {
    @ObservedObject var model: WheelModel

    var body: some View {
        if let scheme = model.snapshotScheme {
            WheelContent(model: model).environment(\.colorScheme, scheme)
        } else {
            WheelContent(model: model)
        }
    }
}

/// Stand-in for Liquid Glass in self-rendered snapshots, which cannot capture the window-server backdrop.
struct SnapshotGlass: View {
    let backdrop: NSImage
    let diameter: CGFloat
    let tint: Color

    var body: some View {
        Image(nsImage: backdrop).resizable().aspectRatio(contentMode: .fill)
            .frame(width: Theme.canvas, height: Theme.canvas)
            .blur(radius: 22)
            .overlay(tint)
            .mask(Circle().frame(width: diameter, height: diameter))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1).frame(width: diameter, height: diameter))
            .frame(width: Theme.canvas, height: Theme.canvas)
    }
}

private struct WheelContent: View {
    @ObservedObject var model: WheelModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let slots = model.slots
        ZStack {
            if let bd = model.snapshotBackdrop {
                Image(nsImage: bd).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: Theme.canvas, height: Theme.canvas).clipped()
            }
            // Glass ring behind the petals.
            Group {
                if let bd = model.snapshotBackdrop {
                    SnapshotGlass(backdrop: bd, diameter: Theme.wheelDiameter,
                                  tint: scheme == .dark ? Color(hex: 0x1D1D1F, opacity: 0.55) : Color.white.opacity(0.52))
                } else {
                    Circle()
                        .fill(scheme == .dark ? Color(hex: 0x1D1D1F, opacity: 0.30) : Color.white.opacity(0.30))
                        .frame(width: Theme.wheelDiameter, height: Theme.wheelDiameter)
                        .yuzuGlass(in: Circle())
                }
            }
                .shadow(Theme.Shadows.float)
                .scaleEffect(model.isOpen ? 1 : 0.5)
                .opacity(model.isOpen ? 1 : 0)
                .animation(model.isOpen ? Theme.bloom : Theme.close, value: model.isOpen)

            ForEach(0..<slots, id: \.self) { i in
                PetalView(index: i, slots: slots,
                          option: i < model.options.count ? model.options[i] : nil,
                          isHovered: model.hoverIndex == i && i < model.options.count && model.options[i].enabled,
                          isOpen: model.isOpen,
                          kind: model.kind)
            }

            HubView(model: model, backdrop: model.snapshotBackdrop)
                .scaleEffect(model.isOpen ? 1 : 0.3)
                .opacity(model.isOpen ? 1 : 0)
                .animation(model.isOpen ? Theme.bloom.delay(0.03) : Theme.close, value: model.isOpen)

            ModeChip(kind: model.kind, isOpen: model.isOpen)
                .offset(y: Theme.wheelDiameter / 2 + Theme.Space.l)
        }
        .frame(width: Theme.canvas, height: Theme.canvas)
    }
}

private struct PetalView: View {
    let index: Int
    let slots: Int
    let option: WheelOption?
    let isHovered: Bool
    let isOpen: Bool
    let kind: WheelKind
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let step = WheelGeometry.step(slots)
        let mid = WheelGeometry.midAngle(index, slots)
        let shape = PetalShape(startAngle: mid - step / 2, endAngle: mid + step / 2,
                               innerRadius: Theme.innerRadius, outerRadius: Theme.outerRadius)
        let labelR = (Theme.innerRadius + Theme.outerRadius) / 2 + 3
        let dark = scheme == .dark
        let enabled = option?.enabled ?? false

        ZStack {
            shape.fill(fill(dark: dark, enabled: enabled))
            shape.stroke(isHovered ? Color.clear : (dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)), lineWidth: 1)
            if let option {
                label(option, dark: dark)
                    .offset(x: labelR * CGFloat(cos(mid)), y: labelR * CGFloat(sin(mid)))
            }
        }
        .frame(width: Theme.canvas, height: Theme.canvas)
        .scaleEffect(isOpen ? (isHovered ? 1.03 : 1) : 0.62)
        .opacity(isOpen ? 1 : 0)
        .animation(Theme.hover, value: isHovered)
        .animation(isOpen ? Theme.petalBloom.delay(Double(index) * 0.016) : Theme.close, value: isOpen)
        .shadow(color: isHovered ? .black.opacity(dark ? 0.4 : 0.18) : .clear, radius: 12, y: 6)
    }

    /// Neutral petals; the hovered one becomes solid ink (pearl in dark mode). No colour fills.
    private func fill(dark: Bool, enabled: Bool) -> AnyShapeStyle {
        if isHovered { return AnyShapeStyle(Theme.ink) }
        if option == nil { return AnyShapeStyle(dark ? Color.white.opacity(0.03) : Color.white.opacity(0.24)) }
        if dark { return AnyShapeStyle(Color.white.opacity(enabled ? 0.11 : 0.05)) }
        return AnyShapeStyle(Color.white.opacity(enabled ? 0.72 : 0.34))
    }

    @ViewBuilder
    private func label(_ o: WheelOption, dark: Bool) -> some View {
        let color: Color = isHovered ? Theme.onInk : Theme.ink
        VStack(spacing: Theme.Space.half) {
            if let s = o.symbol {
                Image(systemName: s).font(.system(size: 16, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(isHovered ? Theme.yuzu : color)
                Text(o.title)
                    .font(.system(size: 11, weight: .medium)).tracking(-0.1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } else {
                Text(o.title).font(.system(size: 16, weight: .medium)).tracking(-0.3)
            }
            if let note = o.note {
                Text(note).font(.system(size: 9, weight: .regular)).opacity(0.6)
            }
        }
        .foregroundStyle(color.opacity(o.enabled ? 1 : 0.35))
        .frame(width: 88)
    }
}

private struct HubView: View {
    @ObservedObject var model: WheelModel
    var backdrop: NSImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let d = Theme.hubDiameter
        ZStack {
            if let backdrop {
                SnapshotGlass(backdrop: backdrop, diameter: d,
                              tint: scheme == .dark ? Color(hex: 0x1D1D1F, opacity: 0.62) : Color.white.opacity(0.62))
            } else {
                Circle()
                    .fill(scheme == .dark ? Color(hex: 0x1D1D1F, opacity: 0.4) : Color.white.opacity(0.4))
                    .frame(width: d, height: d)
                    .yuzuGlass(in: Circle())
            }
            VStack(spacing: Theme.Space.s) {
                if let img = model.thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control - 4, style: .continuous))
                        .shadow(Theme.Shadows.soft)
                }
                Text(caption)
                    .font(.system(size: 11, weight: .medium)).tracking(-0.05)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, Theme.Space.s)
                    .frame(height: 20)
                    .background(Capsule().fill(Theme.ink.opacity(0.06)))
                    .yuzuOpacityTransition()
                    .animation(Theme.Motion.color, value: caption)
            }
            .frame(width: d - Theme.Space.m)
        }
    }

    private var caption: String {
        if let o = model.hoveredOption {
            switch o.action {
            case .convertImage(let f): return "To \(f.title)"
            default: return o.title
            }
        }
        if let m = model.message, model.options.isEmpty { return m }
        return model.sizeText.isEmpty ? "Drop here" : model.sizeText
    }
}

private struct ModeChip: View {
    let kind: WheelKind
    let isOpen: Bool

    var body: some View {
        HStack(spacing: Theme.Space.half + 2) {
            Text(Prefs.combo(for: kind).symbol).font(.system(size: 11, weight: .medium))
            Text(kind.title).font(.system(size: 11, weight: .medium)).tracking(-0.05)
        }
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, Theme.Space.m - 4)
        .frame(height: 24)
        .yuzuGlass(in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        .opacity(isOpen ? 1 : 0)
        .offset(y: isOpen ? 0 : 8)
        .blur(radius: isOpen ? 0 : 6)
        .animation(isOpen ? Theme.Motion.enter(0.5).delay(0.08) : Theme.close, value: isOpen)
    }
}
