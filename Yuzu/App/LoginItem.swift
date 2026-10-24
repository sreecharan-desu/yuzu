import Foundation
import ServiceManagement
import Combine

@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    /// Launch at login uses SMAppService, which needs macOS 13.
    static var isSupported: Bool {
        if #available(macOS 13, *) { return true }
        return false
    }

    @Published private(set) var isEnabled = false
    @Published private(set) var needsApproval = false
    @Published var lastError: String?

    func refresh() {
        guard #available(macOS 13, *) else {
            isEnabled = false
            needsApproval = false
            return
        }
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    func setEnabled(_ on: Bool) {
        lastError = nil
        guard #available(macOS 13, *) else {
            lastError = "Requires macOS 13 or later."
            return
        }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        guard #available(macOS 13, *) else { return }
        SMAppService.openSystemSettingsLoginItems()
    }
}
