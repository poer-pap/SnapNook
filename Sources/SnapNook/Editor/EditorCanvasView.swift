import AppKit
import Foundation

final class EditorCanvasView: NSView, NSTextViewDelegate {
    var selectedTool: EditorTool = .select {
        didSet {
            if case .editingText = interactionState, selectedTool != .text, selectedTool != .select {
                finishActiveTextEditing(commit: true)
            }
            updateCursor(for: lastMouseLocationInView)
        }
    }
    var annotations: [AnnotationItem] = [] {
        didSet {
            if let selectedAnnotationID, annotations.contains(where: { $0.id == selectedAnnotationID }) == false {
                self.selectedAnnotationID = nil
            }
            syncTextEditorFrameIfNeeded()
            needsDisplay = true
        }
    }
    var selectedAnnotationID: UUID? {
        didSet {
            needsDisplay = true
            syncTextEditorFrameIfNeeded()
            updateCursor(for: lastMouseLocationInView)
        }
    }
    var onCommitCommand: ((EditorCommand) -> Void)?
    var onSelectionChange: ((UUID?) -> Void)?

    private let image: NSImage
    private let imageCGImage: CGImage?
    private let imageSize: CGSize
    private let imageEffectProcessor: ImageEffectProcessor?
    private var trackingArea: NSTrackingArea?
    private var interactionState: EditorInteractionState = .idle
    private var previewAnnotation: AnnotationItem? {
        didSet {
            needsDisplay = true
        }
    }
    private var activeTextEdit: ActiveTextEdit?
    private var lastMouseLocationInView: CGPoint = .zero
    private let debugLoggingEnabled = true

