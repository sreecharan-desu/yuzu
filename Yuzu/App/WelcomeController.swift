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
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
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
            VStack(spacing: Theme.Space.m) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                    .shadow(Theme.Shadows.card)
                    .materialize(0)
                EmphasisText("Drag a file. Tap a key. Drop it ", "anywhere", ".")
                    .type(.display)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .materialize(1)
                Text("A ring of options opens at your pointer. Release on the one you want.")
                    .type(.body).foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center).frame(maxWidth: 440).fixedSize(horizontal: false, vertical: true)
                    .materialize(2)
            }
            .padding(.top, Theme.Space.xxl + Theme.Space.s)

            HStack(spacing: Theme.Space.s) {
                keyCard("⇧", "Shift", "Convert", "JPG, PNG, HEIC, WebP, PDF, MP4, MP3 and more").materialize(3)
                keyCard("⌘", "Command", "Tools", "Compress, resize, trim, merge, add a background").materialize(4)
                keyCard("⌃", "Control", "Actions", "AirDrop, Float, copy, move, open in Terminal").materialize(5)
            }
            .padding(.top, Theme.Space.xl).padding(.horizontal, Theme.Space.xl)

            VStack(alignment: .leading, spacing: Theme.Space.half) {
                Text("Optional helpers").type(.callout).fontWeight(.medium).foregroundStyle(Theme.ink)
                ForEach(tools) { t in
                    HStack(spacing: Theme.Space.s) {
                        Image(systemName: t.path == nil ? "circle.dashed" : "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(t.path == nil ? Theme.inkMute : Theme.ink)
                        Text(t.id).type(.callout).fontWeight(.medium).foregroundStyle(Theme.ink).frame(width: 64, alignment: .leading)
                        Text(t.use).type(.callout).foregroundStyle(Theme.inkSoft)
                        Spacer()
                        if t.path == nil, let cmd = ToolLocator.installHint[t.id] {
                            Text(cmd).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkSoft)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(cmd, forType: .string)
                            } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(QuietIconButtonStyle(size: 24)).help("Copy command")
                        }
                    }
                    .frame(height: 24)
                }
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(radius: Theme.Radius.card)
            .padding(.horizontal, Theme.Space.xl).padding(.top, Theme.Space.s)
            .materialize(6)

            Spacer(minLength: Theme.Space.m)
            HStack(spacing: Theme.Space.s) {
                TrustLine(lead: "Private by design.", rest: "Every file stays on this Mac.")
                Spacer()
                Button("Try the ring", action: tryRing).buttonStyle(QuietPillButtonStyle())
                Button("Get started", action: done).keyboardShortcut(.defaultAction)
                    .buttonStyle(InkPillButtonStyle())
            }
            .padding(.horizontal, Theme.Space.xl).padding(.bottom, Theme.Space.xl)
            .materialize(7, rise: 8)
        }
        .frame(width: 640, height: 600)
        .background(Theme.surface)
        .onAppear { tools = ToolLocator.all }
    }

    private func keyCard(_ sym: String, _ key: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Text(sym).font(.system(size: 15, weight: .medium))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.surface))
                    .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                    .foregroundStyle(Theme.ink)
                Text(key).type(.caption).foregroundStyle(Theme.inkMute)
            }
            Spacer(minLength: 0)
            Text(title).type(.headline).foregroundStyle(Theme.ink)
            Text(detail).type(.caption).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
        .card(radius: Theme.Radius.card)
    }
}
