import AppKit
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()

    private var statusItemController: StatusItemController?
    private let preferencesWindowController = PreferencesWindowController()
    private let captureCoordinator = CaptureCoordinator()
    private var isQuitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Keep SnapNook running in the menu bar.")

        statusItemController = StatusItemController(
            onCaptureArea: { [weak self] in self?.captureCoordinator.captureArea() },
            onCaptureText: { [weak self] in self?.captureCoordinator.captureText() },
            onPreferences: { [weak self] in self?.preferencesWindowController.show() },
            onQuit: { [weak self] in self?.quit() }
        )

        KeyboardShortcuts.onKeyUp(for: .captureArea) { [weak self] in
            self?.captureCoordinator.captureArea()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isQuitting ? .terminateNow : .terminateCancel
    }

    private func quit() {
        isQuitting = true
        NSApp.terminate(nil)
    }
}
