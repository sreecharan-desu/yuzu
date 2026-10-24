import Combine
import SwiftUI

// MARK: Glass

extension View {
    /// Liquid Glass on macOS 26. Untinted material on macOS 12–25.
    func yuzuGlass<S: Shape>(in shape: S) -> some View {
        modifier(YuzuGlassModifier(shape: shape))
    }
}

extension Shape {
    /// A glass-filled shape: Liquid Glass on macOS 26, material below that.
    @ViewBuilder
    func yuzuGlassFill() -> some View {
        if #available(macOS 26, *) {
            self.fill(Color.clear).glassEffect(.regular, in: self)
        } else {
            self.fill(.ultraThinMaterial)
        }
    }
}

private struct YuzuGlassModifier<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background { shape.fill(.ultraThinMaterial) }
        }
    }
}

// MARK: Transitions and observation

extension View {
    /// Numeric text morph on macOS 14+. No-op on earlier systems (the value still updates).
    @ViewBuilder
    func yuzuNumericTransition() -> some View {
        if #available(macOS 14, *) {
            self.contentTransition(.numericText())
        } else {
            self
        }
    }

    /// Opacity content transition on macOS 14+. No-op earlier.
    @ViewBuilder
    func yuzuOpacityTransition() -> some View {
        if #available(macOS 14, *) {
            self.contentTransition(.opacity)
        } else {
            self
        }
    }

    /// Grouped form on macOS 13+. The default form style on earlier systems.
    @ViewBuilder
    func yuzuGroupedForm() -> some View {
        if #available(macOS 13, *) {
            self.formStyle(.grouped)
        } else {
            self
        }
    }

    /// Fires when `value` changes. Skips the initial value, matching `onChange`.
    func whenChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        modifier(WhenChange(value: value, action: action))
    }
}

private struct WhenChange<V: Equatable>: ViewModifier {
    let value: V
    let action: (V) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.onChange(of: value) { _, new in action(new) }
        } else {
            content.background(LegacyChange(value: value, action: action))
        }
    }
}

/// Change detection without the macOS 14 `onChange` overload, for macOS 12 and 13.
private struct LegacyChange<V: Equatable>: View {
    let value: V
    let action: (V) -> Void
    @State private var last: V?
    @State private var primed = false

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                if !primed { last = value; primed = true }
            }
            .onReceive(Just(value)) { new in
                guard primed else { return }
                guard last != new else { return }
                last = new
                action(new)
            }
    }
}
