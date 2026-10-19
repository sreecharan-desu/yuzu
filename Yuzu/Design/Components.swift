import SwiftUI

// MARK: Typography

extension View {
    /// Applies a type role from the scale: size, weight and tracking together.
    func type(_ role: Theme.TypeRole) -> some View {
        font(role.font).tracking(role.size * role.trackingEm)
    }

    func shadow(_ s: Theme.Shadow) -> some View { shadow(color: s.color, radius: s.radius, x: 0, y: s.y) }
}

/// Short line with one italic emphasis word, e.g. EmphasisText("Drop it ", "anywhere", ".").
struct EmphasisText: View {
    let lead: String, emphasis: String, trail: String
    init(_ lead: String, _ emphasis: String, _ trail: String = "") { self.lead = lead; self.emphasis = emphasis; self.trail = trail }
    var body: some View { Text("\(lead)\(Text(emphasis).italic())\(trail)") }
}

// MARK: Surfaces

/// Neutral card: step-100 fill (or untinted glass), large radius, hairline border.
struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.Radius.card
    var glass = false
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                if glass { shape.fill(Color.clear).glassEffect(.regular, in: shape) } else { shape.fill(Theme.step100) }
            }
            .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
    }
}

extension View {
    func card(radius: CGFloat = Theme.Radius.card, glass: Bool = false) -> some View {
        modifier(CardBackground(radius: radius, glass: glass))
    }
}

// MARK: Buttons

/// Primary: flat ink pill. Hover settles to 1.02 over ~2.4 s with a slow diagonal glare; press returns to 1.
struct InkPillButtonStyle: ButtonStyle {
    var height: CGFloat = 36
    func makeBody(configuration: Configuration) -> some View { InkPill(configuration: configuration, height: height) }

    private struct InkPill: View {
        let configuration: ButtonStyleConfiguration
        let height: CGFloat
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .type(.headline).font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.onInk)
                .padding(.horizontal, Theme.Space.l)
                .frame(height: height)
                .background(Capsule().fill(Theme.ink.opacity(configuration.isPressed ? 0.86 : 1)))
                .overlay(GlareSweep(active: hover && !reduceMotion).clipShape(Capsule()))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5).blendMode(.plusLighter))
                .scaleEffect(configuration.isPressed ? 1 : (hover && !reduceMotion ? 1.02 : 1))
                .animation(configuration.isPressed ? Theme.Motion.house(0.2) : (hover ? Theme.Motion.pop : Theme.Motion.popOut), value: hover)
                .animation(Theme.Motion.house(0.2), value: configuration.isPressed)
                .opacity(enabled ? 1 : 0.35)
                .contentShape(Capsule())
                .onHover { hover = $0 }
        }
    }
}

/// Secondary: pale pill on step-200 with a hairline; quiet hover (fill brightens over 0.3 s, no hue change).
struct QuietPillButtonStyle: ButtonStyle {
    var height: CGFloat = 36
    func makeBody(configuration: Configuration) -> some View { Quiet(configuration: configuration, height: height) }
    private struct Quiet: View {
        let configuration: ButtonStyleConfiguration
        let height: CGFloat
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium)).tracking(-0.1)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, Theme.Space.m + Theme.Space.half)
                .frame(height: height)
                .background(Capsule().fill(hover ? Theme.step100 : Theme.step200))
                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                .scaleEffect(configuration.isPressed ? 0.99 : 1)
                .animation(Theme.Motion.chrome, value: hover)
                .animation(Theme.Motion.house(0.2), value: configuration.isPressed)
                .opacity(enabled ? 1 : 0.35)
                .contentShape(Capsule())
                .onHover { hover = $0 }
        }
    }
}

/// Icon-only quiet button: 28 pt round, hairline, lifts 1 pt on hover.
struct QuietIconButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    func makeBody(configuration: Configuration) -> some View { Icon(configuration: configuration, size: size) }
    private struct Icon: View {
        let configuration: ButtonStyleConfiguration
        let size: CGFloat
        @State private var hover = false
        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hover ? Theme.ink : Theme.inkSoft)
                .frame(width: size, height: size)
                .background(Circle().fill(hover ? Theme.step200 : Theme.step100))
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                .offset(y: hover && !configuration.isPressed ? -1 : 0)
                .animation(Theme.Motion.chrome, value: hover)
                .contentShape(Circle())
                .onHover { hover = $0 }
        }
    }
}

/// Selectable chip used by every segmented picker: ink when selected, step-200 otherwise.
struct Chip: View {
    let title: String
    var symbol: String? = nil
    let selected: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.half + 2) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .medium)) }
                Text(title).font(.system(size: 12, weight: .medium)).tracking(-0.05).lineLimit(1)
            }
            .foregroundStyle(selected ? Theme.onInk : Theme.ink)
            .padding(.horizontal, Theme.Space.m - 4)
            .frame(height: 28)
            .background(Capsule().fill(selected ? Theme.ink : (hover ? Theme.step100 : Theme.step200)))
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Theme.Motion.color, value: selected)
        .animation(Theme.Motion.chrome, value: hover)
    }
}

/// Slow specular sweep, ~2 s, for primary pills.
struct GlareSweep: View {
    let active: Bool
    var body: some View {
        GeometryReader { g in
            LinearGradient(stops: [
                .init(color: .white.opacity(0), location: 0.38), .init(color: .white.opacity(0.07), location: 0.52),
                .init(color: .white.opacity(0.22), location: 0.61), .init(color: .white.opacity(0.07), location: 0.70),
                .init(color: .white.opacity(0), location: 0.84)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: g.size.width * 3, height: g.size.height * 3)
                .offset(x: active ? 0 : -g.size.width * 2, y: active ? -g.size.height : -g.size.height * 2)
                .animation(active ? Theme.Motion.glare : .easeOut(duration: 0.4), value: active)
                .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }
}

// MARK: Materialize (blur + rise to sharp)

struct Materialize: ViewModifier {
    var delay: Double = 0
    var rise: CGFloat = 18
    var blur: CGFloat = 12
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown || reduceMotion ? 0 : blur)
            .offset(y: shown || reduceMotion ? 0 : rise)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.materialize.delay(delay)) { shown = true }
            }
    }
}

extension View {
    /// Content arrives by sharpening out of a soft blur while rising a few points (~1 s, enter ease).
    func materialize(_ index: Int = 0, rise: CGFloat = 18, blur: CGFloat = 12) -> some View {
        modifier(Materialize(delay: Double(index) * 0.09, rise: rise, blur: blur))
    }
}

/// Privacy line: blue lead-in, then ink.
struct TrustLine: View {
    let lead: String, rest: String
    var body: some View {
        Text("\(Text(lead).foregroundStyle(Theme.trust)) \(Text(rest).foregroundStyle(Theme.inkSoft))")
            .type(.callout)
    }
}
