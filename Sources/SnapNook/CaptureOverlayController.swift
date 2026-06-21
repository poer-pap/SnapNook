import AppKit
import OSLog

private let overlayLogger = Logger(subsystem: "com.ethan.snapnook", category: "CaptureOverlay")

enum CaptureOverlayResult {
    case captured(CGRect, CGRect)
    case cancelled
}

final class CaptureOverlayController {
    private let completion: (CaptureOverlayResult) -> Void
    private var windows: [CaptureOverlayWindow] = []
    private var didFinish = false
    private var didCleanup = false

    init(completion: @escaping (CaptureOverlayResult) -> Void) {
        self.completion = completion
    }

    deinit {
        print("CaptureOverlayController deinit")
    }

    func show() {
        overlayLogger.notice("Overlay show requested for \(NSScreen.screens.count) screen(s).")
        NSApp.activate(ignoringOtherApps: true)

        windows = NSScreen.screens.map { screen in
            CaptureOverlayWindow(screen: screen) { [weak self] result in
                self?.finish(result)
            }
        }

        overlayLogger.notice("Overlay windows created: \(self.windows.count).")
        windows.forEach { $0.show() }
        overlayLogger.notice("Overlay windows shown.")
    }

    private func finish(_ result: CaptureOverlayResult) {
        guard !didFinish else {
            overlayLogger.notice("Ignoring duplicate overlay completion.")
            return
        }

        didFinish = true
        overlayLogger.notice("Overlay finishing.")
        windows.forEach { $0.orderOut(nil) }

        DispatchQueue.main.async { [completion] in
            completion(result)
        }
    }

    func cleanup() {
        guard !didCleanup else {
            overlayLogger.notice("Ignoring duplicate overlay cleanup.")
            return
        }

        didCleanup = true
        overlayLogger.notice("Overlay cleanup.")
        let windowsToClose = windows
        windows.removeAll()

        DispatchQueue.main.async {
            windowsToClose.forEach { $0.closeIfNeeded() }
        }
    }
}

private final class CaptureOverlayWindow: NSWindow {
    private var didClose = false

    init(screen: NSScreen, completion: @escaping (CaptureOverlayResult) -> Void) {
        let overlayView = CaptureOverlayView(screen: screen, completion: completion)
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)

        contentView = overlayView
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        level = .screenSaver
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hasShadow = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func show() {
        overlayLogger.notice("Overlay window show.")
        orderFrontRegardless()
        makeKey()
        makeMain()
        contentView?.window?.makeFirstResponder(contentView)
    }

    func closeIfNeeded() {
        guard !didClose else {
            overlayLogger.notice("Ignoring duplicate overlay window close.")
            return
        }

        didClose = true
        close()
    }

    deinit {
        print("CaptureOverlayWindow deinit")
    }
}

private final class CaptureOverlayView: NSView {
    private let screen: NSScreen
    private let completion: (CaptureOverlayResult) -> Void
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var didComplete = false

    init(screen: NSScreen, completion: @escaping (CaptureOverlayResult) -> Void) {
        self.screen = screen
        self.completion = completion
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        print("CaptureOverlayView deinit")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        overlayLogger.notice("Overlay view moved to window: \(self.window != nil).")
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.36).setFill()
        bounds.fill()

        guard let selection = selectionRect else { return }

        NSColor.clear.setFill()
        selection.fill(using: .destinationOut)

        NSColor.white.setStroke()
        let path = NSBezierPath(rect: selection)
        path.lineWidth = 2
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        overlayLogger.notice("Overlay mouse down.")
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        overlayLogger.notice("Overlay mouse up.")
        currentPoint = convert(event.locationInWindow, from: nil)

        guard let selection = selectionRect, selection.width >= 4, selection.height >= 4 else {
            complete(.cancelled)
            return
        }

        complete(.captured(convertToScreenRect(selection), screen.frame))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            complete(.cancelled)
        } else {
            super.keyDown(with: event)
        }
    }

    private var selectionRect: NSRect? {
        guard let startPoint, let currentPoint else { return nil }

        return NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }

    private func convertToScreenRect(_ rect: NSRect) -> CGRect {
        CGRect(
            x: screen.frame.minX + rect.minX,
            y: screen.frame.minY + rect.minY,
            width: rect.width,
            height: rect.height
        )
    }

    private func complete(_ result: CaptureOverlayResult) {
        guard !didComplete else {
            overlayLogger.notice("Ignoring duplicate overlay view completion.")
            return
        }

        didComplete = true
        DispatchQueue.main.async { [completion] in
            completion(result)
        }
    }
}
