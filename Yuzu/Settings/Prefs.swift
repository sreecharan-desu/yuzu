import AppKit

enum Prefs {
    enum Key {
        static let convertCombo = "wheel.convert.modifiers"
        static let toolsCombo = "wheel.tools.modifiers"
        static let actionsCombo = "wheel.actions.modifiers"
        static let sound = "feedback.sound"
        static let haptics = "feedback.haptics"
        static let reveal = "results.revealInFinder"
        static let lossyQuality = "convert.lossyQuality"
        static let compressQuality = "tools.compressQuality"
        static let preserveMetadata = "convert.preserveMetadata"
        static let hudPlacement = "hud.placement"
    }

    static let d = UserDefaults.standard

    static func registerDefaults() {
        d.register(defaults: [
            Key.convertCombo: ModifierCombo.shift.stored,
            Key.toolsCombo: ModifierCombo.command.stored,
            Key.actionsCombo: ModifierCombo.control.stored,
            Key.sound: true,
            Key.haptics: true,
            Key.reveal: false,
            Key.lossyQuality: 0.85,
            Key.compressQuality: 0.6,
            Key.preserveMetadata: true,
            Key.hudPlacement: "nearPointer",
        ])
    }

    static func comboKey(for kind: WheelKind) -> String {
        switch kind {
        case .convert: return Key.convertCombo
        case .tools: return Key.toolsCombo
        case .actions: return Key.actionsCombo
        }
    }

    static func combo(for kind: WheelKind) -> ModifierCombo {
        ModifierCombo(stored: d.integer(forKey: comboKey(for: kind))) ?? kind.defaultCombo
    }

    static func setCombo(_ c: ModifierCombo, for kind: WheelKind) { d.set(c.stored, forKey: comboKey(for: kind)) }

    static var sound: Bool { d.bool(forKey: Key.sound) }
    static var haptics: Bool { d.bool(forKey: Key.haptics) }
    static var reveal: Bool { d.bool(forKey: Key.reveal) }
    static var lossyQuality: Double { d.double(forKey: Key.lossyQuality) }
    static var compressQuality: Double { d.double(forKey: Key.compressQuality) }
    static var preserveMetadata: Bool { d.bool(forKey: Key.preserveMetadata) }
}

enum WheelKind: String, CaseIterable, Sendable {
    case convert, tools, actions

    var title: String {
        switch self {
        case .convert: return "Convert"
        case .tools: return "Tools"
        case .actions: return "Actions"
        }
    }

    var defaultCombo: ModifierCombo {
        switch self {
        case .convert: return .shift
        case .tools: return .command
        case .actions: return .control
        }
    }
}

/// A modifier combination tapped during a drag (any mix of Control, Option, Shift and Command).
/// Stored as the NSEvent flag mask. Builds before 1.0 stored a picker index 0...6, which still reads correctly.
struct ModifierCombo: Hashable, Identifiable, Sendable {
    static let allowed: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    let flags: NSEvent.ModifierFlags

    init(_ flags: NSEvent.ModifierFlags) { self.flags = flags.intersection(Self.allowed) }

    private static let legacy: [NSEvent.ModifierFlags] = [
        [.shift], [.command], [.control], [.option], [.shift, .option], [.shift, .command], [.control, .option],
    ]

    init?(stored: Int) {
        if (0..<Self.legacy.count).contains(stored) { self.init(Self.legacy[stored]); return }
        let f = NSEvent.ModifierFlags(rawValue: UInt(max(stored, 0))).intersection(Self.allowed)
        guard !f.isEmpty else { return nil }
        self.init(f)
    }

    var stored: Int { Int(flags.rawValue) }
    static func == (a: ModifierCombo, b: ModifierCombo) -> Bool { a.flags.rawValue == b.flags.rawValue }
    func hash(into h: inout Hasher) { h.combine(flags.rawValue) }
    var id: Int { stored }
    var isEmpty: Bool { flags.isEmpty }

    static let shift = ModifierCombo([.shift])
    static let command = ModifierCombo([.command])
    static let control = ModifierCombo([.control])
    static let option = ModifierCombo([.option])

    /// Keys in Apple's canonical order.
    private var parts: [(symbol: String, name: String)] {
        var out: [(String, String)] = []
        if flags.contains(.control) { out.append(("⌃", "Control")) }
        if flags.contains(.option) { out.append(("⌥", "Option")) }
        if flags.contains(.shift) { out.append(("⇧", "Shift")) }
        if flags.contains(.command) { out.append(("⌘", "Command")) }
        return out
    }

    var symbol: String { parts.map(\.symbol).joined() }
    var names: String { parts.map(\.name).joined(separator: " + ") }
    var label: String { "\(symbol) \(names)" }
}
