import Foundation
import ServiceManagement

/// Starts NoFormatNotes at login, via `SMAppService` so it appears in Login Items under the app's own
/// name rather than as an anonymous background agent.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var isBlockedByUser: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
