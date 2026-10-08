import AppKit
import OSLog

private let overlayLogger = Logger(subsystem: "com.ethan.snapnook", category: "CaptureOverlay")

enum CaptureSelectionMode {
    case screenshot
    case textOCR
}

enum CaptureOverlayResult {
    case captured(CaptureScreen, CGRect)
    case cancelled
    case failed
}

final class CaptureOverlayController {
    private let screens: [CaptureScreen]
    private let mode: CaptureSelectionMode
    private let completion: (CaptureOverlayResult) -> Void
    private var windows: [CaptureOverlayWindow] = []
    private var inputSession: CaptureInputSession?
    private var selectionWindow: CaptureOverlayWindow?
    private var didFinish = false
    private var didCleanup = false

    init(screens: [CaptureScreen], mode: CaptureSelectionMode, completion: @escaping (CaptureOverlayResult) -> Void) {
        self.screens = screens
        self.mode = mode
        self.completion = completion
    }

    deinit {
        print("CaptureOverlayController deinit")
    }

    func show() {
        overlayLogger.notice("Overlay show requested for \(NSScreen.screens.count) screen(s).")

        windows = screens.map { screen in
            CaptureOverlayWindow(screen: screen, mode: mode) { [weak self] result in
                self?.finish(result)
            }
        }

        overlayLogger.notice("Overlay windows created: \(self.windows.count).")
        let session = CaptureInputSession { [weak self] type, event in
            self?.handle(type: type, event: event)
        } onFailure: { [weak self] in
            self?.finish(.failed)
        }
        inputSession = session
        guard session.start() else {
            finish(.failed)
            return
        }
        windows.forEach { $0.orderFrontRegardless() }
        CaptureOverlayView.selectionCursor.set()
        overlayLogger.notice("Overlay windows shown.")
    }

    func handle(type: CGEventType, event: CGEvent) {
        guard !didFinish else { return }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let point = CGPoint(x: event.location.x, y: primaryTop - event.location.y)
        let target = selectionWindow ?? windows.first { $0.frame.contains(point) }
        if type == .leftMouseDown { selectionWindow = target }
        for window in windows {
            guard let view = window.contentView as? CaptureOverlayView else { continue }
            if window === target {
                view.handle(type: type, point: CGPoint(x: point.x - window.frame.minX,
                                                       y: point.y - window.frame.minY),
                            shift: event.flags.contains(.maskShift),
                            keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)))
            } else if type == .mouseMoved {
                view.pointerExited()
            }
        }
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
        didFinish = true
        inputSession?.stop()
        inputSession = nil
        selectionWindow = nil
        NSCursor.arrow.set()
        overlayLogger.notice("Overlay cleanup.")
        let windowsToClose = windows
        windows.removeAll()

        DispatchQueue.main.async {
            windowsToClose.forEach { $0.closeIfNeeded() }
        }
    }
}

private final class CaptureOverlayWindow: NSPanel {
    private var didClose = false

