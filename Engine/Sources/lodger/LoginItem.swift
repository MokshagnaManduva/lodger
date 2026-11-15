import Foundation
import ServiceManagement

/// Launch at login, behind a small seam so it can be tested without registering
/// a real login item.
///
/// `SMAppService.mainApp` (macOS 13+) needs no helper bundle and no permission
/// prompt; the user can also remove the item in System Settings, so its state is
/// always read from the system rather than cached in our preferences.
struct LoginItem {
    /// False when there is nothing to register, e.g. the bare SwiftPM binary.
    var isAvailable: Bool
    var isEnabled: () -> Bool
    var setEnabled: (Bool) throws -> Void

    static let system = LoginItem(
        isAvailable: Bundle.main.bundleURL.pathExtension == "app",
        isEnabled: { SMAppService.mainApp.status == .enabled },
        setEnabled: { on in
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        })
}
