import AppKit

final class EditorToolbarView: NSView {
    var onSelectTool: ((EditorTool) -> Void)?
    var onApplyCrop: (() -> Void)?
    var onCancelCrop: (() -> Void)?
    var onSaveAs: (() -> Void)?
    var onDone: (() -> Void)?

    private var toolButtons: [EditorTool: NSButton] = [:]
    private let cropActionsStack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        layer?.borderWidth = 1

        buildLayout()
        updateSelection(.select)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateSelection(_ tool: EditorTool) {
        for (candidate, button) in toolButtons {
            button.state = candidate == tool ? .on : .off
        }
    }

    func updateHistoryButtons(canUndo: Bool, canRedo: Bool) {}

    func updateCropActions(isVisible: Bool) {
        cropActionsStack.isHidden = isVisible == false
    }

    private func buildLayout() {
        let toolsGroup = ToolGroupView()

        let toolsStack = NSStackView()
        toolsStack.orientation = .horizontal
        toolsStack.alignment = .centerY
        toolsStack.spacing = 0
        toolsStack.translatesAutoresizingMaskIntoConstraints = false

        EditorTool.toolbarTools.enumerated().forEach { index, tool in
            let button = makeToolButton(for: tool, action: #selector(toolTapped(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
            toolButtons[tool] = button
            toolsStack.addArrangedSubview(button)

            if index < EditorTool.toolbarTools.count - 1 {
                toolsStack.addArrangedSubview(ToolSeparatorView())
            }
        }

        cropActionsStack.orientation = .horizontal
        cropActionsStack.spacing = 8
        cropActionsStack.translatesAutoresizingMaskIntoConstraints = false
        cropActionsStack.addArrangedSubview(makeButton(title: "Apply", action: #selector(applyCropTapped)))
        cropActionsStack.addArrangedSubview(makeButton(title: "Cancel", action: #selector(cancelCropTapped)))
        cropActionsStack.isHidden = true

        let actionsStack = NSStackView(views: [
            cropActionsStack,
            makeButton(title: "Save as...", action: #selector(saveAsTapped)),
            makeButton(title: "Done", action: #selector(doneTapped))
        ])
        actionsStack.orientation = .horizontal
        actionsStack.spacing = 8
        actionsStack.translatesAutoresizingMaskIntoConstraints = false

        toolsGroup.addSubview(toolsStack)
        addSubview(toolsGroup)
        addSubview(actionsStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 56),

            toolsGroup.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            toolsGroup.centerYAnchor.constraint(equalTo: centerYAnchor),
            toolsGroup.heightAnchor.constraint(equalToConstant: 36),

            toolsStack.leadingAnchor.constraint(equalTo: toolsGroup.leadingAnchor),
            toolsStack.trailingAnchor.constraint(equalTo: toolsGroup.trailingAnchor),
            toolsStack.topAnchor.constraint(equalTo: toolsGroup.topAnchor),
            toolsStack.bottomAnchor.constraint(equalTo: toolsGroup.bottomAnchor),

            actionsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            actionsStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            actionsStack.leadingAnchor.constraint(greaterThanOrEqualTo: toolsGroup.trailingAnchor, constant: 16)
        ])
    }

    private func makeToolButton(for tool: EditorTool, action: Selector) -> NSButton {
        let button = SegmentedToolButton(image: tool.symbolImage, target: self, action: action)
        button.toolTip = tool.rawValue
        button.setButtonType(.toggle)
        return button
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    @objc private func toolTapped(_ sender: NSButton) {
        guard
            let identifier = sender.identifier?.rawValue,
            let tool = EditorTool(rawValue: identifier)
        else {
            return
        }

        updateSelection(tool)
        onSelectTool?(tool)
    }

    @objc private func saveAsTapped() {
        onSaveAs?()
    }

    @objc private func applyCropTapped() {
        onApplyCrop?()
    }

    @objc private func cancelCropTapped() {
        onCancelCrop?()
    }

    @objc private func doneTapped() {
        onDone?()
    }
}

private final class ToolGroupView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.28, alpha: 1).cgColor
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class ToolSeparatorView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        widthAnchor.constraint(equalToConstant: 1).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class SegmentedToolButton: NSButton {
    override var state: NSControl.StateValue {
        didSet {
            updateAppearance()
        }
    }

    init(image: NSImage, target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.image = image
        self.target = target
        self.action = action
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        contentTintColor = .white
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true

        widthAnchor.constraint(equalToConstant: 48).isActive = true
        heightAnchor.constraint(equalToConstant: 36).isActive = true
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func updateAppearance() {
        layer?.backgroundColor = state == .on
            ? NSColor.systemBlue.cgColor
            : NSColor.clear.cgColor
        contentTintColor = .white
    }
}

private extension EditorTool {
    var symbolImage: NSImage {
        let symbolName: String
        switch self {
        case .select:
            symbolName = "cursorarrow"
        case .crop:
            symbolName = "crop"
        case .arrow:
            symbolName = "arrow.down.left"
        case .rectangle:
            symbolName = "rectangle"
        case .text:
            symbolName = "textformat"
        case .highlight:
            symbolName = "rectangle.inset.filled"
        case .blur:
            symbolName = "drop"
        case .mosaic:
            symbolName = "square.grid.3x3"
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: rawValue) {
            return image
        }

        return NSImage(size: NSSize(width: 18, height: 18))
    }
}
