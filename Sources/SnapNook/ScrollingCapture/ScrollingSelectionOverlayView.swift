import AppKit

final class ScrollingSelectionOverlayView: NSView {
    enum Interaction {
        case startCapture
        case done
        case cancel
        case escape
    }

    private enum HitTestResult {
        case body
        case resize(ResizeHandle)
        case outside
    }

    private enum DragState {
        case idle
        case selecting(start: NSPoint)
        case moving(start: NSPoint, original: NSRect)
        case resize(handle: ResizeHandle, original: NSRect, start: NSPoint)
    }

    private enum ResizeHandle: CaseIterable {
        case topLeft
        case top
        case topRight
        case right
        case bottomRight
        case bottom
        case bottomLeft
        case left
    }

    private enum Style {
        static let dimAlpha: CGFloat = 0.42
        static let borderWidth: CGFloat = 2
        static let cornerLength: CGFloat = 24
        static let handleSize: CGFloat = 10
        static let edgeHitTolerance: CGFloat = 8
        static let minSize = NSSize(width: 200, height: 120)
        static let buttonSize = NSSize(width: 154, height: 34)
        static let buttonGap: CGFloat = 14
    }

    private let screen: NSScreen
    private let allowedRect: NSRect
    private let onInteraction: (Interaction) -> Void
    private var hasSelection = false
    private var selectionRect: NSRect
    private var dragState: DragState = .idle
    private var isCapturing = false
    private var startButtonRect: NSRect = .zero

