import AppKit
import QuartzCore

final class ScreenshotPreviewView: NSView, NSDraggingSource {
    var onEdit: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?
    var onDragStarted: (() -> Void)?
    var onDragEnded: ((Bool) -> Void)?
    var isEnabled = true

    private let item: ScreenshotPreviewItem
    private let imageView = NSImageView()
    private let materialView = NSVisualEffectView()
    private let controlsView = NSView()
    private var trackingArea: NSTrackingArea?
    private var mouseDownPoint: NSPoint?
    private var dragSession: NSDraggingSession?
    private var temporaryFileURL: URL?
    private var keepTemporaryFile = false

    init(item: ScreenshotPreviewItem) {
        self.item = item
        super.init(frame: NSRect(origin: .zero, size: ScreenshotPreviewPanel.previewPanelSize))
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.3
        layer?.shadowRadius = 7
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 18, cornerHeight: 18, transform: nil)

        let content = NSView(frame: bounds)
        content.wantsLayer = true
        content.layer?.cornerRadius = 18
        content.layer?.masksToBounds = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.18).cgColor
        content.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        content.layer?.borderWidth = 1
        addSubview(content)

        imageView.image = item.image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.frame = content.bounds
        content.addSubview(imageView)

        materialView.frame = content.bounds
        materialView.blendingMode = .withinWindow
        materialView.state = .active
        materialView.material = .hudWindow
        materialView.appearance = NSAppearance(named: .darkAqua)
        materialView.alphaValue = 0
        content.addSubview(materialView)

        controlsView.frame = content.bounds
        controlsView.alphaValue = 0
        content.addSubview(controlsView)
        addControls()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if !keepTemporaryFile, let temporaryFileURL {
            try? FileManager.default.removeItem(at: temporaryFileURL.deletingLastPathComponent())
        }
    }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
        if let window {
            setHover(bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)))
        }
    }

    override func mouseEntered(with event: NSEvent) { setHover(true) }
    override func mouseExited(with event: NSEvent) { setHover(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled, let hit = super.hitTest(point) else { return nil }
        if controlsView.alphaValue > 0.5 {
            var view: NSView? = hit
            while let current = view, current !== self {
                if current is NSButton { return current }
                view = current.superview
            }
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseUp(with event: NSEvent) { mouseDownPoint = nil }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, dragSession == nil, let start = mouseDownPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) >= 4 else { return }
        do {
            let url = try dragFileURL()
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setData(item.pngData, forType: .png)
            if let tiff = item.image.tiffRepresentation { pasteboardItem.setData(tiff, forType: .tiff) }
            pasteboardItem.setString(url.absoluteString, forType: .fileURL)
            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
            let imageSize = item.image.size
            let scale = 128 / max(imageSize.width, imageSize.height)
            let previewSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
            draggingItem.setDraggingFrame(NSRect(x: point.x - previewSize.width / 2, y: point.y - previewSize.height / 2,
                                                width: previewSize.width, height: previewSize.height), contents: item.image)
            mouseDownPoint = nil
            onDragStarted?()
            let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
        } catch {
            mouseDownPoint = nil
            AlertPresenter.show(message: "Drag failed.", informativeText: error.localizedDescription)
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        dragSession = session
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard dragSession != nil else { return }
        dragSession = nil
        let accepted = !operation.isEmpty
        keepTemporaryFile = accepted
        onDragEnded?(accepted)
    }

    func animateAppearance() {
        guard let layer else { return }
        let slide = CASpringAnimation(keyPath: "transform.translation.x")
        slide.fromValue = -frame.maxX
        slide.toValue = 0
        slide.mass = 1
        slide.stiffness = 350
        slide.damping = 25
        slide.duration = 0.3
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.3
        layer.add(slide, forKey: "appearSlide")
        layer.add(fade, forKey: "appearFade")
    }

    private func dragFileURL() throws -> URL {
        let url: URL
        if let temporaryFileURL {
            url = temporaryFileURL
        } else {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("SnapNook-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent(ScreenshotWriter.filename(createdAt: item.createdAt))
            temporaryFileURL = url
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try item.pngData.write(to: url, options: .atomic)
        }
        return url
    }

    private func setHover(_ hovering: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            materialView.animator().alphaValue = hovering ? 1 : 0
            controlsView.animator().alphaValue = hovering ? 1 : 0
        }
    }

    private func addControls() {
        let copyButton = makeButton(title: "Copy", action: #selector(copyTapped))
        let saveButton = makeButton(title: "Save", action: #selector(saveTapped))
        let closeButton = makeIconButton(symbolName: "xmark", title: "Close", action: #selector(closeTapped))
        let editButton = makeIconButton(symbolName: "pencil", title: "Edit", action: #selector(editTapped))
        let stack = NSStackView(views: [copyButton, saveButton])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        [stack, closeButton, editButton].forEach { controlsView.addSubview($0) }
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: controlsView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: controlsView.centerYAnchor),
            closeButton.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: 6),
            closeButton.topAnchor.constraint(equalTo: controlsView.topAnchor, constant: 6),
            editButton.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: 6),
            editButton.bottomAnchor.constraint(equalTo: controlsView.bottomAnchor, constant: -6)
        ])
    }

    private func makeButton(title: String, action: Selector, size: NSSize = NSSize(width: 54, height: 28)) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.font = .systemFont(ofSize: 14, weight: .medium)
        button.contentTintColor = .black
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor(white: 0.82, alpha: 1).cgColor
        button.layer?.cornerRadius = size.height / 2
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: size.width).isActive = true
        button.heightAnchor.constraint(equalToConstant: size.height).isActive = true
        return button
    }

    private func makeIconButton(symbolName: String, title: String, action: Selector) -> NSButton {
        let button = makeButton(title: "", action: action, size: NSSize(width: 24, height: 24))
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = title
        button.setAccessibilityLabel(title)
        return button
    }

    @objc private func editTapped() { if isEnabled { onEdit?() } }
    @objc private func copyTapped() { if isEnabled { onCopy?() } }
    @objc private func saveTapped() { if isEnabled { onSave?() } }
    @objc private func closeTapped() { if isEnabled { onClose?() } }
}