    init(image: NSImage) {
        self.image = image
        self.imageCGImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        self.imageSize = Self.imagePixelSize(for: image)
        if let cgImage = self.imageCGImage {
            self.imageEffectProcessor = ImageEffectProcessor(sourceImage: cgImage)
        } else {
            self.imageEffectProcessor = nil
        }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        dirtyRect.fill()

        let transform = canvasTransform
        let displayedImageRect = transform.displayedImageRect
        guard displayedImageRect.width > 0, displayedImageRect.height > 0 else { return }

        image.draw(
            in: displayedImageRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let visibleAnnotations = annotationsForDisplay()
        imageEffectProcessor?.drawPreviewEffects(
            for: visibleAnnotations,
            displayedImageRect: displayedImageRect,
            transform: transform
        )
        AnnotationRenderer.draw(annotations: visibleAnnotations, in: context, transform: transform)

        if let annotation = selectedAnnotationForDisplay() {
            AnnotationRenderer.drawSelection(for: annotation, in: context, transform: transform)
        }

        if let previewAnnotation, isDrawingEffectPreview(previewAnnotation) {
            let rect = previewAnnotation.blur?.rect ?? previewAnnotation.mosaic?.rect
            if let rect {
                AnnotationRenderer.drawDraftRect(rect, in: context, transform: transform)
            }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        lastMouseLocationInView = viewPoint
        updateCursor(for: viewPoint)
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        let viewPoint = convert(event.locationInWindow, from: nil)
        lastMouseLocationInView = viewPoint
        log("mouseDown point=\(debugPoint(viewPoint)) tool=\(selectedTool.rawValue) displayedImageRect=\(debugRect(canvasTransform.displayedImageRect)) annotations=\(annotations.count)")

        if case .editingText = interactionState {
            if activeTextEdit?.textView.frame.contains(viewPoint) == true {
                window?.makeFirstResponder(activeTextEdit?.textView)
                return
            }

            finishActiveTextEditing(commit: true)
            return
        }

        switch selectedTool {
        case .rectangle:
            beginDrawingRectangle(at: viewPoint)
        case .arrow:
            beginDrawingArrow(at: viewPoint)
        case .highlight:
            beginDrawingHighlight(at: viewPoint)
        case .blur:
            beginDrawingBlur(at: viewPoint)
        case .mosaic:
            beginDrawingMosaic(at: viewPoint)
        case .text:
            beginTextCreation(at: viewPoint)
        case .select:
            beginSelectionInteraction(at: viewPoint, clickCount: event.clickCount)
        default:
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        lastMouseLocationInView = viewPoint
        updateInteractionPreview(with: viewPoint)
        updateCursor(for: viewPoint)
    }

    override func mouseUp(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        lastMouseLocationInView = viewPoint
        commitInteraction(at: viewPoint)
        updateCursor(for: viewPoint)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == KeyCode.deleteKey || event.keyCode == KeyCode.forwardDeleteKey {
            deleteSelectedAnnotationIfNeeded()
            return
        }

        if event.keyCode == KeyCode.returnKey || event.keyCode == KeyCode.enterKey {
            guard
                selectedTool == .select,
                let selectedAnnotationID,
                let annotation = annotations.first(where: { $0.id == selectedAnnotationID }),
                let text = annotation.text
            else {
                super.keyDown(with: event)
                return
            }

            beginEditingExistingText(text)
            return
        }

        super.keyDown(with: event)
    }

    override func layout() {
        super.layout()
        syncTextEditorFrameIfNeeded()
        needsDisplay = true
    }

    func textDidChange(_ notification: Notification) {
        syncTextEditorFrameIfNeeded()
        needsDisplay = true
    }

    private var canvasTransform: CanvasTransform {
        CanvasTransform(imageSize: imageSize, containerRect: bounds.insetBy(dx: 32, dy: 24))
    }

    private func annotationsForDisplay() -> [AnnotationItem] {
        var visibleAnnotations = annotations

        if let activeTextEdit, case .editingText(let id) = interactionState, id == activeTextEdit.id {
            visibleAnnotations.removeAll { $0.id == activeTextEdit.id }
        }

        guard let previewAnnotation else {
            return visibleAnnotations
        }

        visibleAnnotations.removeAll { $0.id == previewAnnotation.id }
        visibleAnnotations.append(previewAnnotation)
        return visibleAnnotations
    }

    private func selectedAnnotationForDisplay() -> AnnotationItem? {
        if let activeTextEdit, case .editingText(let id) = interactionState, id == activeTextEdit.id {
            return .text(TextAnnotation(
                id: activeTextEdit.id,
                text: activeTextEdit.textView.string,
                rect: activeTextEdit.rect,
                fontSize: activeTextEdit.originalAnnotation?.fontSize ?? Metrics.defaultTextFontSize,
                color: activeTextEdit.originalAnnotation?.color ?? .systemRed,
                fontName: activeTextEdit.originalAnnotation?.fontName
            ))
        }

        guard let selectedAnnotationID else { return nil }

        if let previewAnnotation, previewAnnotation.id == selectedAnnotationID {
            return previewAnnotation
        }

        return annotations.first(where: { $0.id == selectedAnnotationID })
    }

    private func beginDrawingRectangle(at viewPoint: CGPoint) {
        guard let imagePoint = canvasTransform.viewPointToImagePoint(viewPoint) else {
            log("beginDrawingRectangle ignored point outside image: \(debugPoint(viewPoint))")
            return
        }

        let annotation = AnnotationItem.rectangle(RectangleAnnotation(rect: CGRect(origin: imagePoint, size: .zero)))
        setInteractionState(.drawingRectangle(start: imagePoint, current: imagePoint))
        previewAnnotation = annotation
    }

    private func beginDrawingArrow(at viewPoint: CGPoint) {
        guard let imagePoint = canvasTransform.viewPointToImagePoint(viewPoint) else {
            log("beginDrawingArrow ignored point outside image: \(debugPoint(viewPoint))")
            return
        }

        let annotation = AnnotationItem.arrow(ArrowAnnotation(startPoint: imagePoint, endPoint: imagePoint))
        setInteractionState(.drawingArrow(start: imagePoint, current: imagePoint))
        previewAnnotation = annotation
    }

    private func beginDrawingHighlight(at viewPoint: CGPoint) {
        guard let imagePoint = canvasTransform.viewPointToImagePoint(viewPoint) else {
            log("beginDrawingHighlight ignored point outside image: \(debugPoint(viewPoint))")
            return
        }

        let annotation = AnnotationItem.highlight(HighlightAnnotation(rect: CGRect(origin: imagePoint, size: .zero)))
        setInteractionState(.drawingHighlight(start: imagePoint, current: imagePoint))
        previewAnnotation = annotation
    }

    private func beginTextCreation(at viewPoint: CGPoint) {
        guard let imagePoint = canvasTransform.viewPointToImagePoint(viewPoint) else {
            log("beginTextCreation ignored point outside image: \(debugPoint(viewPoint))")
            return
        }

        let defaultRect = clampedRect(CGRect(origin: imagePoint, size: Metrics.defaultTextBounds))
        beginEditingText(
            id: UUID(),
            text: "",
            rect: defaultRect,
            originalAnnotation: nil
        )
    }

    private func beginDrawingBlur(at viewPoint: CGPoint) {
        guard let imagePoint = canvasTransform.viewPointToImagePoint(viewPoint) else {
            log("beginDrawingBlur ignored point outside image: \(debugPoint(viewPoint))")
            return
        }

        let annotation = AnnotationItem.blur(BlurAnnotation(rect: CGRect(origin: imagePoint, size: .zero)))
        setInteractionState(.drawingBlur(start: imagePoint, current: imagePoint))
        previewAnnotation = annotation
    }

    private func beginDrawingMosaic(at viewPoint: CGPoint) {
        guard let imagePoint = canvasTransform.viewPointToImagePoint(viewPoint) else {
            log("beginDrawingMosaic ignored point outside image: \(debugPoint(viewPoint))")
            return
        }

        let annotation = AnnotationItem.mosaic(MosaicAnnotation(rect: CGRect(origin: imagePoint, size: .zero)))
        setInteractionState(.drawingMosaic(start: imagePoint, current: imagePoint))
        previewAnnotation = annotation
    }

    private func beginSelectionInteraction(at viewPoint: CGPoint, clickCount: Int) {
        let hit = hitTestAnnotation(at: viewPoint, transform: canvasTransform)
        log("hitTest result=\(String(describing: hit)) selected=\(String(describing: selectedAnnotationID))")

        guard let hit else {
            setInteractionState(.idle)
            previewAnnotation = nil
            notifySelectionChange(nil)
            return
        }

        if clickCount >= 2,
           case .textBody(let id) = hit,
           let annotation = annotations.first(where: { $0.id == id }),
           let text = annotation.text {
            beginEditingExistingText(text)
            return
        }

        notifySelectionChange(hit.annotationID)

        switch hit {
        case .rectangleHandle(let id, let handle):
            guard let annotation = annotations.first(where: { $0.id == id }), let rectangle = annotation.rectangle else {
                setInteractionState(.idle)
                return
            }
            setInteractionState(.resizingRectangle(
                id: id,
                handle: handle,
                startMouse: viewPoint,
                originalRect: rectangle.rect
            ))
        case .textHandle(let id, let handle):
            guard let annotation = annotations.first(where: { $0.id == id }), let text = annotation.text else {
                setInteractionState(.idle)
                return
            }
            setInteractionState(.resizingText(
                id: id,
                handle: handle,
                startMouse: viewPoint,
                originalRect: text.rect
            ))
        case .rectangleBody(let id), .arrowBody(let id), .textBody(let id), .highlightBody(let id), .blurBody(let id), .mosaicBody(let id):
            guard let annotation = annotations.first(where: { $0.id == id }) else {
                setInteractionState(.idle)
                return
            }
            setInteractionState(.movingAnnotation(
                id: id,
                startMouse: viewPoint,
                originalAnnotation: annotation
            ))
        case .arrowEndpoint(let id, let endpoint):
            guard let annotation = annotations.first(where: { $0.id == id }), let arrow = annotation.arrow else {
                setInteractionState(.idle)
                return
            }
            setInteractionState(.editingArrowEndpoint(
                id: id,
                endpoint: endpoint,
                startMouse: viewPoint,
                originalArrow: arrow
            ))
        case .highlightHandle(let id, let handle):
            guard let annotation = annotations.first(where: { $0.id == id }), let highlight = annotation.highlight else {
                setInteractionState(.idle)
                return
            }
            setInteractionState(.resizingHighlight(
                id: id,
                handle: handle,
                startMouse: viewPoint,
                originalRect: highlight.rect
            ))
        case .blurHandle(let id, let handle):
            guard let annotation = annotations.first(where: { $0.id == id }), let blur = annotation.blur else {
                setInteractionState(.idle)
                return
            }
            setInteractionState(.resizingBlur(
                id: id,
                handle: handle,
                startMouse: viewPoint,
                originalRect: blur.rect
            ))
        case .mosaicHandle(let id, let handle):
            guard let annotation = annotations.first(where: { $0.id == id }), let mosaic = annotation.mosaic else {
                setInteractionState(.idle)
                return
            }
            setInteractionState(.resizingMosaic(
                id: id,
                handle: handle,
                startMouse: viewPoint,
                originalRect: mosaic.rect
            ))
        }
    }

    private func updateInteractionPreview(with viewPoint: CGPoint) {
        switch interactionState {
        case .idle, .editingText:
            return
        case .drawingRectangle(let start, _):
            let current = canvasTransform.clampedImagePoint(fromViewPoint: viewPoint)
            setInteractionState(.drawingRectangle(start: start, current: current))
            previewAnnotation = .rectangle(RectangleAnnotation(rect: normalizedRect(from: start, to: current)))
        case .drawingArrow(let start, _):
            let current = canvasTransform.clampedImagePoint(fromViewPoint: viewPoint)
            setInteractionState(.drawingArrow(start: start, current: current))
            previewAnnotation = .arrow(ArrowAnnotation(startPoint: start, endPoint: current))
        case .drawingHighlight(let start, _):
            let current = canvasTransform.clampedImagePoint(fromViewPoint: viewPoint)
            setInteractionState(.drawingHighlight(start: start, current: current))
            previewAnnotation = .highlight(HighlightAnnotation(rect: normalizedRect(from: start, to: current)))
        case .drawingBlur(let start, _):
            let current = canvasTransform.clampedImagePoint(fromViewPoint: viewPoint)
            setInteractionState(.drawingBlur(start: start, current: current))
            previewAnnotation = .blur(BlurAnnotation(rect: normalizedRect(from: start, to: current)))
        case .drawingMosaic(let start, _):
            let current = canvasTransform.clampedImagePoint(fromViewPoint: viewPoint)
            setInteractionState(.drawingMosaic(start: start, current: current))
            previewAnnotation = .mosaic(MosaicAnnotation(rect: normalizedRect(from: start, to: current)))
        case .movingAnnotation(_, let startMouse, let originalAnnotation):
            let delta = imageDelta(from: startMouse, to: viewPoint)
            previewAnnotation = movedAnnotation(originalAnnotation, by: delta)
        case .resizingRectangle(_, let handle, _, let originalRect):
            let currentImagePoint = canvasTransform.clampedImagePoint(fromViewPoint: viewPoint)
            let resizedRect = resizedRectangle(
                originalRect: originalRect,
                handle: handle,
                currentImagePoint: currentImagePoint,
                minimumSize: Metrics.minimumRectangleSize
            )
            previewAnnotation = .rectangle(RectangleAnnotation(
                id: selectedAnnotationID ?? UUID(),
                rect: resizedRect
            ))
        case .resizingHighlight(_, let handle, _, let originalRect):
            let currentImagePoint = canvasTransform.clampedImagePoint(fromViewPoint: viewPoint)
            let resizedRect = resizedRectangle(
                originalRect: originalRect,
                handle: handle,
                currentImagePoint: currentImagePoint,
                minimumSize: Metrics.minimumHighlightSize
            )
            previewAnnotation = .highlight(HighlightAnnotation(
                id: selectedAnnotationID ?? UUID(),
                rect: resizedRect
            ))
        case .resizingBlur(_, let handle, _, let originalRect):
            let currentImagePoint = canvasTransform.clampedImagePoint(fromViewPoint: viewPoint)
            let resizedRect = resizedRectangle(
                originalRect: originalRect,
                handle: handle,
                currentImagePoint: currentImagePoint,
                minimumSize: Metrics.minimumBlurSize
            )
            previewAnnotation = .blur(BlurAnnotation(
                id: selectedAnnotationID ?? UUID(),
                rect: resizedRect
            ))
        case .resizingMosaic(_, let handle, _, let originalRect):
            let currentImagePoint = canvasTransform.clampedImagePoint(fromViewPoint: viewPoint)
            let resizedRect = resizedRectangle(
                originalRect: originalRect,
                handle: handle,
                currentImagePoint: currentImagePoint,
                minimumSize: Metrics.minimumMosaicSize
            )
            previewAnnotation = .mosaic(MosaicAnnotation(
                id: selectedAnnotationID ?? UUID(),
                rect: resizedRect
            ))
        case .resizingText(_, let handle, _, let originalRect):
            let currentImagePoint = canvasTransform.clampedImagePoint(fromViewPoint: viewPoint)
            let resizedRect = resizedRectangle(
                originalRect: originalRect,
                handle: handle,
                currentImagePoint: currentImagePoint,
                minimumSize: Metrics.minimumTextBounds.width,
                minimumHeight: Metrics.minimumTextBounds.height
            )
            if let originalText = annotations.first(where: { $0.id == selectedAnnotationID })?.text {
                previewAnnotation = .text(originalText.updating(text: originalText.text, rect: resizedRect))
            }
        case .editingArrowEndpoint(_, let endpoint, _, let originalArrow):
            let currentPoint = canvasTransform.clampedImagePoint(fromViewPoint: viewPoint)
            previewAnnotation = updatedArrow(originalArrow, endpoint: endpoint, currentPoint: currentPoint)
        }
    }

    private func commitInteraction(at viewPoint: CGPoint) {
        let shouldResetInteractionState: Bool
        if case .editingText = interactionState {
            shouldResetInteractionState = false
        } else {
            shouldResetInteractionState = true
        }

        defer {
            if shouldResetInteractionState {
                setInteractionState(.idle)
                previewAnnotation = nil
            }
        }

        switch interactionState {
        case .idle, .editingText:
            return
        case .drawingRectangle(let start, _):
            let end = canvasTransform.clampedImagePoint(fromViewPoint: viewPoint)
            let rect = normalizedRect(from: start, to: end)
            guard rect.width >= Metrics.minimumRectangleSize, rect.height >= Metrics.minimumRectangleSize else { return }
            let annotation = AnnotationItem.rectangle(RectangleAnnotation(rect: rect))
            notifySelectionChange(annotation.id)
            onCommitCommand?(.add(annotation))
        case .drawingArrow(let start, _):
            let end = canvasTransform.clampedImagePoint(fromViewPoint: viewPoint)
            guard arrowLength(from: start, to: end) >= Metrics.minimumArrowLength else { return }
            let annotation = AnnotationItem.arrow(ArrowAnnotation(startPoint: start, endPoint: end))
            notifySelectionChange(annotation.id)
            onCommitCommand?(.add(annotation))
        case .drawingHighlight(let start, _):
            let end = canvasTransform.clampedImagePoint(fromViewPoint: viewPoint)
            let rect = normalizedRect(from: start, to: end)
            guard rect.width >= Metrics.minimumHighlightSize, rect.height >= Metrics.minimumHighlightSize else { return }
            let annotation = AnnotationItem.highlight(HighlightAnnotation(rect: rect))
            notifySelectionChange(annotation.id)
            onCommitCommand?(.add(annotation))
        case .drawingBlur(let start, _):
            let end = canvasTransform.clampedImagePoint(fromViewPoint: viewPoint)
            let rect = normalizedRect(from: start, to: end)
            guard rect.width >= Metrics.minimumBlurSize, rect.height >= Metrics.minimumBlurSize else { return }
            let annotation = AnnotationItem.blur(BlurAnnotation(rect: rect))
            notifySelectionChange(annotation.id)
            onCommitCommand?(.add(annotation))
        case .drawingMosaic(let start, _):
            let end = canvasTransform.clampedImagePoint(fromViewPoint: viewPoint)
            let rect = normalizedRect(from: start, to: end)
            guard rect.width >= Metrics.minimumMosaicSize, rect.height >= Metrics.minimumMosaicSize else { return }
            let annotation = AnnotationItem.mosaic(MosaicAnnotation(rect: rect))
            notifySelectionChange(annotation.id)
            onCommitCommand?(.add(annotation))
        case .movingAnnotation(_, _, let originalAnnotation):
            guard let previewAnnotation, previewAnnotation.id == originalAnnotation.id else { return }
            guard annotationsDiffer(originalAnnotation, previewAnnotation) else { return }
            notifySelectionChange(previewAnnotation.id)
            onCommitCommand?(.update(before: originalAnnotation, after: previewAnnotation))
        case .resizingRectangle(let id, _, _, let originalRect):
            guard let previewAnnotation = previewAnnotation, previewAnnotation.id == id else { return }
            guard let rectangle = previewAnnotation.rectangle, rectangle.rect != originalRect else { return }
            let originalAnnotation = AnnotationItem.rectangle(RectangleAnnotation(
                id: id,
                rect: originalRect,
                strokeColor: rectangle.strokeColor,
                lineWidth: rectangle.lineWidth
            ))
            notifySelectionChange(id)
            onCommitCommand?(.update(before: originalAnnotation, after: previewAnnotation))
        case .resizingHighlight(let id, _, _, let originalRect):
            guard let previewAnnotation = previewAnnotation, previewAnnotation.id == id else { return }
            guard let highlight = previewAnnotation.highlight, highlight.rect != originalRect else { return }
            let originalAnnotation = AnnotationItem.highlight(HighlightAnnotation(
                id: id,
                rect: originalRect,
                dimOpacity: highlight.dimOpacity
            ))
            notifySelectionChange(id)
            onCommitCommand?(.update(before: originalAnnotation, after: previewAnnotation))
        case .resizingBlur(let id, _, _, let originalRect):
            guard let previewAnnotation = previewAnnotation, previewAnnotation.id == id else { return }
            guard let blur = previewAnnotation.blur, blur.rect != originalRect else { return }
            let originalAnnotation = AnnotationItem.blur(BlurAnnotation(
                id: id,
                rect: originalRect,
                radius: blur.radius
            ))
            notifySelectionChange(id)
            onCommitCommand?(.update(before: originalAnnotation, after: previewAnnotation))
        case .resizingMosaic(let id, _, _, let originalRect):
            guard let previewAnnotation = previewAnnotation, previewAnnotation.id == id else { return }
            guard let mosaic = previewAnnotation.mosaic, mosaic.rect != originalRect else { return }
            let originalAnnotation = AnnotationItem.mosaic(MosaicAnnotation(
                id: id,
                rect: originalRect,
                blockSize: mosaic.blockSize
            ))
            notifySelectionChange(id)
            onCommitCommand?(.update(before: originalAnnotation, after: previewAnnotation))
        case .resizingText(let id, _, _, let originalRect):
            guard let previewAnnotation = previewAnnotation, previewAnnotation.id == id else { return }
            guard let text = previewAnnotation.text, text.rect != originalRect else { return }
            let originalAnnotation = AnnotationItem.text(TextAnnotation(
                id: id,
                text: text.text,
                rect: originalRect,
                fontSize: text.fontSize,
                color: text.color,
                fontName: text.fontName
            ))
            notifySelectionChange(id)
            onCommitCommand?(.update(before: originalAnnotation, after: previewAnnotation))
        case .editingArrowEndpoint(let id, _, _, let originalArrow):
            guard let previewAnnotation = previewAnnotation, previewAnnotation.id == id else { return }
            guard let previewArrow = previewAnnotation.arrow else { return }
            guard previewArrow.startPoint != originalArrow.startPoint || previewArrow.endPoint != originalArrow.endPoint else { return }
            let originalAnnotation = AnnotationItem.arrow(originalArrow)
            notifySelectionChange(id)
            onCommitCommand?(.update(before: originalAnnotation, after: previewAnnotation))
        }
    }

    private func beginEditingExistingText(_ annotation: TextAnnotation) {
        beginEditingText(
            id: annotation.id,
            text: annotation.text,
            rect: annotation.rect,
            originalAnnotation: annotation
        )
    }

    private func beginEditingText(
        id: UUID,
        text: String,
        rect: CGRect,
        originalAnnotation: TextAnnotation?
    ) {
        if activeTextEdit != nil {
            finishActiveTextEditing(commit: true)
        }

        let textView = InlineTextView()
        textView.delegate = self
        textView.string = text
        textView.font = scaledEditingFont(for: originalAnnotation?.fontSize ?? Metrics.defaultTextFontSize)
        textView.textColor = originalAnnotation?.color ?? .systemRed
        textView.backgroundColor = NSColor.black.withAlphaComponent(0.2)
        textView.drawsBackground = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 4)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.onCommit = { [weak self] in
            self?.finishActiveTextEditing(commit: true)
        }
        textView.onCancel = { [weak self] in
            self?.finishActiveTextEditing(commit: false)
        }

        addSubview(textView)

        activeTextEdit = ActiveTextEdit(
            id: id,
            rect: rect,
            originalAnnotation: originalAnnotation,
            textView: textView
        )
        syncTextEditorFrameIfNeeded()
        notifySelectionChange(id)
        setInteractionState(.editingText(id: id))
        window?.makeFirstResponder(textView)
    }

    private func finishActiveTextEditing(commit: Bool) {
        guard let activeTextEdit else { return }

        let originalAnnotation = activeTextEdit.originalAnnotation
        let annotationID = activeTextEdit.id
        let annotationRect = activeTextEdit.rect
        let committedText = activeTextEdit.textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        activeTextEdit.textView.removeFromSuperview()
        self.activeTextEdit = nil

        defer {
            setInteractionState(.idle)
            needsDisplay = true
        }

        guard commit else {
            notifySelectionChange(originalAnnotation?.id)
            return
        }

        if let originalAnnotation {
            if committedText.isEmpty {
                notifySelectionChange(nil)
                onCommitCommand?(.delete(.text(originalAnnotation)))
                return
            }

            let updatedAnnotation = TextAnnotation(
                id: originalAnnotation.id,
                text: committedText,
                rect: annotationRect,
                fontSize: originalAnnotation.fontSize,
                color: originalAnnotation.color,
                fontName: originalAnnotation.fontName
            )
            let before = AnnotationItem.text(originalAnnotation)
            let after = AnnotationItem.text(updatedAnnotation)
            guard annotationsDiffer(before, after) else {
                notifySelectionChange(originalAnnotation.id)
                return
            }
            notifySelectionChange(updatedAnnotation.id)
            onCommitCommand?(.update(before: before, after: after))
            return
        }

        guard committedText.isEmpty == false else {
            notifySelectionChange(nil)
            return
        }

        let annotation = AnnotationItem.text(TextAnnotation(
            id: annotationID,
            text: committedText,
            rect: annotationRect
        ))
        notifySelectionChange(annotation.id)
        onCommitCommand?(.add(annotation))
    }

    private func syncTextEditorFrameIfNeeded() {
        guard let activeTextEdit else { return }
        activeTextEdit.textView.font = scaledEditingFont(for: activeTextEdit.originalAnnotation?.fontSize ?? Metrics.defaultTextFontSize)

        let frame = AnnotationRenderer.textBoundingRect(
            for: TextAnnotation(
                id: activeTextEdit.id,
                text: activeTextEdit.textView.string,
                rect: activeTextEdit.rect,
                fontSize: activeTextEdit.originalAnnotation?.fontSize ?? Metrics.defaultTextFontSize,
                color: activeTextEdit.originalAnnotation?.color ?? .systemRed,
                fontName: activeTextEdit.originalAnnotation?.fontName
            ),
            transform: canvasTransform
        )
        activeTextEdit.textView.frame = frame
        activeTextEdit.textView.textContainer?.containerSize = frame.size
    }

    private func notifySelectionChange(_ id: UUID?) {
        log("selectedAnnotationID -> \(String(describing: id))")
        selectedAnnotationID = id
        onSelectionChange?(id)
    }

    private func hitTestAnnotation(at viewPoint: CGPoint, transform: CanvasTransform) -> AnnotationHitTarget? {
        for annotation in annotations {
            log("annotation id=\(annotation.id) data=\(debugDescription(for: annotation))")
        }

        for annotation in annotations.reversed() {
            switch annotation {
            case .rectangle(let rectangle):
                if selectedAnnotationID == rectangle.id {
                    for handle in ResizeHandle.allCases {
                        if AnnotationRenderer.rectangleHandleRects(for: rectangle, transform: transform)[handle]?.contains(viewPoint) == true {
                            return .rectangleHandle(id: rectangle.id, handle: handle)
                        }
                    }
                }

                let rect = transform.imageRectToViewRect(rectangle.rect)
                if rect.insetBy(dx: -AnnotationRenderer.SelectionStyle.rectangleHitTolerance, dy: -AnnotationRenderer.SelectionStyle.rectangleHitTolerance).contains(viewPoint) {
                    return .rectangleBody(id: rectangle.id)
                }
            case .arrow(let arrow):
                if selectedAnnotationID == arrow.id {
                    let endpointRects = AnnotationRenderer.arrowEndpointRects(for: arrow, transform: transform)
                    if endpointRects[.start]?.contains(viewPoint) == true {
                        return .arrowEndpoint(id: arrow.id, endpoint: .start)
                    }
                    if endpointRects[.end]?.contains(viewPoint) == true {
                        return .arrowEndpoint(id: arrow.id, endpoint: .end)
                    }
                }

                let startPoint = transform.imagePointToViewPoint(arrow.startPoint)
                let endPoint = transform.imagePointToViewPoint(arrow.endPoint)
                if distanceFromPoint(viewPoint, toSegmentFrom: startPoint, to: endPoint) <= AnnotationRenderer.SelectionStyle.arrowHitTolerance {
                    return .arrowBody(id: arrow.id)
                }
            case .text(let text):
                if selectedAnnotationID == text.id {
                    for handle in ResizeHandle.allCases {
                        if AnnotationRenderer.textHandleRects(for: text, transform: transform)[handle]?.contains(viewPoint) == true {
                            return .textHandle(id: text.id, handle: handle)
                        }
                    }
                }

                let rect = AnnotationRenderer.textBoundingRect(for: text, transform: transform)
                    .insetBy(dx: -AnnotationRenderer.SelectionStyle.textHitPadding, dy: -AnnotationRenderer.SelectionStyle.textHitPadding)
                if rect.contains(viewPoint) {
                    return .textBody(id: text.id)
                }
            case .highlight(let highlight):
                if selectedAnnotationID == highlight.id {
                    for handle in ResizeHandle.allCases {
                        if AnnotationRenderer.highlightHandleRects(for: highlight, transform: transform)[handle]?.contains(viewPoint) == true {
                            return .highlightHandle(id: highlight.id, handle: handle)
                        }
                    }
                }

                let rect = transform.imageRectToViewRect(highlight.rect)
                if rect.insetBy(dx: -AnnotationRenderer.SelectionStyle.rectangleHitTolerance, dy: -AnnotationRenderer.SelectionStyle.rectangleHitTolerance).contains(viewPoint) {
                    return .highlightBody(id: highlight.id)
                }
            case .blur(let blur):
                if selectedAnnotationID == blur.id {
                    for handle in ResizeHandle.allCases {
                        if AnnotationRenderer.blurHandleRects(for: blur, transform: transform)[handle]?.contains(viewPoint) == true {
                            return .blurHandle(id: blur.id, handle: handle)
                        }
                    }
                }

                let rect = transform.imageRectToViewRect(blur.rect)
                if rect.insetBy(dx: -AnnotationRenderer.SelectionStyle.rectangleHitTolerance, dy: -AnnotationRenderer.SelectionStyle.rectangleHitTolerance).contains(viewPoint) {
                    return .blurBody(id: blur.id)
                }
            case .mosaic(let mosaic):
                if selectedAnnotationID == mosaic.id {
                    for handle in ResizeHandle.allCases {
                        if AnnotationRenderer.mosaicHandleRects(for: mosaic, transform: transform)[handle]?.contains(viewPoint) == true {
                            return .mosaicHandle(id: mosaic.id, handle: handle)
                        }
                    }
                }

                let rect = transform.imageRectToViewRect(mosaic.rect)
                if rect.insetBy(dx: -AnnotationRenderer.SelectionStyle.rectangleHitTolerance, dy: -AnnotationRenderer.SelectionStyle.rectangleHitTolerance).contains(viewPoint) {
                    return .mosaicBody(id: mosaic.id)
                }
            }
        }

        return nil
    }

    private func imageDelta(from startMouse: CGPoint, to currentMouse: CGPoint) -> CGPoint {
        let startPoint = canvasTransform.clampedImagePoint(fromViewPoint: startMouse)
        let endPoint = canvasTransform.clampedImagePoint(fromViewPoint: currentMouse)
        return CGPoint(x: endPoint.x - startPoint.x, y: endPoint.y - startPoint.y)
    }

    private func movedAnnotation(_ annotation: AnnotationItem, by delta: CGPoint) -> AnnotationItem {
        switch annotation {
        case .rectangle(let rectangle):
            let movedRect = CGRect(
                x: rectangle.rect.origin.x + delta.x,
                y: rectangle.rect.origin.y + delta.y,
                width: rectangle.rect.width,
                height: rectangle.rect.height
            )
            return .rectangle(rectangle.updatingRect(clampedRect(movedRect)))
        case .arrow(let arrow):
            let movedArrow = arrow.updatingPoints(
                startPoint: clampedImagePoint(CGPoint(x: arrow.startPoint.x + delta.x, y: arrow.startPoint.y + delta.y)),
                endPoint: clampedImagePoint(CGPoint(x: arrow.endPoint.x + delta.x, y: arrow.endPoint.y + delta.y))
            )
            return .arrow(movedArrow)
        case .text(let text):
            let movedRect = CGRect(
                x: text.rect.origin.x + delta.x,
                y: text.rect.origin.y + delta.y,
                width: text.rect.width,
                height: text.rect.height
            )
            return .text(text.updating(text: text.text, rect: clampedRect(movedRect)))
        case .highlight(let highlight):
            let movedRect = CGRect(
                x: highlight.rect.origin.x + delta.x,
                y: highlight.rect.origin.y + delta.y,
                width: highlight.rect.width,
                height: highlight.rect.height
            )
            return .highlight(highlight.updatingRect(clampedRect(movedRect)))
        case .blur(let blur):
            let movedRect = CGRect(
                x: blur.rect.origin.x + delta.x,
                y: blur.rect.origin.y + delta.y,
                width: blur.rect.width,
                height: blur.rect.height
            )
            return .blur(blur.updatingRect(clampedRect(movedRect)))
        case .mosaic(let mosaic):
            let movedRect = CGRect(
                x: mosaic.rect.origin.x + delta.x,
                y: mosaic.rect.origin.y + delta.y,
                width: mosaic.rect.width,
                height: mosaic.rect.height
            )
            return .mosaic(mosaic.updatingRect(clampedRect(movedRect)))
        }
    }

    private func resizedRectangle(
        originalRect: CGRect,
        handle: ResizeHandle,
        currentImagePoint: CGPoint,
        minimumSize: CGFloat
    ) -> CGRect {
        resizedRectangle(
            originalRect: originalRect,
            handle: handle,
            currentImagePoint: currentImagePoint,
            minimumSize: minimumSize,
            minimumHeight: minimumSize
        )
    }

    private func resizedRectangle(
        originalRect: CGRect,
        handle: ResizeHandle,
        currentImagePoint: CGPoint,
        minimumSize: CGFloat,
        minimumHeight: CGFloat
    ) -> CGRect {
        var left = originalRect.minX
        var right = originalRect.maxX
        var top = originalRect.minY
        var bottom = originalRect.maxY

        switch handle {
        case .topLeft:
            left = currentImagePoint.x
            top = currentImagePoint.y
        case .top:
            top = currentImagePoint.y
        case .topRight:
            right = currentImagePoint.x
            top = currentImagePoint.y
        case .right:
            right = currentImagePoint.x
        case .bottomRight:
            right = currentImagePoint.x
            bottom = currentImagePoint.y
        case .bottom:
            bottom = currentImagePoint.y
        case .bottomLeft:
            left = currentImagePoint.x
            bottom = currentImagePoint.y
        case .left:
            left = currentImagePoint.x
        }

        var rect = CGRect(
            x: min(left, right),
            y: min(top, bottom),
            width: abs(right - left),
            height: abs(bottom - top)
        )

        if rect.width < minimumSize {
            rect.size.width = minimumSize
            if left <= right {
                rect.origin.x = right - minimumSize
            }
        }

        if rect.height < minimumHeight {
            rect.size.height = minimumHeight
            if top <= bottom {
                rect.origin.y = bottom - minimumHeight
            }
        }

        return clampedRect(rect)
    }

    private func updatedArrow(
        _ originalArrow: ArrowAnnotation,
        endpoint: ArrowEndpoint,
        currentPoint: CGPoint
    ) -> AnnotationItem {
        let updatedArrow: ArrowAnnotation
        switch endpoint {
        case .start:
            let newStart = adjustedArrowEndpoint(
                fixedPoint: originalArrow.endPoint,
                candidate: currentPoint
            )
            updatedArrow = originalArrow.updatingPoints(startPoint: newStart, endPoint: originalArrow.endPoint)
        case .end:
            let newEnd = adjustedArrowEndpoint(
                fixedPoint: originalArrow.startPoint,
                candidate: currentPoint
            )
            updatedArrow = originalArrow.updatingPoints(startPoint: originalArrow.startPoint, endPoint: newEnd)
        }

        return .arrow(updatedArrow)
    }

    private func adjustedArrowEndpoint(fixedPoint: CGPoint, candidate: CGPoint) -> CGPoint {
        let dx = candidate.x - fixedPoint.x
        let dy = candidate.y - fixedPoint.y
        let length = hypot(dx, dy)
        guard length > 0, length < Metrics.minimumArrowLength else {
            return clampedImagePoint(candidate)
        }

        let scale = Metrics.minimumArrowLength / length
        return clampedImagePoint(CGPoint(
            x: fixedPoint.x + dx * scale,
            y: fixedPoint.y + dy * scale
        ))
    }

    private func clampedRect(_ rect: CGRect) -> CGRect {
        var clamped = rect
        clamped.origin.x = min(max(clamped.origin.x, 0), max(0, imageSize.width - clamped.width))
        clamped.origin.y = min(max(clamped.origin.y, 0), max(0, imageSize.height - clamped.height))
        clamped.size.width = min(clamped.size.width, imageSize.width)
        clamped.size.height = min(clamped.size.height, imageSize.height)
        return clamped
    }

    private func clampedImagePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), imageSize.width),
            y: min(max(point.y, 0), imageSize.height)
        )
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func arrowLength(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func distanceFromPoint(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy

        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    private func annotationsDiffer(_ lhs: AnnotationItem, _ rhs: AnnotationItem) -> Bool {
        switch (lhs, rhs) {
        case (.rectangle(let left), .rectangle(let right)):
            return left.rect != right.rect
        case (.arrow(let left), .arrow(let right)):
            return left.startPoint != right.startPoint || left.endPoint != right.endPoint
        case (.text(let left), .text(let right)):
            return left.rect != right.rect || left.text != right.text
        case (.highlight(let left), .highlight(let right)):
            return left.rect != right.rect
        case (.blur(let left), .blur(let right)):
            return left.rect != right.rect
        case (.mosaic(let left), .mosaic(let right)):
            return left.rect != right.rect
        default:
            return true
        }
    }

    private func updateCursor(for viewPoint: CGPoint) {
        switch interactionState {
        case .movingAnnotation:
            NSCursor.closedHand.set()
            return
        case .resizingRectangle, .resizingHighlight, .resizingBlur, .resizingMosaic, .resizingText, .editingArrowEndpoint, .drawingRectangle, .drawingArrow, .drawingHighlight, .drawingBlur, .drawingMosaic:
            NSCursor.crosshair.set()
            return
        case .editingText:
            NSCursor.iBeam.set()
            return
        case .idle:
            break
        }

        switch selectedTool {
        case .rectangle, .arrow, .highlight, .blur, .mosaic:
            if canvasTransform.displayedImageRect.contains(viewPoint) {
                NSCursor.crosshair.set()
            } else {
                NSCursor.arrow.set()
            }
        case .text:
            if canvasTransform.displayedImageRect.contains(viewPoint) {
                NSCursor.iBeam.set()
            } else {
                NSCursor.arrow.set()
            }
        case .select:
            guard let hit = hitTestAnnotation(at: viewPoint, transform: canvasTransform) else {
                log("cursor hitTest miss")
                NSCursor.arrow.set()
                return
            }

            switch hit {
            case .rectangleHandle(_, let handle), .textHandle(_, let handle), .highlightHandle(_, let handle), .blurHandle(_, let handle), .mosaicHandle(_, let handle):
                cursor(for: handle).set()
            case .rectangleBody, .arrowBody, .textBody, .highlightBody, .blurBody, .mosaicBody:
                NSCursor.openHand.set()
            case .arrowEndpoint:
                NSCursor.crosshair.set()
            }
        default:
            NSCursor.arrow.set()
        }
    }

    private func cursor(for handle: ResizeHandle) -> NSCursor {
        switch handle {
        case .left, .right:
            return .resizeLeftRight
        case .top, .bottom:
            return .resizeUpDown
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return .crosshair
        }
    }

    private func scaledEditingFont(for fontSize: CGFloat) -> NSFont {
        let scale = max(0.01, canvasTransform.displayedImageRect.width / max(imageSize.width, 1))
        return .systemFont(ofSize: max(8, fontSize * scale))
    }

    private func deleteSelectedAnnotationIfNeeded() {
        guard selectedTool == .select else { return }
        guard case .editingText = interactionState else {
            guard let selectedAnnotationID, let annotation = annotations.first(where: { $0.id == selectedAnnotationID }) else {
                return
            }

            previewAnnotation = nil
            setInteractionState(.idle)
            notifySelectionChange(nil)
            onCommitCommand?(.delete(annotation))
            return
        }
    }

    private func isDrawingEffectPreview(_ annotation: AnnotationItem) -> Bool {
        switch interactionState {
        case .drawingBlur:
            return annotation.blur != nil
        case .drawingMosaic:
            return annotation.mosaic != nil
        default:
            return false
        }
    }

    private static func imagePixelSize(for image: NSImage) -> CGSize {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }

        return image.size
    }

    private func setInteractionState(_ newState: EditorInteractionState) {
        interactionState = newState
        log("interactionState -> \(debugDescription(for: newState))")
    }

    private func log(_ message: String) {
        guard debugLoggingEnabled else { return }
        print("[Editor] \(message)")
    }

    private func debugDescription(for annotation: AnnotationItem) -> String {
        switch annotation {
        case .rectangle(let rectangle):
            return "rectangle rect=\(debugRect(rectangle.rect))"
        case .arrow(let arrow):
            return "arrow start=\(debugPoint(arrow.startPoint)) end=\(debugPoint(arrow.endPoint))"
        case .text(let text):
            return "text rect=\(debugRect(text.rect)) value=\(text.text)"
        case .highlight(let highlight):
            return "highlight rect=\(debugRect(highlight.rect))"
        case .blur(let blur):
            return "blur rect=\(debugRect(blur.rect)) radius=\(blur.radius)"
        case .mosaic(let mosaic):
            return "mosaic rect=\(debugRect(mosaic.rect)) blockSize=\(mosaic.blockSize)"
        }
    }

    private func debugDescription(for state: EditorInteractionState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .drawingRectangle(let start, let current):
            return "drawingRectangle start=\(debugPoint(start)) current=\(debugPoint(current))"
        case .drawingArrow(let start, let current):
            return "drawingArrow start=\(debugPoint(start)) current=\(debugPoint(current))"
        case .drawingHighlight(let start, let current):
            return "drawingHighlight start=\(debugPoint(start)) current=\(debugPoint(current))"
        case .drawingBlur(let start, let current):
            return "drawingBlur start=\(debugPoint(start)) current=\(debugPoint(current))"
        case .drawingMosaic(let start, let current):
            return "drawingMosaic start=\(debugPoint(start)) current=\(debugPoint(current))"
        case .movingAnnotation(let id, let startMouse, _):
            return "movingAnnotation id=\(id) startMouse=\(debugPoint(startMouse))"
        case .resizingRectangle(let id, let handle, let startMouse, let originalRect):
            return "resizingRectangle id=\(id) handle=\(handle) startMouse=\(debugPoint(startMouse)) rect=\(debugRect(originalRect))"
        case .resizingHighlight(let id, let handle, let startMouse, let originalRect):
            return "resizingHighlight id=\(id) handle=\(handle) startMouse=\(debugPoint(startMouse)) rect=\(debugRect(originalRect))"
        case .resizingBlur(let id, let handle, let startMouse, let originalRect):
            return "resizingBlur id=\(id) handle=\(handle) startMouse=\(debugPoint(startMouse)) rect=\(debugRect(originalRect))"
        case .resizingMosaic(let id, let handle, let startMouse, let originalRect):
            return "resizingMosaic id=\(id) handle=\(handle) startMouse=\(debugPoint(startMouse)) rect=\(debugRect(originalRect))"
        case .resizingText(let id, let handle, let startMouse, let originalRect):
            return "resizingText id=\(id) handle=\(handle) startMouse=\(debugPoint(startMouse)) rect=\(debugRect(originalRect))"
        case .editingArrowEndpoint(let id, let endpoint, let startMouse, let originalArrow):
            return "editingArrowEndpoint id=\(id) endpoint=\(endpoint) startMouse=\(debugPoint(startMouse)) arrow=\(debugPoint(originalArrow.startPoint))->\(debugPoint(originalArrow.endPoint))"
        case .editingText(let id):
            return "editingText id=\(id)"
        }
    }

    private func debugPoint(_ point: CGPoint) -> String {
        String(format: "{%.1f, %.1f}", point.x, point.y)
    }

    private func debugRect(_ rect: CGRect) -> String {
        String(format: "{x:%.1f y:%.1f w:%.1f h:%.1f}", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)
    }
}

