import AppKit

final class StatusItemController {
    private let statusItem: NSStatusItem

    init(
        onCaptureArea: @escaping () -> Void,
        onCaptureText: @escaping () -> Void,
        onPreferences: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            if let image = NSImage(named: "SnapNookMenuBarTemplate") {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                button.image = image
                button.imagePosition = .imageOnly
                button.toolTip = "SnapNook"
                button.setAccessibilityLabel("SnapNook")
            } else {
                button.title = "SnapNook"
            }
        }

        let menu = NSMenu()
        menu.addItem(MenuActionItem(title: "Capture Area", actionHandler: onCaptureArea))
        menu.addItem(MenuActionItem(title: "Capture Text", actionHandler: onCaptureText))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(MenuActionItem(title: "Preferences", actionHandler: onPreferences))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(MenuActionItem(title: "Quit", actionHandler: onQuit))
        statusItem.menu = menu
    }
}

private final class MenuActionItem: NSMenuItem {
    private let actionHandler: () -> Void

    init(title: String, actionHandler: @escaping () -> Void) {
        self.actionHandler = actionHandler
        super.init(title: title, action: #selector(runAction), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runAction() {
        actionHandler()
    }
}
