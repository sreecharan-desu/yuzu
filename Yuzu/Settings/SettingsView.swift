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
        .tint(Theme.ink)
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
                    .disabled(!LoginItem.isSupported)
                if !LoginItem.isSupported {
                    Text("Requires macOS 13 or later.").font(.caption).foregroundStyle(.secondary)
                }
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
        .yuzuGroupedForm()
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
        .yuzuGroupedForm()
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
                HStack(spacing: Theme.Space.s) {
                    if isRecording {
                        Circle().fill(Theme.yuzu).frame(width: 8, height: 8)
                        Text(state.live.isEmpty ? "Press keys…" : ModifierCombo(state.live).label)
                    } else {
                        Text(current.symbol).font(.system(size: 13, weight: .medium))
                        Text(current.names)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, Theme.Space.m - 4).frame(minWidth: 152, minHeight: 28)
                .background(Capsule().fill(isRecording ? Theme.surface : Theme.step200))
                .overlay(Capsule().strokeBorder(isRecording ? Theme.ink : Theme.line, lineWidth: isRecording ? 1.5 : 1))
                .animation(Theme.Motion.chrome, value: isRecording)
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
        .yuzuGroupedForm()
    }
}

private struct AboutPane: View {
    var body: some View {
        VStack(spacing: Theme.Space.m) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                .shadow(Theme.Shadows.card)
                .materialize(0)
            VStack(spacing: Theme.Space.half) {
                Text("Yuzu").type(.title).foregroundStyle(Theme.ink)
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .type(.caption).foregroundStyle(Theme.inkMute)
            }
            .materialize(1)
            EmphasisText("Convert, edit and act on files, right ", "at", " your pointer.")
                .type(.body).multilineTextAlignment(.center).foregroundStyle(Theme.inkSoft).frame(maxWidth: 360)
                .materialize(2)
            Grid(alignment: .leading, horizontalSpacing: Theme.Space.m - 4, verticalSpacing: Theme.Space.s) {
                ForEach(ToolLocator.all) { t in
                    GridRow {
                        Image(systemName: t.path == nil ? "circle.dashed" : "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(t.path == nil ? Theme.inkMute : Theme.ink)
                        Text(t.id).type(.callout).fontWeight(.medium).foregroundStyle(Theme.ink)
                        Text(t.path == nil ? "Not installed" : t.use).type(.callout).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            .padding(Theme.Space.m)
            .card()
            .materialize(3)
            TrustLine(lead: "Private by design.", rest: "Every file stays on this Mac.").materialize(4)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
