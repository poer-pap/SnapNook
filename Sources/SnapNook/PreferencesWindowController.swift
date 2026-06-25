import AppKit
import SwiftUI
import KeyboardShortcuts

final class PreferencesWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            window = makeWindow()
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let view = PreferencesView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "SnapNook Preferences"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        return window
    }
}

private struct PreferencesView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Capture Area:", name: .captureArea)
            KeyboardShortcuts.Recorder("Capture Text:", name: .captureText)
        }
        .padding(24)
        .frame(width: 420, height: 200)
    }
}
