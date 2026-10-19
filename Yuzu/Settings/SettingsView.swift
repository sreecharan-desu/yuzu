import SwiftUI

struct SettingsView: View {
    @AppStorage("settings.tab") private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralPane().tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            ShortcutsPane().tabItem { Label("Shortcuts", systemImage: "keyboard") }.tag("shortcuts")
            ConversionPane().tabItem { Label("Conversion", systemImage: "arrow.triangle.2.circlepath") }.tag("conversion")
            AboutPane().tabItem { Label("About", systemImage: "info.circle") }.tag("about")
        }
        .frame(width: 540, height: 400)
        .tint(Theme.accentDeep)
    }
}

private struct GeneralPane: View {
    @ObservedObject private var login = LoginItem.shared
    @AppStorage(Prefs.Key.sound) private var sound = true
    @AppStorage(Prefs.Key.haptics) private var haptics = true
    @AppStorage(Prefs.Key.reveal) private var reveal = false
    @AppStorage(Prefs.Key.hudPlacement) private var placement = "nearPointer"

    var body: some View {
        Form {
            Section {
                Toggle("Launch Yuzu at login", isOn: Binding(
                    get: { login.isEnabled },
                    set: { login.setEnabled($0) }))
                if login.needsApproval {
                    HStack {
                        Text("macOS needs your OK in Login Items.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { login.openLoginItemsSettings() }
                    }
                }
                if let err = login.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Feedback") {
                Toggle("Play a soft tick when an option highlights", isOn: $sound)
                Toggle("Trackpad haptics", isOn: $haptics)
            }
            Section("Results") {
                Toggle("Reveal finished files in Finder", isOn: $reveal)
                Picker("Show results", selection: $placement) {
                    Text("Near the pointer").tag("nearPointer")
                    Text("Top of the screen").tag("topCenter")
                }
                Text("Converted and edited copies are always saved next to the original. Originals are never changed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { login.refresh() }
    }
}

private struct ShortcutsPane: View {
    // Observed so the rows refresh when any combination changes (recorder, reset, or another window).
    @AppStorage(Prefs.Key.convertCombo) private var convert = ModifierCombo.shift.stored
    @AppStorage(Prefs.Key.toolsCombo) private var tools = ModifierCombo.command.stored
    @AppStorage(Prefs.Key.actionsCombo) private var actions = ModifierCombo.control.stored

    var body: some View {
        Form {
            Section {
                row(.convert, "Convert formats", "arrow.triangle.2.circlepath")
                row(.tools, "File tools", "wand.and.stars")
                row(.actions, "File actions", "square.grid.2x2")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Click a shortcut, then press and release the modifier keys you want. Esc cancels.")
                    Text("Start dragging a file, then tap the keys. The ring stays open until you drop.")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ kind: WheelKind, _ title: String, _ icon: String) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                ShortcutRecorder(kind: kind)
                Button {
                    Prefs.setCombo(kind.defaultCombo, for: kind)
                } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(.borderless)
                .help("Reset to \(kind.defaultCombo.label)")
                .disabled(Prefs.combo(for: kind) == kind.defaultCombo)
                .id("\(convert)-\(tools)-\(actions)")
            }
        } label: {
            Label(title, systemImage: icon)
        }
    }
}

/// Shared so only one recorder listens at a time; the debug hook drives it for screenshots.
@MainActor
final class RecorderState: ObservableObject {
    static let shared = RecorderState()
    @Published var recording: WheelKind?
    @Published var live: NSEvent.ModifierFlags = []
    @Published var message: (WheelKind, String)?
}

/// Records a modifier-only shortcut: the widest combination held is committed when every key is released.
struct ShortcutRecorder: View {
    let kind: WheelKind
    @ObservedObject private var state = RecorderState.shared
    @AppStorage private var stored: Int
    @State private var monitor: Any?
    @State private var peak: NSEvent.ModifierFlags = []

    init(kind: WheelKind) {
        self.kind = kind
        _stored = AppStorage(wrappedValue: kind.defaultCombo.stored, Prefs.comboKey(for: kind))
    }

    private var isRecording: Bool { state.recording == kind }
    private var current: ModifierCombo { ModifierCombo(stored: stored) ?? kind.defaultCombo }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    if isRecording {
                        Circle().fill(Theme.accentDeep).frame(width: 7, height: 7)
                        Text(state.live.isEmpty ? "Press keys…" : ModifierCombo(state.live).label)
                    } else {
                        Text(current.symbol).font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text(current.names)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).frame(minWidth: 150, minHeight: 26)
                .background(Capsule().fill(isRecording ? Theme.accent.opacity(0.22) : Color.primary.opacity(0.06)))
                .overlay(Capsule().strokeBorder(isRecording ? Theme.accentDeep : Color.primary.opacity(0.12), lineWidth: isRecording ? 1.5 : 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Shortcut for \(kind.title): \(current.names)")
            if let m = state.message, m.0 == kind {
                Text(m.1).font(.caption2).foregroundStyle(.red)
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggle() { isRecording ? stop() : start() }

    private func start() {
        state.recording = kind
        state.live = []
        state.message = nil
        peak = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { e in
            if e.type == .keyDown {
                if e.keyCode == 53 { stop() }   // Esc
                else { state.message = (kind, "Use modifier keys only: ⌃ ⌥ ⇧ ⌘") }
                return nil
            }
            let f = e.modifierFlags.intersection(ModifierCombo.allowed)
            state.live = f
            if f.isSuperset(of: peak) { peak = f }
            if f.isEmpty, !peak.isEmpty { commit(ModifierCombo(peak)) }
            return e
        }
    }

    private func commit(_ c: ModifierCombo) {
        if let clash = WheelKind.allCases.first(where: { $0 != kind && Prefs.combo(for: $0) == c }) {
            state.message = (kind, "\(c.symbol) already opens \(clash.title). Try another.")
            peak = []
            state.live = []
            return
        }
        stored = c.stored
        state.message = nil
        stop()
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if state.recording == kind { state.recording = nil; state.live = [] }
    }
}

private struct ConversionPane: View {
    @AppStorage(Prefs.Key.lossyQuality) private var quality = 0.85
    @AppStorage(Prefs.Key.compressQuality) private var compress = 0.6
    @AppStorage(Prefs.Key.preserveMetadata) private var metadata = true

    var body: some View {
        Form {
            Section("Images") {
                LabeledContent("JPG, HEIC, WebP quality") {
                    HStack { Slider(value: $quality, in: 0.4...1.0); Text("\(Int(quality * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing) }
                }
                LabeledContent("Compress strength") {
                    HStack { Slider(value: $compress, in: 0.2...0.9); Text("\(Int(compress * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing) }
                }
                Toggle("Keep metadata when converting", isOn: $metadata)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutPane: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
            Text("Yuzu").font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .foregroundStyle(.secondary)
            Text("Convert, edit and act on files right at your pointer. Everything runs on this Mac.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 360)
            Divider().frame(width: 360)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(ToolLocator.all) { t in
                    GridRow {
                        Image(systemName: t.path == nil ? "xmark.circle" : "checkmark.circle.fill")
                            .foregroundStyle(t.path == nil ? Color.secondary : Theme.accentDeep)
                        Text(t.id).fontWeight(.medium)
                        Text(t.path == nil ? "not found" : t.use).foregroundStyle(.secondary)
                    }
                }
            }
            .font(.callout)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
