import AppKit

final class ScreenshotEditorView: NSView {
    let toolbarView = EditorToolbarView()
    let canvasView: EditorCanvasView

    init(image: NSImage) {
        self.canvasView = EditorCanvasView(image: image)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1).cgColor

        addSubview(toolbarView)
        addSubview(canvasView)

        NSLayoutConstraint.activate([
            toolbarView.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbarView.topAnchor.constraint(equalTo: topAnchor),

            canvasView.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvasView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            canvasView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
