import Foundation
import ServiceManagement
import Combine

@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    @Published private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    @Published var lastError: String?

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() { status = SMAppService.mainApp.status }

    func setEnabled(_ on: Bool) {
        lastError = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }
}
