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
            .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1).frame(width: diameter, height: diameter))
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
                                  tint: scheme == .dark ? Color.black.opacity(0.38) : Color.white.opacity(0.30))
                } else {
                    Circle()
                        .fill(Color.white.opacity(scheme == .dark ? 0.02 : 0.06))
                        .frame(width: Theme.wheelDiameter, height: Theme.wheelDiameter)
                        .glassEffect(.regular, in: Circle())
                }
            }
                .shadow(color: .black.opacity(0.16), radius: 26, x: 0, y: 14)
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
                .offset(y: Theme.wheelDiameter / 2 + 16)
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
            shape.stroke(Color.white.opacity(isHovered ? 0.55 : (dark ? 0.10 : 0.45)), lineWidth: 0.8)
            if let option {
                label(option, dark: dark)
                    .offset(x: labelR * CGFloat(cos(mid)), y: labelR * CGFloat(sin(mid)))
            }
        }
        .frame(width: Theme.canvas, height: Theme.canvas)
        .scaleEffect(isOpen ? (isHovered ? 1.045 : 1) : 0.62)
        .opacity(isOpen ? 1 : 0)
        .animation(isHovered ? Theme.hover : nil, value: isHovered)
        .animation(isOpen ? Theme.petalBloom.delay(Double(index) * 0.018) : Theme.close, value: isOpen)
        .shadow(color: isHovered ? Theme.accentDeep.opacity(0.35) : .clear, radius: 12, y: 4)
    }

    private func fill(dark: Bool, enabled: Bool) -> AnyShapeStyle {
        if isHovered {
            return AnyShapeStyle(LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                                                startPoint: .top, endPoint: .bottom))
        }
        if option == nil { return AnyShapeStyle(Color.white.opacity(dark ? 0.04 : 0.22)) }
        if dark { return AnyShapeStyle(Color.white.opacity(enabled ? 0.14 : 0.06)) }
        return AnyShapeStyle(Color(red: 1.0, green: 0.96, blue: 0.90).opacity(enabled ? 0.74 : 0.36))
    }

    @ViewBuilder
    private func label(_ o: WheelOption, dark: Bool) -> some View {
        let color: Color = isHovered ? Theme.ink : (dark ? .white : Theme.ink)
        VStack(spacing: 4) {
            if let s = o.symbol {
                Image(systemName: s).font(.system(size: 17, weight: .semibold))
                Text(o.title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text(o.title).font(.system(size: 17, weight: .bold, design: .rounded))
            }
            if let note = o.note {
                Text(note).font(.system(size: 8.5, weight: .semibold)).opacity(0.7)
            }
        }
        .foregroundStyle(color.opacity(o.enabled ? 1 : 0.4))
        .frame(width: 86)
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
                              tint: scheme == .dark ? Color.black.opacity(0.5) : Color.white.opacity(0.45))
            } else {
                Circle()
                    .fill(Color.black.opacity(scheme == .dark ? 0.18 : 0.05))
                    .frame(width: d, height: d)
                    .glassEffect(.regular, in: Circle())
            }
            VStack(spacing: 5) {
                if let img = model.thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
                }
                Text(caption)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.12), value: caption)
            }
            .frame(width: d - 16)
        }
    }

    private var caption: String {
        if let o = model.hoveredOption {
            switch o.action {
            case .convertImage(let f): return "→ \(f.title)"
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
        HStack(spacing: 5) {
            Text(Prefs.combo(for: kind).symbol).font(.system(size: 11, weight: .bold))
            Text(kind.title.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.8)
        }
        .foregroundStyle(.primary.opacity(0.75))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(0.10)))
        .glassEffect(.regular, in: Capsule())
        .opacity(isOpen ? 1 : 0)
        .offset(y: isOpen ? 0 : 10)
        .animation(isOpen ? Theme.bloom.delay(0.08) : Theme.close, value: isOpen)
    }
}