private extension EditorCanvasView {
    enum Metrics {
        static let minimumRectangleSize: CGFloat = 5
        static let minimumHighlightSize: CGFloat = 5
        static let minimumBlurSize: CGFloat = 5
        static let minimumMosaicSize: CGFloat = 5
        static let minimumArrowLength: CGFloat = 8
        static let defaultTextFontSize: CGFloat = 24
        static let defaultTextBounds = CGSize(width: 160, height: 44)
        static let minimumTextBounds = CGSize(width: 120, height: 32)
    }

    enum KeyCode {
        static let returnKey: UInt16 = 36
        static let enterKey: UInt16 = 76
        static let escapeKey: UInt16 = 53
        static let deleteKey: UInt16 = 51
        static let forwardDeleteKey: UInt16 = 117
    }

    enum EditorInteractionState {
        case idle
        case drawingRectangle(start: CGPoint, current: CGPoint)
        case drawingArrow(start: CGPoint, current: CGPoint)
        case drawingHighlight(start: CGPoint, current: CGPoint)
        case drawingBlur(start: CGPoint, current: CGPoint)
        case drawingMosaic(start: CGPoint, current: CGPoint)
        case movingAnnotation(id: UUID, startMouse: CGPoint, originalAnnotation: AnnotationItem)
        case resizingRectangle(id: UUID, handle: ResizeHandle, startMouse: CGPoint, originalRect: CGRect)
        case resizingHighlight(id: UUID, handle: ResizeHandle, startMouse: CGPoint, originalRect: CGRect)
        case resizingBlur(id: UUID, handle: ResizeHandle, startMouse: CGPoint, originalRect: CGRect)
        case resizingMosaic(id: UUID, handle: ResizeHandle, startMouse: CGPoint, originalRect: CGRect)
        case resizingText(id: UUID, handle: ResizeHandle, startMouse: CGPoint, originalRect: CGRect)
        case editingArrowEndpoint(id: UUID, endpoint: ArrowEndpoint, startMouse: CGPoint, originalArrow: ArrowAnnotation)
        case editingText(id: UUID)
    }

