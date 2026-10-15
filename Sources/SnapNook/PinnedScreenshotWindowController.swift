import AppKit

final class PinnedScreenshotWindowController: NSWindowController {
    var onClose: (() -> Void)?
    private(set) var isClosed = false

    init(item: ScreenshotPreviewItem, screen: NSScreen) {
        let available = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        let size = item.originalImage.size
        let scale = min(1, available.width / max(1, size.width), available.height / max(1, size.height))
        let view = PinnedScreenshotView(item: item, scale: scale)
        let contentSize = view.bounds.size
        let panel = PinnedScreenshotPanel(contentRect: NSRect(
            x: available.midX - view.bounds.width / 2, y: available.midY - view.bounds.height / 2,
            width: view.bounds.width, height: view.bounds.height
        ), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = view
        panel.setContentSize(contentSize)
        super.init(window: panel)
        view.onClose = { [weak self] in self?.closePinned() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() { if !isClosed { window?.orderFrontRegardless() } }

    private func closePinned() {
        guard !isClosed else { return }
        isClosed = true
        window?.orderOut(nil)
        // Release controller ownership only after the mouse callback has returned.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.close()
            self.onClose?()
        }
    }
}

private final class PinnedScreenshotPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PinnedScreenshotView: NSView, NSDraggingSource {
    var onClose: (() -> Void)?
    var onDragStarted: (() -> Void)?
    var onDragEnded: (() -> Void)?
    private(set) var isLocked = false
    private(set) var scale: CGFloat
    private(set) var isHovering = false
    private let item: ScreenshotPreviewItem
    private var tracking: NSTrackingArea?
    private var dragStart: NSPoint?
    private var dragSession: NSDraggingSession?
    private var temporaryFileURL: URL?
    private var keepTemporaryFile = false
    private let imageView = NSImageView()
    private let closeButton = PinnedControlButton()
    private let lockButton = PinnedControlButton()
    private let percentage = NSTextField(labelWithString: "")
    private let grip = PinnedFileGrip()

    init(item: ScreenshotPreviewItem, scale: CGFloat) {
        self.item = item
        self.scale = scale
        // A minimum control footprint keeps Close reachable even for very thin images.
        let size = NSSize(width: max(96, item.image.size.width * scale), height: max(64, item.image.size.height * scale))
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        imageView.image = item.image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)
        configure(closeButton, symbol: "xmark", label: "Close", action: #selector(closeTapped))
        configure(lockButton, symbol: "lock.open.fill", label: "Lock", action: #selector(lockTapped))
        percentage.font = .systemFont(ofSize: 12, weight: .bold)
        percentage.textColor = NSColor(white: 0.86, alpha: 1)
        percentage.alignment = .center
        percentage.wantsLayer = true
        percentage.layer?.backgroundColor = NSColor(white: 0.18, alpha: 0.9).cgColor
        percentage.layer?.cornerRadius = 10
        grip.wantsLayer = true
        grip.setAccessibilityElement(true)
        grip.setAccessibilityLabel("Drag screenshot file")
        [closeButton, lockButton, percentage, grip].forEach { addSubview($0) }
        needsLayout = true
        updateControls()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if !keepTemporaryFile, let temporaryFileURL {
            try? FileManager.default.removeItem(at: temporaryFileURL.deletingLastPathComponent())
        }
    }

    override func layout() {
        super.layout()
        let size = NSSize(width: item.image.size.width * scale, height: item.image.size.height * scale)
        imageView.frame = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                                 width: size.width, height: size.height)
        closeButton.frame = NSRect(x: 10, y: bounds.height - 32, width: 22, height: 22)
        lockButton.frame = NSRect(x: bounds.width - 32, y: bounds.height - 32, width: 22, height: 22)
        percentage.frame = NSRect(x: bounds.midX - 25, y: bounds.height - 32, width: 50, height: 20)
        grip.frame = NSRect(x: bounds.midX - 26, y: 10, width: 52, height: 23)
        updateControls()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
        if let window {
            isHovering = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
            updateControls()
        }
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true; updateControls() }
    override func mouseExited(with event: NSEvent) { isHovering = false; updateControls() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit === closeButton || hit === lockButton { return hit }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard !isLocked, dragSession == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        if !grip.isHidden, grip.frame.contains(point) { dragStart = point }
        else { window?.performDrag(with: event) }
    }

    override func mouseUp(with event: NSEvent) { dragStart = nil }

    override func mouseDragged(with event: NSEvent) {
        guard !isLocked, dragSession == nil, let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) >= 4 else { return }
        dragStart = nil
        do {
            let pasteboard = NSPasteboardItem()
            pasteboard.setData(item.pngData, forType: .png)
            if let tiff = item.image.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
            pasteboard.setString(try dragFileURL().absoluteString, forType: .fileURL)
            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboard)
            let factor = 128 / max(item.image.size.width, item.image.size.height)
            let size = NSSize(width: item.image.size.width * factor, height: item.image.size.height * factor)
            draggingItem.setDraggingFrame(NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                                width: size.width, height: size.height), contents: item.image)
            onDragStarted?()
            let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
        } catch {
            AlertPresenter.show(message: "Drag failed.", informativeText: error.localizedDescription)
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) { dragSession = session }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard dragSession != nil else { return }
        dragSession = nil
        keepTemporaryFile = keepTemporaryFile || !operation.isEmpty
        onDragEnded?()
        if !operation.isEmpty { onClose?() }
    }

    func dragFileURL() throws -> URL {
        let url = temporaryFileURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapNook-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(ScreenshotWriter.filename(createdAt: item.createdAt))
        temporaryFileURL = url
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try item.pngData.write(to: url, options: .atomic)
        }
        return url
    }

    override func scrollWheel(with event: NSEvent) {
        guard !isLocked, dragSession == nil, event.scrollingDeltaY != 0 else { return }
        let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.005 : 0.05
        resize(to: scale * exp(max(-1, min(1, event.scrollingDeltaY * sensitivity))))
    }

    func resize(to requestedScale: CGFloat) {
        guard !isLocked, requestedScale.isFinite, let window, let screen = window.screen ?? NSScreen.screens.first else { return }
        let available = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        let imageSize = item.image.size
        let maximum = min(4, available.width / max(1, imageSize.width), available.height / max(1, imageSize.height))
        let minimum = min(maximum, max(0.1, 96 / max(1, imageSize.width), 64 / max(1, imageSize.height)))
        scale = min(maximum, max(minimum, requestedScale))
        let size = NSSize(width: max(96, imageSize.width * scale), height: max(64, imageSize.height * scale))
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        let origin = NSPoint(x: max(available.minX, min(available.maxX - size.width, center.x - size.width / 2)),
                             y: max(available.minY, min(available.maxY - size.height, center.y - size.height / 2)))
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        needsLayout = true
        needsDisplay = true
        updateControls()
    }

    private func updateControls() {
        let compact = bounds.width < 140 || bounds.height < 100
        closeButton.isHidden = isLocked || (!isHovering && !compact)
        lockButton.isHidden = !isLocked && !isHovering
        percentage.isHidden = isLocked || !isHovering || compact
        grip.isHidden = isLocked || !isHovering || compact
        percentage.stringValue = "\(Int((scale * 100).rounded()))%"
    }

    @objc private func closeTapped() { if dragSession == nil { onClose?() } }
    @objc private func lockTapped() {
        guard dragSession == nil else { return }
        isLocked.toggle()
        window?.isMovable = !isLocked
        lockButton.image = symbol(isLocked ? "lock.fill" : "lock.open.fill")
        lockButton.toolTip = isLocked ? "Unlock" : "Lock"
        lockButton.setAccessibilityLabel(lockButton.toolTip)
        updateControls()
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: name == "xmark" ? 9 : 11, weight: .bold))
    }

    private func configure(_ button: NSButton, symbol name: String, label: String, action: Selector) {
        button.isBordered = false
        button.title = ""
        button.image = symbol(name)
        button.imagePosition = .imageOnly
        button.contentTintColor = NSColor(white: 0.12, alpha: 1)
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor(white: 0.82, alpha: 1).cgColor
        button.layer?.cornerRadius = 11
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }
}

private final class PinnedControlButton: NSButton {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class PinnedFileGrip: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.82, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        // Reference proportions: three separated thin lines on each side of a document.
        NSColor(white: 0.57, alpha: 1).setStroke()
        let lines = NSBezierPath()
        lines.lineWidth = 0.8
        for x: CGFloat in [7, 40] {
            for y: CGFloat in [7, 11.5, 16] {
                lines.move(to: NSPoint(x: x, y: y))
                lines.line(to: NSPoint(x: x + 5, y: y))
            }
        }
        lines.stroke()
        let document = NSImage(systemSymbolName: "doc.fill", accessibilityDescription: "Drag screenshot file")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        NSColor(white: 0.22, alpha: 1).set()
        if let document {
            let tinted = NSImage(size: document.size, flipped: false) { rect in
                document.draw(in: rect)
                NSColor(white: 0.22, alpha: 1).setFill()
                rect.fill(using: .sourceIn)
                return true
            }
            tinted.draw(in: NSRect(x: 21.5, y: 5.5, width: 9, height: 12))
        }
    }
}
