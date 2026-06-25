import AppKit

final class ToastController {
    private var panel: ToastPanel?
    private var closeTask: DispatchWorkItem?

    func show(message: String, duration: TimeInterval = 1.6) {
        closeTask?.cancel()

        let panel = panel ?? ToastPanel()
        panel.setMessage(message)
        position(panel: panel)
        panel.orderFrontRegardless()
        self.panel = panel

        let closeTask = DispatchWorkItem { [weak self] in
            self?.close()
        }
        self.closeTask = closeTask
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: closeTask)
    }

    func close() {
        closeTask?.cancel()
        closeTask = nil
        panel?.closeIfNeeded()
        panel = nil
    }

    private func position(panel: NSPanel) {
        let screen = currentMouseScreen() ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero
        let frame = panel.frame
        panel.setFrame(
            NSRect(
                x: visibleFrame.midX - frame.width / 2,
                y: visibleFrame.minY + 40,
                width: frame.width,
                height: frame.height
            ),
            display: true
        )
    }

    private func currentMouseScreen() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
    }
}

private final class ToastPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private var didClose = false

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true

        let container = NSVisualEffectView(frame: contentRect(forFrameRect: frame))
        container.material = .hudWindow
        container.blendingMode = .withinWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true

        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.frame = container.bounds.insetBy(dx: 12, dy: 10)
        label.autoresizingMask = [.width, .height]

        container.addSubview(label)
        contentView = container
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setMessage(_ message: String) {
        label.stringValue = message
    }

    func closeIfNeeded() {
        guard !didClose else { return }
        didClose = true
        orderOut(nil)
        close()
    }
}
