import AppKit
import OSLog

private let editorLogger = Logger(subsystem: "com.ethan.snapnook", category: "ScreenshotEditor")

final class ScreenshotEditorWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let item: ScreenshotPreviewItem
    private let exporter = EditedImageExporter()
    private let editorView: ScreenshotEditorView
    private let undoRedoManager = UndoRedoManager()
    private var selectedTool: EditorTool = .select {
        didSet {
            editorLogger.notice("Editor selected tool: \(self.selectedTool.rawValue, privacy: .public).")
            editorView.toolbarView.updateSelection(selectedTool)
            editorView.toolbarView.updateCropActions(isVisible: selectedTool == .crop)
            editorView.canvasView.selectedTool = selectedTool
        }
    }
    private var annotations: [AnnotationItem] = [] {
        didSet {
            editorView.canvasView.annotations = annotations
            if let selectedAnnotationID, annotations.contains(where: { $0.id == selectedAnnotationID }) == false {
                self.selectedAnnotationID = nil
            }
            updateToolbarState()
        }
    }
    private var selectedAnnotationID: UUID? {
        didSet {
            editorView.canvasView.selectedAnnotationID = selectedAnnotationID
        }
    }

    init(item: ScreenshotPreviewItem) {
        self.item = item
        self.editorView = ScreenshotEditorView(image: item.originalImage)

        let window = NSWindow(
            contentRect: Self.initialFrame(for: item.originalImage),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SnapNook Editor"
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1)
        window.center()
        window.minSize = NSSize(width: 640, height: 420)

        super.init(window: window)

        window.delegate = self
        window.contentView = editorView
        configureActions()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showEditor() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    private func configureActions() {
        editorView.toolbarView.onSelectTool = { [weak self] tool in
            self?.selectTool(tool)
        }
        editorView.toolbarView.onApplyCrop = { [weak self] in
            self?.applyCrop()
        }
        editorView.toolbarView.onCancelCrop = { [weak self] in
            self?.cancelCrop()
        }
        editorView.canvasView.onCommitCommand = { [weak self] command in
            self?.applyAndRecord(command)
        }
        editorView.canvasView.onSelectionChange = { [weak self] selection in
            self?.selectedAnnotationID = selection
        }
        editorView.canvasView.onRequestToolChange = { [weak self] tool in
            self?.selectedTool = tool
        }
        editorView.toolbarView.onSaveAs = { [weak self] in
            self?.saveAs()
        }
        editorView.toolbarView.onDone = { [weak self] in
            self?.close()
        }
        editorView.canvasView.selectedTool = selectedTool
        editorView.toolbarView.updateSelection(selectedTool)
        editorView.toolbarView.updateCropActions(isVisible: selectedTool == .crop)
        editorView.canvasView.annotations = annotations
        editorView.canvasView.selectedAnnotationID = selectedAnnotationID
        updateToolbarState()
    }

    private func undo() {
        editorLogger.notice("Editor undo requested.")
        guard let command = undoRedoManager.undo() else { return }
        applyReversed(command)
        selectedAnnotationID = selectionAfterUndoing(command)
    }

    private func redo() {
        editorLogger.notice("Editor redo requested.")
        guard let command = undoRedoManager.redo() else { return }
        apply(command)
        selectedAnnotationID = selectionAfterRedoing(command)
    }

    private func applyAndRecord(_ command: EditorCommand) {
        editorLogger.notice("Editor command committed.")
        apply(command)
        undoRedoManager.record(command)
        selectedAnnotationID = selectionAfterApplying(command)
        if case .add = command {
            selectedTool = .select
        }
    }

    private func saveAs() {
        guard let window else { return }
        editorLogger.notice("Editor save-as requested.")
        exporter.export(
            originalImage: item.originalImage,
            originalPNGData: item.pngData,
            createdAt: item.createdAt,
            annotations: annotations,
            activeCropRect: editorView.canvasView.activeCropRect,
            from: window
        ) { result in
            switch result {
            case .success(let url):
                editorLogger.notice("Editor image saved to \(url.path, privacy: .public).")
            case .failure(let error):
                editorLogger.error("Editor save-as failed: \(error.localizedDescription, privacy: .public).")
                AlertPresenter.show(message: "Save failed.", informativeText: error.localizedDescription)
            }
        }
    }

    private func updateToolbarState() {
        editorView.toolbarView.updateHistoryButtons(
            canUndo: undoRedoManager.canUndo,
            canRedo: undoRedoManager.canRedo
        )
    }

    private func selectTool(_ tool: EditorTool) {
        if selectedTool == .crop, tool != .crop {
            editorView.canvasView.cancelCropMode()
        }

        if tool == .crop {
            editorView.canvasView.enterCropMode()
        }

        selectedTool = tool
    }

    private func applyCrop() {
        editorView.canvasView.applyCropMode()
        selectedTool = .select
    }

    private func cancelCrop() {
        editorView.canvasView.cancelCropMode()
        selectedTool = .select
    }

    private func apply(_ command: EditorCommand) {
        switch command {
        case .add(let annotation):
            annotations.append(annotation)
        case .update(_, let after):
            replaceAnnotation(after)
        case .delete(let annotation):
            annotations.removeAll { $0.id == annotation.id }
        }
    }

    private func applyReversed(_ command: EditorCommand) {
        switch command {
        case .add(let annotation):
            annotations.removeAll { $0.id == annotation.id }
        case .update(let before, _):
            replaceAnnotation(before)
        case .delete(let annotation):
            annotations.append(annotation)
        }
    }

    private func replaceAnnotation(_ annotation: AnnotationItem) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        annotations[index] = annotation
    }

    private func selectionAfterUndoing(_ command: EditorCommand) -> UUID? {
        switch command {
        case .add:
            return nil
        case .update(let before, _):
            return before.id
        case .delete(let annotation):
            return annotation.id
        }
    }

    private func selectionAfterRedoing(_ command: EditorCommand) -> UUID? {
        switch command {
        case .add(let annotation):
            return annotation.id
        case .update(_, let after):
            return after.id
        case .delete:
            return nil
        }
    }

    private func selectionAfterApplying(_ command: EditorCommand) -> UUID? {
        switch command {
        case .add(let annotation):
            return annotation.id
        case .update(_, let after):
            return after.id
        case .delete:
            return nil
        }
    }

    private static func initialFrame(for image: NSImage) -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxWidth = visibleFrame.width * 0.8
        let maxHeight = visibleFrame.height * 0.8
        let toolbarHeight: CGFloat = 56
        let horizontalPadding: CGFloat = 64
        let verticalPadding: CGFloat = 48

        let imageSize = image.size.width > 0 && image.size.height > 0
            ? image.size
            : NSSize(width: 960, height: 540)

        let availableImageWidth = max(320, maxWidth - horizontalPadding)
        let availableImageHeight = max(240, maxHeight - toolbarHeight - verticalPadding)
        let scale = min(availableImageWidth / imageSize.width, availableImageHeight / imageSize.height, 1)

        let width = min(maxWidth, imageSize.width * scale + horizontalPadding)
        let height = min(maxHeight, imageSize.height * scale + toolbarHeight + verticalPadding)

        return NSRect(x: visibleFrame.midX - width / 2, y: visibleFrame.midY - height / 2, width: width, height: height)
    }
}
