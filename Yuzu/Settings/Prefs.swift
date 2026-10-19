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
            Key.convertCombo: ModifierCombo.shift.rawValue,
            Key.toolsCombo: ModifierCombo.command.rawValue,
            Key.actionsCombo: ModifierCombo.control.rawValue,
            Key.sound: true,
            Key.haptics: true,
            Key.reveal: false,
            Key.lossyQuality: 0.85,
            Key.compressQuality: 0.6,
            Key.preserveMetadata: true,
            Key.hudPlacement: "nearPointer",
        ])
    }

    static func combo(for kind: WheelKind) -> ModifierCombo {
        let key: String
        switch kind {
        case .convert: key = Key.convertCombo
        case .tools: key = Key.toolsCombo
        case .actions: key = Key.actionsCombo
        }
        return ModifierCombo(rawValue: d.integer(forKey: key)) ?? kind.defaultCombo
    }

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

/// A modifier combination tapped during a drag. Raw value is the NSEvent flag mask.
enum ModifierCombo: Int, CaseIterable, Identifiable, Sendable {
    case shift, command, control, option, shiftOption, shiftCommand, controlOption

    var id: Int { rawValue }

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .shift: return [.shift]
        case .command: return [.command]
        case .control: return [.control]
        case .option: return [.option]
        case .shiftOption: return [.shift, .option]
        case .shiftCommand: return [.shift, .command]
        case .controlOption: return [.control, .option]
        }
    }

    var label: String {
        switch self {
        case .shift: return "⇧ Shift"
        case .command: return "⌘ Command"
        case .control: return "⌃ Control"
        case .option: return "⌥ Option"
        case .shiftOption: return "⌥⇧ Option + Shift"
        case .shiftCommand: return "⇧⌘ Shift + Command"
        case .controlOption: return "⌃⌥ Control + Option"
        }
    }

    var symbol: String {
        switch self {
        case .shift: return "⇧"
        case .command: return "⌘"
        case .control: return "⌃"
        case .option: return "⌥"
        case .shiftOption: return "⌥⇧"
        case .shiftCommand: return "⇧⌘"
        case .controlOption: return "⌃⌥"
        }
    }
}
