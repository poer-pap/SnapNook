import AppKit
import OSLog

private let overlayLogger = Logger(subsystem: "com.ethan.snapnook", category: "CaptureOverlay")

enum CaptureSelectionMode {
    case screenshot
    case textOCR
}

enum CaptureOverlayResult {
    case captured(CGRect, CGRect)
    case cancelled
}

final class CaptureOverlayController {
    private let mode: CaptureSelectionMode
    private let completion: (CaptureOverlayResult) -> Void
    private var windows: [CaptureOverlayWindow] = []
    private var didFinish = false
    private var didCleanup = false

    init(mode: CaptureSelectionMode, completion: @escaping (CaptureOverlayResult) -> Void) {
        self.mode = mode
        self.completion = completion
    }

    deinit {
        print("CaptureOverlayController deinit")
    }

    func show() {
        overlayLogger.notice("Overlay show requested for \(NSScreen.screens.count) screen(s).")
        NSApp.activate(ignoringOtherApps: true)

        windows = NSScreen.screens.map { screen in
            CaptureOverlayWindow(screen: screen, mode: mode) { [weak self] result in
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

    init(screen: NSScreen, mode: CaptureSelectionMode, completion: @escaping (CaptureOverlayResult) -> Void) {
        let overlayView = CaptureOverlayView(screen: screen, mode: mode, completion: completion)
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
    private enum Style {
        static let screenshotBackdropAlpha: CGFloat = 0.36
        static let screenshotBorderWidth: CGFloat = 2
        static let textBackdropAlpha: CGFloat = 0.14
        static let textFillAlpha: CGFloat = 0.25
        static let textBorderWidth: CGFloat = 1.5
        static let textLabelPadding = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        static let textLabelOffset: CGFloat = 8
        static let minimumSelectionSize: CGFloat = 5
    }

    private let screen: NSScreen
    private let mode: CaptureSelectionMode
    private let completion: (CaptureOverlayResult) -> Void
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var didComplete = false

    init(screen: NSScreen, mode: CaptureSelectionMode, completion: @escaping (CaptureOverlayResult) -> Void) {
        self.screen = screen
        self.mode = mode
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
        switch mode {
        case .screenshot:
            drawScreenshotOverlay()
        case .textOCR:
            drawTextOverlay()
        }
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

        guard let selection = selectionRect,
              selection.width >= Style.minimumSelectionSize,
              selection.height >= Style.minimumSelectionSize else {
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

    private func drawScreenshotOverlay() {
        NSColor.black.withAlphaComponent(Style.screenshotBackdropAlpha).setFill()
        bounds.fill()

        guard let selection = selectionRect else { return }

        NSColor.clear.setFill()
        selection.fill(using: .destinationOut)

        NSColor.white.setStroke()
        let path = NSBezierPath(rect: selection)
        path.lineWidth = Style.screenshotBorderWidth
        path.stroke()
    }

    private func drawTextOverlay() {
        NSColor.black.withAlphaComponent(Style.textBackdropAlpha).setFill()
        bounds.fill()

        guard let selection = selectionRect else { return }

        NSColor.white.withAlphaComponent(Style.textFillAlpha).setFill()
        selection.fill()

        NSColor.white.withAlphaComponent(0.95).setStroke()
        let path = NSBezierPath(rect: selection)
        path.lineWidth = Style.textBorderWidth
        path.stroke()

        drawSelectionSizeLabel(for: selection)
    }

    private func drawSelectionSizeLabel(for selection: NSRect) {
        let pixelSize = selectionPixelSize(for: selection)
        let label = "\(pixelSize.width)\n\(pixelSize.height)" as NSString
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]

        let textSize = label.boundingRect(
            with: NSSize(width: 120, height: 80),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        ).integral.size

        let backgroundRect = NSRect(
            x: selection.maxX + Style.textLabelOffset,
            y: selection.minY - textSize.height - CGFloat(Style.textLabelPadding.top + Style.textLabelPadding.bottom) - Style.textLabelOffset,
            width: textSize.width + CGFloat(Style.textLabelPadding.left + Style.textLabelPadding.right),
            height: textSize.height + CGFloat(Style.textLabelPadding.top + Style.textLabelPadding.bottom)
        )
        let clampedRect = clampLabelRect(backgroundRect)

        let labelBackground = NSBezierPath(roundedRect: clampedRect, xRadius: 6, yRadius: 6)
        NSColor.black.withAlphaComponent(0.55).setFill()
        labelBackground.fill()

        label.draw(
            in: NSRect(
                x: clampedRect.minX + CGFloat(Style.textLabelPadding.left),
                y: clampedRect.minY + CGFloat(Style.textLabelPadding.bottom),
                width: clampedRect.width - CGFloat(Style.textLabelPadding.left + Style.textLabelPadding.right),
                height: clampedRect.height - CGFloat(Style.textLabelPadding.top + Style.textLabelPadding.bottom)
            ),
            withAttributes: attributes
        )
    }

    private func clampLabelRect(_ rect: NSRect) -> NSRect {
        var adjusted = rect
        if adjusted.maxX > bounds.maxX - 8 {
            adjusted.origin.x = max(bounds.minX + 8, bounds.maxX - 8 - adjusted.width)
        }
        if adjusted.minX < bounds.minX + 8 {
            adjusted.origin.x = bounds.minX + 8
        }
        if adjusted.minY < bounds.minY + 8 {
            adjusted.origin.y = min(bounds.maxY - 8 - adjusted.height, selectionRect?.maxY ?? adjusted.minY + Style.textLabelOffset)
        }
        if adjusted.maxY > bounds.maxY - 8 {
            adjusted.origin.y = bounds.maxY - 8 - adjusted.height
        }
        return adjusted
    }

    private func selectionPixelSize(for rect: NSRect) -> (width: Int, height: Int) {
        let scale = window?.backingScaleFactor ?? screen.backingScaleFactor
        return (
            width: Int(round(rect.width * scale)),
            height: Int(round(rect.height * scale))
        )
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
