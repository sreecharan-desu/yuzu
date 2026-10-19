import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralPane().tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsPane().tabItem { Label("Shortcuts", systemImage: "keyboard") }
            ConversionPane().tabItem { Label("Conversion", systemImage: "arrow.triangle.2.circlepath") }
            AboutPane().tabItem { Label("About", systemImage: "info.circle") }
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
    @AppStorage(Prefs.Key.convertCombo) private var convert = ModifierCombo.shift.rawValue
    @AppStorage(Prefs.Key.toolsCombo) private var tools = ModifierCombo.command.rawValue
    @AppStorage(Prefs.Key.actionsCombo) private var actions = ModifierCombo.control.rawValue

    var body: some View {
        Form {
            Section {
                picker("Convert formats", $convert)
                picker("File tools", $tools)
                picker("File actions", $actions)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start dragging a file, then tap the key. The ring stays open until you drop.")
                    if Set([convert, tools, actions]).count < 3 {
                        Text("Two rings share the same key. Pick a different key for each.").foregroundStyle(.red)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func picker(_ title: String, _ value: Binding<Int>) -> some View {
        Picker(title, selection: value) {
            ForEach(ModifierCombo.allCases) { Text($0.label).tag($0.rawValue) }
        }
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
