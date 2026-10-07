import AppKit

final class ScrollingPreviewPanel: NSPanel {
    private enum Style {
        static let width: CGFloat = 220
        static let maxHeightRatio: CGFloat = 0.7
        static let padding: CGFloat = 12
        static let spacing: CGFloat = 10
    }

    private let previewView = ScrollingPreviewView()
    private var didClose = false

    init(selectionRect: CGRect, screen: NSScreen) {
        let height = min(screen.visibleFrame.height * Style.maxHeightRatio, 460)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Style.width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .screenSaver
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentView = previewView
        setFrame(positionFrame(size: NSSize(width: Style.width, height: height), selectionRect: selectionRect, screen: screen), display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(image: NSImage?, pixelHeight: Int, status: String) {
        previewView.update(image: image, pixelHeight: pixelHeight, status: status)
    }

    func closeIfNeeded() {
        guard !didClose else { return }
        didClose = true
        close()
    }

    private func positionFrame(size: NSSize, selectionRect: CGRect, screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let gap: CGFloat = 14
        let rightX = selectionRect.maxX + gap
        let leftX = selectionRect.minX - gap - size.width
        let x = rightX + size.width <= visible.maxX ? rightX : max(visible.minX + gap, leftX)
        let y = min(max(selectionRect.midY - size.height / 2, visible.minY + gap), visible.maxY - gap - size.height)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

private final class ScrollingPreviewView: NSView {
    private var image: NSImage?
    private var pixelHeight = 0
    private var status = "Capturing..."

    func update(image: NSImage?, pixelHeight: Int, status: String) {
        if let image { self.image = image }
        self.status = status
        self.pixelHeight = pixelHeight
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let panelPath = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        NSColor.black.withAlphaComponent(0.72).setFill()
        panelPath.fill()

        drawHeader()
        drawImage()
    }

    private func drawHeader() {
        let title = status as NSString
        let subtitle = pixelHeight > 0 ? "Height: \(pixelHeight) px" as NSString : "Scroll to capture more" as NSString
        title.draw(at: NSPoint(x: 12, y: bounds.maxY - 28), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ])
        subtitle.draw(at: NSPoint(x: 12, y: bounds.maxY - 48), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.72)
        ])
    }

    private func drawImage() {
        let imageRect = bounds.insetBy(dx: 12, dy: 12)
        let targetBounds = NSRect(x: imageRect.minX, y: imageRect.minY, width: imageRect.width, height: max(40, imageRect.height - 52))
        NSColor.white.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: targetBounds, xRadius: 6, yRadius: 6).fill()

        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(targetBounds.width / image.size.width, targetBounds.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = NSRect(x: targetBounds.midX - size.width / 2, y: targetBounds.maxY - size.height - 8, width: size.width, height: size.height)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

final class ScrollingCaptureControlPanel: NSPanel {
    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?
    private var didClose = false

    init(selectionRect: CGRect, screen: NSScreen) {
        let size = NSSize(width: 198, height: 42)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .screenSaver
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentView = ScrollingCaptureControlView(
            frame: NSRect(origin: .zero, size: size),
            onDone: { [weak self] in self?.onDone?() },
            onCancel: { [weak self] in self?.onCancel?() }
        )
        setFrame(positionFrame(size: size, selectionRect: selectionRect, screen: screen), display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func closeIfNeeded() {
        guard !didClose else { return }
        didClose = true
        close()
    }

    private func positionFrame(size: NSSize, selectionRect: CGRect, screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let gap: CGFloat = 12
        var y = selectionRect.minY - gap - size.height
        if y < visible.minY + gap {
            y = min(selectionRect.maxY + gap, visible.maxY - gap - size.height)
        }
        let x = min(max(selectionRect.midX - size.width / 2, visible.minX + gap), visible.maxX - gap - size.width)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

private final class ScrollingCaptureControlView: NSView {
    private let onDone: () -> Void
    private let onCancel: () -> Void

    init(frame: NSRect, onDone: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onDone = onDone
        self.onCancel = onCancel
        super.init(frame: frame)
        wantsLayer = true

        addButton(title: "x  Cancel", frame: NSRect(x: 0, y: 4, width: 92, height: 34), color: .black, alpha: 0.82, textColor: .white, action: #selector(cancel))
        addButton(title: "OK  Done", frame: NSRect(x: 104, y: 4, width: 92, height: 34), color: .white, alpha: 0.9, textColor: .black, action: #selector(done))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func addButton(title: String, frame: NSRect, color: NSColor, alpha: CGFloat, textColor: NSColor, action: Selector) {
        let button = NSButton(frame: frame)
        button.title = title
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.contentTintColor = textColor
        button.target = self
        button.action = action
        button.wantsLayer = true
        button.layer?.backgroundColor = color.withAlphaComponent(alpha).cgColor
        button.layer?.cornerRadius = frame.height / 2
        addSubview(button)
    }

    @objc private func done() {
        onDone()
    }

    @objc private func cancel() {
        onCancel()
    }
}