    enum AnnotationHitTarget {
        case rectangleHandle(id: UUID, handle: ResizeHandle)
        case rectangleBody(id: UUID)
        case arrowEndpoint(id: UUID, endpoint: ArrowEndpoint)
        case arrowBody(id: UUID)
        case textHandle(id: UUID, handle: ResizeHandle)
        case textBody(id: UUID)
        case highlightHandle(id: UUID, handle: ResizeHandle)
        case highlightBody(id: UUID)
        case blurHandle(id: UUID, handle: ResizeHandle)
        case blurBody(id: UUID)
        case mosaicHandle(id: UUID, handle: ResizeHandle)
        case mosaicBody(id: UUID)

        var annotationID: UUID {
            switch self {
            case .rectangleHandle(let id, _),
                    .rectangleBody(let id),
                    .arrowEndpoint(let id, _),
                    .arrowBody(let id),
                    .textHandle(let id, _),
                    .textBody(let id),
                    .highlightHandle(let id, _),
                    .highlightBody(let id),
                    .blurHandle(let id, _),
                    .blurBody(let id),
                    .mosaicHandle(let id, _),
                    .mosaicBody(let id):
                id
            }
        }
    }

    final class ActiveTextEdit {
        let id: UUID
        var rect: CGRect
        let originalAnnotation: TextAnnotation?
        let textView: InlineTextView

        init(id: UUID, rect: CGRect, originalAnnotation: TextAnnotation?, textView: InlineTextView) {
            self.id = id
            self.rect = rect
            self.originalAnnotation = originalAnnotation
            self.textView = textView
        }
    }

    final class InlineTextView: NSTextView {
        var onCommit: (() -> Void)?
        var onCancel: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            if event.keyCode == KeyCode.returnKey || event.keyCode == KeyCode.enterKey {
                onCommit?()
                return
            }

            if event.keyCode == KeyCode.escapeKey {
                onCancel?()
                return
            }

            super.keyDown(with: event)
        }
    }
}
