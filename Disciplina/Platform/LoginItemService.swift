import AppKit
import Observation
import ServiceManagement

@MainActor @Observable
final class LoginItemService {
    private(set) var status = SMAppService.mainApp.status
    private(set) var errorMessage: String?
    var enabled: Bool { status == .enabled || status == .requiresApproval }

    func refresh() { status = SMAppService.mainApp.status }
    func setEnabled(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
        refresh()
    }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
