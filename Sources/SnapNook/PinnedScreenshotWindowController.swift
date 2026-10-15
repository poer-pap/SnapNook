import AppKit

final class PinnedScreenshotWindowController: NSWindowController {
    init(item: ScreenshotPreviewItem, screen: NSScreen) {
        let imageSize = item.originalImage.size
        let available = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        let scale = min(1, available.width / max(1, imageSize.width), available.height / max(1, imageSize.height))
        let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let panel = PinnedScreenshotPanel(contentRect: NSRect(
            x: available.midX - size.width / 2, y: available.midY - size.height / 2,
            width: size.width, height: size.height
        ), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = PinnedScreenshotView(image: item.originalImage, size: size, scale: scale)
        panel.setContentSize(size)
        super.init(window: panel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() { window?.orderFrontRegardless() }
}

private final class PinnedScreenshotPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PinnedScreenshotView: NSView {
    private let controls = NSView()
    private var tracking: NSTrackingArea?

    init(image: NSImage, size: NSSize, scale: CGFloat) {
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        let imageView = NSImageView(frame: bounds)
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
        controls.wantsLayer = true
        controls.frame = bounds
        controls.autoresizingMask = [.width, .height]
        controls.isHidden = true
        addSubview(controls)

        let close = icon("xmark", description: "Close", size: NSSize(width: 22, height: 22))
        let lock = icon("lock.open.fill", description: "Lock", size: NSSize(width: 22, height: 22))
        let percentage = NSTextField(labelWithString: "\(Int((scale * 100).rounded()))%")
        percentage.font = .systemFont(ofSize: 12, weight: .bold)
        percentage.textColor = NSColor(white: 0.86, alpha: 1)
        percentage.alignment = .center
        percentage.drawsBackground = false
        percentage.wantsLayer = true
        percentage.layer?.backgroundColor = NSColor(white: 0.18, alpha: 0.9).cgColor
        percentage.layer?.cornerRadius = 10
        percentage.translatesAutoresizingMaskIntoConstraints = false
        // The lower grip, like the other hover controls, is visual only for now.
        let grip = NSStackView(views: [gripLines(), iconImage("doc.fill", description: "Drag window"), gripLines()])
        grip.orientation = .horizontal
        grip.alignment = .centerY
        grip.distribution = .equalSpacing
        grip.edgeInsets = NSEdgeInsets(top: 5, left: 6, bottom: 5, right: 6)
        grip.wantsLayer = true
        grip.layer?.backgroundColor = NSColor(white: 0.82, alpha: 1).cgColor
        grip.layer?.cornerRadius = 5
        grip.translatesAutoresizingMaskIntoConstraints = false
        [close, lock, percentage, grip].forEach { controls.addSubview($0) }
        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: controls.leadingAnchor, constant: 10),
            close.topAnchor.constraint(equalTo: controls.topAnchor, constant: 10),
            lock.trailingAnchor.constraint(equalTo: controls.trailingAnchor, constant: -10),
            lock.topAnchor.constraint(equalTo: controls.topAnchor, constant: 10),
            percentage.centerXAnchor.constraint(equalTo: controls.centerXAnchor),
            percentage.topAnchor.constraint(equalTo: controls.topAnchor, constant: 12),
            percentage.widthAnchor.constraint(equalToConstant: 50),
            percentage.heightAnchor.constraint(equalToConstant: 20),
            grip.centerXAnchor.constraint(equalTo: controls.centerXAnchor),
            grip.bottomAnchor.constraint(equalTo: controls.bottomAnchor, constant: -10),
            grip.widthAnchor.constraint(equalToConstant: 52),
            grip.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
        if let window { controls.isHidden = !bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) }
    }

    override func mouseEntered(with event: NSEvent) { controls.isHidden = false }
    override func mouseExited(with event: NSEvent) { controls.isHidden = true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }

    private func iconImage(_ symbol: String, description: String) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .bold))
        view.contentTintColor = NSColor(white: 0.12, alpha: 1)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func icon(_ symbol: String, description: String, size: NSSize) -> NSView {
        let background = NSView()
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor(white: 0.82, alpha: 1).cgColor
        background.layer?.cornerRadius = size.height / 2
        background.translatesAutoresizingMaskIntoConstraints = false
        let image = iconImage(symbol, description: description)
        background.addSubview(image)
        NSLayoutConstraint.activate([
            background.widthAnchor.constraint(equalToConstant: size.width),
            background.heightAnchor.constraint(equalToConstant: size.height),
            image.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            image.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 12),
            image.heightAnchor.constraint(equalToConstant: 12)
        ])
        return background
    }

    private func gripLines() -> NSTextField {
        let label = NSTextField(labelWithString: "≡")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .gray
        return label
    }
}