    init(screen: NSScreen, onInteraction: @escaping (Interaction) -> Void) {
        self.screen = screen
        self.onInteraction = onInteraction
        let screenBounds = NSRect(origin: .zero, size: screen.frame.size)
        self.allowedRect = NSRect(
            x: screen.visibleFrame.minX - screen.frame.minX,
            y: screen.visibleFrame.minY - screen.frame.minY,
            width: screen.visibleFrame.width,
            height: screen.visibleFrame.height
        ).intersection(screenBounds)

        self.selectionRect = .zero

        super.init(frame: screenBounds)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    var selectedScreenRect: CGRect {
        CGRect(
            x: screen.frame.minX + selectionRect.minX,
            y: screen.frame.minY + selectionRect.minY,
            width: selectionRect.width,
            height: selectionRect.height
        )
    }

    func setCapturing(_ value: Bool) {
        isCapturing = value
        dragState = .idle
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawDimmedBackground()
        if hasSelection { drawSelection() }

        if !hasSelection {
            let text = "Drag to select scrolling content (exclude fixed headers and scrollbars)" as NSString
            text.draw(at: NSPoint(x: allowedRect.midX - 230, y: allowedRect.midY), withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.white])
        } else if !isCapturing, case .idle = dragState {
            drawStartButton()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isCapturing {
            return
        }

        if hasSelection, startButtonRect.contains(point) {
            onInteraction(.startCapture)
            return
        }

        if !hasSelection {
            dragState = .selecting(start: point)
            hasSelection = true
            selectionRect = NSRect(origin: point, size: .zero)
            startButtonRect = .zero
            return
        }

        switch hitTestSelection(at: point) {
        case .body:
            dragState = .moving(start: point, original: selectionRect)
        case .resize(let handle):
            dragState = .resize(handle: handle, original: selectionRect, start: point)
        case .outside:
            dragState = .idle
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isCapturing else { return }

        let point = convert(event.locationInWindow, from: nil)
        switch dragState {
        case .idle:
            return
        case .selecting(let start):
            let end = NSPoint(x: min(max(point.x, allowedRect.minX), allowedRect.maxX), y: min(max(point.y, allowedRect.minY), allowedRect.maxY))
            selectionRect = NSRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        case .moving(let start, let original):
            var next = original
            next.origin = NSPoint(
                x: original.origin.x + point.x - start.x,
                y: original.origin.y + point.y - start.y
            )
            selectionRect = clamp(next)
        case .resize(let handle, let original, let start):
            selectionRect = clamp(resizedRect(from: original, handle: handle, delta: NSPoint(x: point.x - start.x, y: point.y - start.y)))
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if case .selecting = dragState {
            if selectionRect.width < Style.minSize.width || selectionRect.height < Style.minSize.height {
                hasSelection = false
                selectionRect = .zero
            } else {
                selectionRect = clamp(selectionRect)
            }
        }
        needsDisplay = true
        dragState = .idle
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onInteraction(.escape)
        } else {
            super.keyDown(with: event)
        }
    }

    private func drawDimmedBackground() {
        NSColor.black.withAlphaComponent(Style.dimAlpha).setFill()
        bounds.fill()

        NSGraphicsContext.saveGraphicsState()
        selectionRect.fill(using: .clear)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSelection() {
        NSColor.white.withAlphaComponent(isCapturing ? 0.88 : 0.96).setStroke()
        let path = NSBezierPath(rect: selectionRect)
        path.lineWidth = Style.borderWidth
        path.stroke()

        drawCorners()
        if !isCapturing {
            drawHandles()
        }
    }

    private func drawCorners() {
        let length = Style.cornerLength
        let path = NSBezierPath()
        let corners = [
            (NSPoint(x: selectionRect.minX, y: selectionRect.maxY), NSPoint(x: selectionRect.minX + length, y: selectionRect.maxY), NSPoint(x: selectionRect.minX, y: selectionRect.maxY - length)),
            (NSPoint(x: selectionRect.maxX, y: selectionRect.maxY), NSPoint(x: selectionRect.maxX - length, y: selectionRect.maxY), NSPoint(x: selectionRect.maxX, y: selectionRect.maxY - length)),
            (NSPoint(x: selectionRect.maxX, y: selectionRect.minY), NSPoint(x: selectionRect.maxX - length, y: selectionRect.minY), NSPoint(x: selectionRect.maxX, y: selectionRect.minY + length)),
            (NSPoint(x: selectionRect.minX, y: selectionRect.minY), NSPoint(x: selectionRect.minX + length, y: selectionRect.minY), NSPoint(x: selectionRect.minX, y: selectionRect.minY + length))
        ]

        for corner in corners {
            path.move(to: corner.0)
            path.line(to: corner.1)
            path.move(to: corner.0)
            path.line(to: corner.2)
        }

        path.lineWidth = 4
        path.stroke()
    }

    private func drawHandles() {
        NSColor.white.withAlphaComponent(0.95).setFill()
        for rect in handleRects().map(\.rect) {
            NSBezierPath(ovalIn: rect).fill()
        }
    }

    private func drawStartButton() {
        startButtonRect = NSRect(
            x: selectionRect.midX - Style.buttonSize.width / 2,
            y: max(allowedRect.minY + 10, selectionRect.minY + Style.buttonGap),
            width: Style.buttonSize.width,
            height: Style.buttonSize.height
        )
        drawPill(rect: startButtonRect, fill: NSColor.white.withAlphaComponent(0.86), title: "Start Capture", color: .black, symbol: "v")
    }

    private func drawPill(rect: NSRect, fill: NSColor, title: String, color: NSColor, symbol: String) {
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()

        let text = "\(symbol)  \(title)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: color
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
            withAttributes: attributes
        )
    }

    private func handleRects() -> [(handle: ResizeHandle, rect: NSRect)] {
        let size = Style.handleSize
        let points: [(ResizeHandle, NSPoint)] = [
            (.topLeft, NSPoint(x: selectionRect.minX, y: selectionRect.maxY)),
            (.top, NSPoint(x: selectionRect.midX, y: selectionRect.maxY)),
            (.topRight, NSPoint(x: selectionRect.maxX, y: selectionRect.maxY)),
            (.right, NSPoint(x: selectionRect.maxX, y: selectionRect.midY)),
            (.bottomRight, NSPoint(x: selectionRect.maxX, y: selectionRect.minY)),
            (.bottom, NSPoint(x: selectionRect.midX, y: selectionRect.minY)),
            (.bottomLeft, NSPoint(x: selectionRect.minX, y: selectionRect.minY)),
            (.left, NSPoint(x: selectionRect.minX, y: selectionRect.midY))
        ]

        return points.map { handle, point in
            (
                handle,
                NSRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
            )
        }
    }

    private func hitTestSelection(at point: NSPoint) -> HitTestResult {
        if let handle = handle(at: point) {
            return .resize(handle)
        }
        if let edge = edgeHandle(at: point) {
            return .resize(edge)
        }
        if selectionRect.contains(point) {
            return .body
        }
        return .outside
    }

    private func handle(at point: NSPoint) -> ResizeHandle? {
        handleRects().first { $0.rect.insetBy(dx: -5, dy: -5).contains(point) }?.handle
    }

    private func edgeHandle(at point: NSPoint) -> ResizeHandle? {
        let tolerance = Style.edgeHitTolerance
        guard selectionRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point),
              !selectionRect.insetBy(dx: tolerance, dy: tolerance).contains(point)
        else {
            return nil
        }

        let nearLeft = abs(point.x - selectionRect.minX) <= tolerance
        let nearRight = abs(point.x - selectionRect.maxX) <= tolerance
        let nearBottom = abs(point.y - selectionRect.minY) <= tolerance
        let nearTop = abs(point.y - selectionRect.maxY) <= tolerance

        switch (nearLeft, nearRight, nearBottom, nearTop) {
        case (true, false, false, true):
            return .topLeft
        case (false, true, false, true):
            return .topRight
        case (false, true, true, false):
            return .bottomRight
        case (true, false, true, false):
            return .bottomLeft
        case (true, false, false, false):
            return .left
        case (false, true, false, false):
            return .right
        case (false, false, true, false):
            return .bottom
        case (false, false, false, true):
            return .top
        default:
            return nil
        }
    }

    private func resizedRect(from original: NSRect, handle: ResizeHandle, delta: NSPoint) -> NSRect {
        var rect = original
        switch handle {
        case .topLeft:
            rect.origin.x += delta.x
            rect.size.width -= delta.x
            rect.size.height += delta.y
        case .top:
            rect.size.height += delta.y
        case .topRight:
            rect.size.width += delta.x
            rect.size.height += delta.y
        case .right:
            rect.size.width += delta.x
        case .bottomRight:
            rect.origin.y += delta.y
            rect.size.width += delta.x
            rect.size.height -= delta.y
        case .bottom:
            rect.origin.y += delta.y
            rect.size.height -= delta.y
        case .bottomLeft:
            rect.origin.x += delta.x
            rect.origin.y += delta.y
            rect.size.width -= delta.x
            rect.size.height -= delta.y
        case .left:
            rect.origin.x += delta.x
            rect.size.width -= delta.x
        }
        return rect.standardized
    }

    private func clamp(_ rect: NSRect) -> NSRect {
        var adjusted = rect

        if adjusted.width < Style.minSize.width {
            adjusted.size.width = Style.minSize.width
        }
        if adjusted.height < Style.minSize.height {
            adjusted.size.height = Style.minSize.height
        }
        if adjusted.width > allowedRect.width {
            adjusted.size.width = allowedRect.width
        }
        if adjusted.height > allowedRect.height {
            adjusted.size.height = allowedRect.height
        }

        if adjusted.minX < allowedRect.minX {
            adjusted.origin.x = allowedRect.minX
        }
        if adjusted.maxX > allowedRect.maxX {
            adjusted.origin.x = allowedRect.maxX - adjusted.width
        }
        if adjusted.minY < allowedRect.minY {
            adjusted.origin.y = allowedRect.minY
        }
        if adjusted.maxY > allowedRect.maxY {
            adjusted.origin.y = allowedRect.maxY - adjusted.height
        }

        return adjusted.integral
    }
}
