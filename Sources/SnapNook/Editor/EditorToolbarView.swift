import AppKit

final class EditorToolbarView: NSView {
    var onSelectTool: ((EditorTool) -> Void)?
    var onSaveAs: (() -> Void)?
    var onDone: (() -> Void)?

    private var toolButtons: [EditorTool: NSButton] = [:]

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

    private func buildLayout() {
        let toolsStack = NSStackView()
        toolsStack.orientation = .horizontal
        toolsStack.spacing = 8
        toolsStack.translatesAutoresizingMaskIntoConstraints = false

        EditorTool.toolbarTools.forEach { tool in
            let button = makeToggleButton(title: tool.rawValue, action: #selector(toolTapped(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
            toolButtons[tool] = button
            toolsStack.addArrangedSubview(button)
        }

        let actionsStack = NSStackView(views: [
            makeButton(title: "Save as...", action: #selector(saveAsTapped)),
            makeButton(title: "Done", action: #selector(doneTapped))
        ])
        actionsStack.orientation = .horizontal
        actionsStack.spacing = 8
        actionsStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(toolsStack)
        addSubview(actionsStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 56),

            toolsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            toolsStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            actionsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            actionsStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            actionsStack.leadingAnchor.constraint(greaterThanOrEqualTo: toolsStack.trailingAnchor, constant: 16)
        ])
    }

    private func makeToggleButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.setButtonType(.toggle)
        button.bezelStyle = .rounded
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

    @objc private func doneTapped() {
        onDone?()
    }
}