    init(screen: CaptureScreen, mode: CaptureSelectionMode, completion: @escaping (CaptureOverlayResult) -> Void) {
        let overlayView = CaptureOverlayView(screen: screen, mode: mode, completion: completion)
        super.init(contentRect: screen.screenFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        contentView = overlayView
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        level = .screenSaver
        ignoresMouseEvents = true
        animationBehavior = .none
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hasShadow = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

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

struct CaptureSelectionDrag {
    var anchor: CGPoint
    var rect: CGRect = .zero
    private var lastPoint: CGPoint

    init(start: CGPoint) {
        anchor = start
        lastPoint = start
        rect = CGRect(origin: start, size: .zero)
    }

    mutating func update(to point: CGPoint, bounds: CGRect, square: Bool, moving: Bool) {
        if moving {
            let dx = min(max(point.x - lastPoint.x, bounds.minX - rect.minX), bounds.maxX - rect.maxX)
            let dy = min(max(point.y - lastPoint.y, bounds.minY - rect.minY), bounds.maxY - rect.maxY)
            rect = rect.offsetBy(dx: dx, dy: dy)
            anchor.x += dx
            anchor.y += dy
        } else {
            let end = CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                              y: min(max(point.y, bounds.minY), bounds.maxY))
            var dx = end.x - anchor.x
            var dy = end.y - anchor.y
            if square {
                let side = min(abs(dx), abs(dy))
                dx = dx < 0 ? -side : side
                dy = dy < 0 ? -side : side
            }
            rect = CGRect(x: min(anchor.x, anchor.x + dx), y: min(anchor.y, anchor.y + dy),
                          width: abs(dx), height: abs(dy))
        }
        lastPoint = point
    }
}

final class CaptureOverlayView: NSView {
    static let selectionCursor: NSCursor = {
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { _ in
            let cross = NSBezierPath()
            cross.move(to: CGPoint(x: 2, y: 12))
            cross.line(to: CGPoint(x: 22, y: 12))
            cross.move(to: CGPoint(x: 12, y: 2))
            cross.line(to: CGPoint(x: 12, y: 22))
            cross.appendOval(in: CGRect(x: 7, y: 7, width: 10, height: 10))
            NSColor.black.setStroke()
            cross.lineWidth = 3
            cross.stroke()
            NSColor.white.setStroke()
            cross.lineWidth = 1
            cross.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }()

    private let screen: CaptureScreen
    private let completion: (CaptureOverlayResult) -> Void
    private var drag: CaptureSelectionDrag?
    private var pointer: CGPoint
    private var spaceHeld = false
    private var didComplete = false

    init(screen: CaptureScreen, mode _: CaptureSelectionMode, completion: @escaping (CaptureOverlayResult) -> Void) {
        self.screen = screen
        self.completion = completion
        self.pointer = CGPoint(x: NSEvent.mouseLocation.x - screen.screenFrame.minX,
                               y: NSEvent.mouseLocation.y - screen.screenFrame.minY)
        super.init(frame: NSRect(origin: .zero, size: screen.screenFrame.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func pointerExited() {
        guard drag == nil else { return }
        pointer = CGPoint(x: -1, y: -1)
        needsDisplay = true
    }

    func handle(type: CGEventType, point: CGPoint, shift: Bool = false, keyCode: Int = 0) {
        guard !didComplete else { return }
        switch type {
        case .mouseMoved:
            Self.selectionCursor.set()
            pointer = point
        case .leftMouseDown:
            pointer = point
            drag = CaptureSelectionDrag(start: point)
        case .leftMouseDragged, .leftMouseUp:
            pointer = point
            drag?.update(to: point, bounds: bounds, square: shift, moving: spaceHeld)
            if type == .leftMouseUp, let selection = drag?.rect {
                complete(selection.width >= 5 && selection.height >= 5
                         ? .captured(screen, screenRect(selection)) : .cancelled)
            }
        case .flagsChanged:
            drag?.update(to: pointer, bounds: bounds, square: shift, moving: spaceHeld)
        case .keyDown:
            if keyCode == 53 { complete(.cancelled) }
            if keyCode == 49 { spaceHeld = true }
        case .keyUp:
            if keyCode == 49 { spaceHeld = false }
        default:
            break
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.clear(bounds)

        NSColor.white.setStroke()
        if let selection = drag?.rect {
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 1.5
            border.stroke()
        }
        guard drag != nil || ((bounds.minX...bounds.maxX).contains(pointer.x)
            && (bounds.minY...bounds.maxY).contains(pointer.y)) else { return }
        let cursor = CGPoint(x: min(max(pointer.x, 0), bounds.maxX), y: min(max(pointer.y, 0), bounds.maxY))
        let text: String
        if let selection = drag?.rect {
            let pixels = screen.pixelRect(for: screenRect(selection))
            text = "\(Int(pixels.width))\n\(Int(pixels.height))"
        } else {
            let x = min(Int(floor(cursor.x * CGFloat(screen.pixelWidth) / bounds.width)), screen.pixelWidth - 1)
            let y = min(Int(floor((bounds.maxY - cursor.y) * CGFloat(screen.pixelHeight) / bounds.height)), screen.pixelHeight - 1)
            text = "\(x)\n\(y)"
        }
        drawLabel(text, at: cursor)
    }

    private func drawLabel(_ text: String, at point: CGPoint) {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .shadow: shadow
        ]
        let label = text as NSString
        let size = label.size(withAttributes: attributes)
        var origin = CGPoint(x: point.x + 10, y: point.y - 10 - size.height)
        if origin.x + size.width > bounds.maxX - 4 { origin.x = point.x - 10 - size.width }
        if origin.y < 4 { origin.y = point.y + 10 }
        origin.x = min(max(4, origin.x), bounds.maxX - size.width - 4)
        origin.y = min(max(4, origin.y), bounds.maxY - size.height - 4)
        label.draw(at: origin, withAttributes: attributes)
    }

    private func screenRect(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: screen.screenFrame.minX, dy: screen.screenFrame.minY)
    }

    private func complete(_ result: CaptureOverlayResult) {
        guard !didComplete else { return }
        didComplete = true
        completion(result)
    }
}
