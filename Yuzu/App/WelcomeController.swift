import AppKit
import SwiftUI

/// First-run welcome: one calm page that teaches the three keys and checks the optional helper tools.
@MainActor
final class WelcomeController {
    static let shared = WelcomeController()
    static let doneKey = "onboarding.done"
    private var window: NSWindow?

    static var shouldShowOnLaunch: Bool {
        !UserDefaults.standard.bool(forKey: doneKey) && !UserDefaults.standard.bool(forKey: "YuzuNoOnboarding")
    }

    func show(background: Bool = false) {
        let w = window ?? makeWindow()
        window = w
        if background {
            Offscreen.park(w)
        } else {
            w.ignoresMouseEvents = false
            w.level = .normal
            w.center()
            NSApp.activate()
            w.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 548),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: WelcomeView(done: { [weak self] in self?.close() },
                                                            tryRing: { WheelController.shared.showDemo() }))
        return w
    }
}

struct WelcomeView: View {
    let done: () -> Void
    let tryRing: () -> Void
    @State private var tools = ToolLocator.all

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 76, height: 76)
                    .shadow(color: Theme.accentDeep.opacity(0.35), radius: 14, y: 6)
                Text("Welcome to Yuzu").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Start dragging any file, tap a key, and a ring of options opens at your pointer. Drop on one.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 460).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 34)

            HStack(spacing: 12) {
                keyCard("⇧", "Shift", "Convert", "JPG, PNG, HEIC, WebP, PDF, MP4, MP3 and more")
                keyCard("⌘", "Command", "Tools", "Compress, resize, trim, merge, add background")
                keyCard("⌃", "Control", "Actions", "AirDrop, Float, copy, move, Terminal")
            }
            .padding(.top, 24).padding(.horizontal, 28)

            VStack(alignment: .leading, spacing: 7) {
                Text("Optional helpers").font(.system(size: 12, weight: .semibold))
                ForEach(tools) { t in
                    HStack(spacing: 8) {
                        Image(systemName: t.path == nil ? "circle.dashed" : "checkmark.circle.fill")
                            .foregroundStyle(t.path == nil ? Color.secondary : Theme.accentDeep)
                        Text(t.id).font(.system(size: 12, weight: .medium)).frame(width: 64, alignment: .leading)
                        Text(t.use).font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        if t.path == nil, let cmd = ToolLocator.installHint[t.id] {
                            Text(cmd).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(cmd, forType: .string)
                            } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless).help("Copy command")
                        }
                    }
                }
                Text("Images, PDFs and most tools work without them. Install with Homebrew for video, WebP and Office files.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.045)))
            .padding(.horizontal, 28).padding(.top, 18)

            Spacer(minLength: 12)
            HStack {
                Text("Yuzu lives in the menu bar. Everything runs on this Mac.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                Spacer()
                Button("Try the Ring", action: tryRing)
                Button("Get Started", action: done).keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).tint(Theme.accentDeep)
            }
            .controlSize(.large)
            .padding(.horizontal, 28).padding(.bottom, 24)
        }
        .frame(width: 640, height: 548)
        .background(LinearGradient(colors: [Theme.accent.opacity(0.16), .clear], startPoint: .top, endPoint: .center))
        .onAppear { tools = ToolLocator.all }
    }

    private func keyCard(_ sym: String, _ key: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(sym).font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent))
                    .foregroundStyle(Theme.ink)
                Text(key).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}
