import AppKit

final class ScreenshotPreviewView: NSView {
    var onEdit: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private let imageView = NSImageView()
    private let materialView = NSVisualEffectView()
    private let controlsView = NSView()
    private var trackingArea: NSTrackingArea?
    private let cornerRadius: CGFloat = 18

    init(image: NSImage) {
        super.init(frame: NSRect(origin: .zero, size: ScreenshotPreviewPanel.previewPanelSize))
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.18).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        layer?.borderWidth = 1

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        materialView.translatesAutoresizingMaskIntoConstraints = false
        materialView.blendingMode = .withinWindow
        materialView.state = .active
        materialView.material = .hudWindow
        materialView.isHidden = true
        addSubview(materialView)

        controlsView.wantsLayer = true
        controlsView.layer?.backgroundColor = NSColor.clear.cgColor
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        controlsView.isHidden = true
        addSubview(controlsView)

        addControls()

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: ScreenshotPreviewPanel.previewPanelSize.width),
            heightAnchor.constraint(equalToConstant: ScreenshotPreviewPanel.previewPanelSize.height),

            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            materialView.leadingAnchor.constraint(equalTo: leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: trailingAnchor),
            materialView.topAnchor.constraint(equalTo: topAnchor),
            materialView.bottomAnchor.constraint(equalTo: bottomAnchor),

            controlsView.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlsView.topAnchor.constraint(equalTo: topAnchor),
            controlsView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        ScreenshotPreviewPanel.previewPanelSize
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        materialView.isHidden = false
        controlsView.isHidden = false
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        materialView.isHidden = true
        controlsView.isHidden = true
        onHoverChanged?(false)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func addControls() {
        let editButton = makeButton(title: "Edit", action: #selector(editTapped))
        let copyButton = makeButton(title: "Copy", action: #selector(copyTapped))
        let saveButton = makeButton(title: "Save", action: #selector(saveTapped))
        let closeButton = makeIconButton(symbolName: "xmark", fallbackTitle: "x", action: #selector(closeTapped))
        closeButton.toolTip = "Close"

        let stack = NSStackView(views: [copyButton, saveButton])
        stack.orientation = NSUserInterfaceLayoutOrientation.vertical
        stack.spacing = 10
        stack.alignment = NSLayoutConstraint.Attribute.centerX
        stack.translatesAutoresizingMaskIntoConstraints = false

        [stack, closeButton].forEach { controlsView.addSubview($0) }
        controlsView.addSubview(editButton)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: controlsView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: controlsView.centerYAnchor),

            closeButton.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: 12),
            closeButton.topAnchor.constraint(equalTo: controlsView.topAnchor, constant: 12),

            editButton.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: 12),
            editButton.bottomAnchor.constraint(equalTo: controlsView.bottomAnchor, constant: -12)
        ])
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    private func makeIconButton(symbolName: String, fallbackTitle: String, action: Selector) -> NSButton {
        let button = NSButton(title: fallbackTitle, target: self, action: action)
        button.bezelStyle = .circular
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: fallbackTitle) {
            button.image = image
            button.title = ""
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return button
    }

    @objc private func editTapped() {
        onEdit?()
    }

    @objc private func copyTapped() {
        onCopy?()
    }

    @objc private func saveTapped() {
        onSave?()
    }

    @objc private func closeTapped() {
        onClose?()
    }
}
