import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let loginItem = NSMenuItem()
    private let hintItem = NSMenuItem()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.image = Glyphs.menuBarIcon()
        statusItem.button?.toolTip = "Yuzu"
        buildMenu()
        statusItem.menu = menu
        menu.delegate = self
    }

    private func item(_ title: String, _ symbol: String?, _ action: Selector?, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return i
    }

    @objc private func showWelcome() { WelcomeController.shared.show() }
    @objc private func showFloat() { FloatController.shared.add([], near: NSEvent.mouseLocation) }

    private func buildMenu() {
        menu.autoenablesItems = false
        let header = NSMenuItem()
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(string: "Yuzu is ready", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
        menu.addItem(header)
        hintItem.isEnabled = false
        menu.addItem(hintItem)
        menu.addItem(.separator())
        menu.addItem(item("Try the Ring", "circle.dotted.circle", #selector(tryRing)))
        menu.addItem(item("Show Float", "paperclip", #selector(showFloat)))
        menu.addItem(item("Getting Started…", "sparkles", #selector(showWelcome)))
        menu.addItem(item("Settings…", "gearshape", #selector(openSettings), key: ","))
        loginItem.title = "Launch at Login"
        loginItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        loginItem.target = self
        loginItem.action = #selector(toggleLogin)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        let quit = item("Quit Yuzu", "xmark.circle", #selector(quit), key: "q")
        menu.addItem(quit)
        refresh()
    }

    private func refresh() {
        let c = Prefs.combo(for: .convert).symbol
        let t = Prefs.combo(for: .tools).symbol
        let a = Prefs.combo(for: .actions).symbol
        hintItem.attributedTitle = NSAttributedString(
            string: "Drag a file, then tap \(c) convert  \(t) tools  \(a) actions",
            attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor])
        if LoginItem.isSupported {
            LoginItem.shared.refresh()
            loginItem.isEnabled = true
            loginItem.title = "Launch at Login"
            loginItem.state = LoginItem.shared.isEnabled ? .on : .off
        } else {
            loginItem.isEnabled = false
            loginItem.state = .off
            loginItem.title = "Launch at Login (macOS 13+)"
        }
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    /// Opens the menu programmatically (used by the screenshot hook).
    func openMenu(autoCloseAfter seconds: TimeInterval) {
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.menu.cancelTracking() }
        }
        RunLoop.main.add(timer, forMode: .common)
        statusItem.button?.performClick(nil)
    }

    @objc private func tryRing() { WheelController.shared.showDemo() }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func toggleLogin() {
        LoginItem.shared.setEnabled(!LoginItem.shared.isEnabled)
        refresh()
        if LoginItem.shared.needsApproval { LoginItem.shared.openLoginItemsSettings() }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
