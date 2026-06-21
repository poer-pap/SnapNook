import AppKit
import CoreGraphics

final class ScreenCapturePermissionService {
    var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestPermission() {
        if CGRequestScreenCaptureAccess() {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "Allow SnapNook in System Settings > Privacy & Security > Screen & System Audio Recording. If you just enabled it, quit and reopen SnapNook once, then try again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            openSystemSettings()
        }
    }

    private func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenRecording"
        ]

        for value in urls {
            guard let url = URL(string: value), NSWorkspace.shared.open(url) else {
                continue
            }
            return
        }
    }
}
