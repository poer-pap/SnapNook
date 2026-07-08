import AppKit

final class ScrollingSelectionWindow: NSPanel {
    private var didClose = false

    init(screen: NSScreen, contentView: NSView) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.contentView = contentView
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        level = .screenSaver
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hasShadow = false
    }

    override var canBecomeKey: Bool { true }

    func show() {
        orderFrontRegardless()
        makeKey()
        contentView?.window?.makeFirstResponder(contentView)
    }

    func closeIfNeeded() {
        guard !didClose else { return }
        didClose = true
        close()
    }
}
