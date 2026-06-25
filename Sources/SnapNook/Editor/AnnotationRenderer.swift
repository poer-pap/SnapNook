import AppKit
import CoreGraphics
import Foundation
import OSLog

enum AnnotationRenderer {
    private static let logger = Logger(subsystem: "com.ethan.snapnook", category: "AnnotationRenderer")

    enum SelectionStyle {
        static let outlineColor = NSColor.systemBlue
        static let handleFillColor = NSColor.white
        static let handleStrokeColor = NSColor.systemBlue
        static let handleSize: CGFloat = 8
        static let dashPattern: [CGFloat] = [6, 4]
        static let arrowHitTolerance: CGFloat = 8
        static let rectangleHitTolerance: CGFloat = 8
        static let textHitPadding: CGFloat = 6
    }

    static func draw(
        annotations: [AnnotationItem],
        in context: CGContext,
        transform: CanvasTransform
    ) {
        let highlights = annotations.compactMap(\.highlight)
        if highlights.isEmpty == false {
            drawHighlights(highlights, in: context, transform: transform)
        }

        for annotation in annotations where annotation.highlight == nil {
            draw(annotation: annotation, in: context, transform: transform)
        }
    }

    static func draw(
        annotations: [AnnotationItem],
        in context: CGContext,
        imageSize: CGSize,
        visibleImageRect: CGRect? = nil
    ) {
        let transform = CanvasTransform(
            imageSize: imageSize,
            visibleImageRect: visibleImageRect,
            canvasSize: visibleImageRect?.size ?? imageSize
        )

        draw(annotations: annotations, in: context, transform: transform)
    }

    static func drawSelection(
        for annotation: AnnotationItem,
        in context: CGContext,
        transform: CanvasTransform
    ) {
        switch annotation {
        case .rectangle(let rectangle):
            drawRectangleSelection(rectangle, in: context, transform: transform)
        case .arrow(let arrow):
            drawArrowSelection(arrow, in: context, transform: transform)
        case .text(let text):
            drawTextSelection(text, in: context, transform: transform)
        case .highlight(let highlight):
            drawHighlightSelection(highlight, in: context, transform: transform)
        case .blur(let blur):
            drawBlurSelection(blur, in: context, transform: transform)
        case .mosaic(let mosaic):
            drawMosaicSelection(mosaic, in: context, transform: transform)
        }
    }

    static func rectangleHandleRects(
        for annotation: RectangleAnnotation,
        transform: CanvasTransform
    ) -> [ResizeHandle: CGRect] {
        handleRects(for: annotation.rect, transform: transform)
    }

    static func highlightHandleRects(
        for annotation: HighlightAnnotation,
        transform: CanvasTransform
    ) -> [ResizeHandle: CGRect] {
        handleRects(for: annotation.rect, transform: transform)
    }

    static func blurHandleRects(
        for annotation: BlurAnnotation,
        transform: CanvasTransform
    ) -> [ResizeHandle: CGRect] {
        handleRects(for: annotation.rect, transform: transform)
    }

    static func mosaicHandleRects(
        for annotation: MosaicAnnotation,
        transform: CanvasTransform
    ) -> [ResizeHandle: CGRect] {
        handleRects(for: annotation.rect, transform: transform)
    }

    static func textBoundingRect(
        for annotation: TextAnnotation,
        transform: CanvasTransform
    ) -> CGRect {
        transform.imageRectToViewRect(annotation.rect)
    }

    static func textHandleRects(
        for annotation: TextAnnotation,
        transform: CanvasTransform
    ) -> [ResizeHandle: CGRect] {
        handleRects(for: annotation.rect, transform: transform)
    }

    private static func handleRects(
        for rect: CGRect,
        transform: CanvasTransform
    ) -> [ResizeHandle: CGRect] {
        let rect = transform.imageRectToViewRect(rect)
        let size = SelectionStyle.handleSize
        let half = size / 2

        return [
            .topLeft: CGRect(x: rect.minX - half, y: rect.minY - half, width: size, height: size),
            .top: CGRect(x: rect.midX - half, y: rect.minY - half, width: size, height: size),
            .topRight: CGRect(x: rect.maxX - half, y: rect.minY - half, width: size, height: size),
            .right: CGRect(x: rect.maxX - half, y: rect.midY - half, width: size, height: size),
            .bottomRight: CGRect(x: rect.maxX - half, y: rect.maxY - half, width: size, height: size),
            .bottom: CGRect(x: rect.midX - half, y: rect.maxY - half, width: size, height: size),
            .bottomLeft: CGRect(x: rect.minX - half, y: rect.maxY - half, width: size, height: size),
            .left: CGRect(x: rect.minX - half, y: rect.midY - half, width: size, height: size)
        ]
    }

    static func arrowEndpointRects(
        for annotation: ArrowAnnotation,
        transform: CanvasTransform
    ) -> [ArrowEndpoint: CGRect] {
        let size = SelectionStyle.handleSize
        let half = size / 2
        let startPoint = transform.imagePointToViewPoint(annotation.startPoint)
        let endPoint = transform.imagePointToViewPoint(annotation.endPoint)

        return [
            .start: CGRect(x: startPoint.x - half, y: startPoint.y - half, width: size, height: size),
            .end: CGRect(x: endPoint.x - half, y: endPoint.y - half, width: size, height: size)
        ]
    }

    static func arrowSelectionBounds(
        for annotation: ArrowAnnotation,
        transform: CanvasTransform
    ) -> CGRect {
        let startPoint = transform.imagePointToViewPoint(annotation.startPoint)
        let endPoint = transform.imagePointToViewPoint(annotation.endPoint)
        let rect = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )

        return rect.insetBy(dx: -12, dy: -12)
    }

    static func cropHandleRects(
        for rect: CGRect,
        transform: CanvasTransform
    ) -> [ResizeHandle: CGRect] {
        handleRects(for: rect, transform: transform)
    }

    static func drawCropOverlay(
        cropRect: CGRect,
        in context: CGContext,
        transform: CanvasTransform
    ) {
        let displayedImageRect = transform.displayedImageRect
        let viewCropRect = transform.imageRectToViewRect(cropRect)
        let path = CGMutablePath()
        path.addRect(displayedImageRect)
        path.addRect(viewCropRect)

        context.saveGState()
        context.addPath(path)
        context.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        context.drawPath(using: .eoFill)
        context.restoreGState()

        drawRectSelection(
            cropRect,
            handleRects: cropHandleRects(for: cropRect, transform: transform),
            in: context,
            transform: transform
        )
    }

    private static func draw(
        annotation: AnnotationItem,
        in context: CGContext,
        transform: CanvasTransform
    ) {
        do {
            switch annotation {
            case .rectangle(let rectangle):
                try drawRectangle(rectangle, in: context, transform: transform)
            case .arrow(let arrow):
                try drawArrow(arrow, in: context, transform: transform)
            case .text(let text):
                try drawText(text, in: context, transform: transform)
            case .highlight, .blur, .mosaic:
                break
            }
        } catch {
            logger.error("Skipping annotation \(annotation.id.uuidString, privacy: .public) during render: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func drawRectangle(
        _ annotation: RectangleAnnotation,
        in context: CGContext,
        transform: CanvasTransform
    ) throws {
        let viewRect = transform.imageRectToViewRect(annotation.rect)
        guard viewRect.origin.x.isFinite, viewRect.origin.y.isFinite, viewRect.width.isFinite, viewRect.height.isFinite else {
            throw AnnotationRenderError.invalidRect
        }
        let lineWidth = scaledLineWidth(annotation.lineWidth, transform: transform)

        context.saveGState()
        context.setStrokeColor(annotation.strokeColor.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineJoin(.round)
        context.stroke(viewRect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        context.restoreGState()
    }

    private static func drawArrow(
        _ annotation: ArrowAnnotation,
        in context: CGContext,
        transform: CanvasTransform
    ) throws {
        let startPoint = transform.imagePointToViewPoint(annotation.startPoint)
        let endPoint = transform.imagePointToViewPoint(annotation.endPoint)
        guard
            startPoint.x.isFinite,
            startPoint.y.isFinite,
            endPoint.x.isFinite,
            endPoint.y.isFinite
        else {
            throw AnnotationRenderError.invalidPoint
        }
        let lineWidth = scaledLineWidth(annotation.lineWidth, transform: transform)

        context.saveGState()
        context.setStrokeColor(annotation.strokeColor.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        strokeArrowPath(from: startPoint, to: endPoint, lineWidth: lineWidth, in: context)
        context.restoreGState()
    }

    private static func drawText(
        _ annotation: TextAnnotation,
        in context: CGContext,
        transform: CanvasTransform
    ) throws {
        guard annotation.text.isEmpty == false else { return }

        let rect = textBoundingRect(for: annotation, transform: transform)
        guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite else {
            throw AnnotationRenderError.invalidRect
        }
        guard rect.width >= 1, rect.height >= 1 else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: scaledFont(for: annotation, transform: transform),
            .foregroundColor: annotation.color
        ]
        let attributedString = NSAttributedString(string: annotation.text, attributes: attributes)

        context.saveGState()
        context.clip(to: rect)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        attributedString.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    private static func drawHighlights(
        _ annotations: [HighlightAnnotation],
        in context: CGContext,
        transform: CanvasTransform
    ) {
        guard let firstAnnotation = annotations.first else { return }
        let displayedImageRect = transform.displayedImageRect
        guard displayedImageRect.isEmpty == false else { return }

        let path = CGMutablePath()
        path.addRect(displayedImageRect)
        for annotation in annotations {
            let rect = transform.imageRectToViewRect(annotation.rect)
            guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite else {
                logger.error("Skipping highlight \(annotation.id.uuidString, privacy: .public) due to invalid rect.")
                continue
            }
            path.addRect(rect)
        }

        context.saveGState()
        context.addPath(path)
        context.setFillColor(NSColor.black.withAlphaComponent(firstAnnotation.dimOpacity).cgColor)
        context.drawPath(using: .eoFill)
        context.restoreGState()
    }

    private static func drawRectangleSelection(
        _ annotation: RectangleAnnotation,
        in context: CGContext,
        transform: CanvasTransform
    ) {
        let rect = transform.imageRectToViewRect(annotation.rect).insetBy(dx: -2, dy: -2)
        context.saveGState()
        context.setStrokeColor(SelectionStyle.outlineColor.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: SelectionStyle.dashPattern)
        context.stroke(rect)
        context.restoreGState()

        let handleRects = rectangleHandleRects(for: annotation, transform: transform)
        for rect in handleRects.values {
            drawHandle(in: rect, context: context)
        }
    }

    private static func drawArrowSelection(
        _ annotation: ArrowAnnotation,
        in context: CGContext,
        transform: CanvasTransform
    ) {
        let startPoint = transform.imagePointToViewPoint(annotation.startPoint)
        let endPoint = transform.imagePointToViewPoint(annotation.endPoint)
        let bounds = arrowSelectionBounds(for: annotation, transform: transform)
        let lineWidth = max(2, scaledLineWidth(annotation.lineWidth, transform: transform))

        context.saveGState()
        context.setStrokeColor(SelectionStyle.outlineColor.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        strokeArrowPath(from: startPoint, to: endPoint, lineWidth: lineWidth, in: context)
        context.restoreGState()

        context.saveGState()
        context.setStrokeColor(SelectionStyle.outlineColor.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: SelectionStyle.dashPattern)
        context.stroke(bounds)
        context.restoreGState()

        let endpointRects = arrowEndpointRects(for: annotation, transform: transform)
        for rect in endpointRects.values {
            drawRoundHandle(in: rect, context: context)
        }
    }

    private static func drawTextSelection(
        _ annotation: TextAnnotation,
        in context: CGContext,
        transform: CanvasTransform
    ) {
        let rect = textBoundingRect(for: annotation, transform: transform)
            .insetBy(dx: -SelectionStyle.textHitPadding, dy: -SelectionStyle.textHitPadding)

        context.saveGState()
        context.setStrokeColor(SelectionStyle.outlineColor.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: SelectionStyle.dashPattern)
        context.stroke(rect)
        context.restoreGState()

        let handleRects = textHandleRects(for: annotation, transform: transform)
        for rect in handleRects.values {
            drawHandle(in: rect, context: context)
        }
    }

    private static func drawHighlightSelection(
        _ annotation: HighlightAnnotation,
        in context: CGContext,
        transform: CanvasTransform
    ) {
        let rect = transform.imageRectToViewRect(annotation.rect).insetBy(dx: -2, dy: -2)
        context.saveGState()
        context.setStrokeColor(SelectionStyle.outlineColor.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: SelectionStyle.dashPattern)
        context.stroke(rect)
        context.restoreGState()

        let handleRects = highlightHandleRects(for: annotation, transform: transform)
        for rect in handleRects.values {
            drawHandle(in: rect, context: context)
        }
    }

    private static func drawBlurSelection(
        _ annotation: BlurAnnotation,
        in context: CGContext,
        transform: CanvasTransform
    ) {
        drawRectSelection(annotation.rect, handleRects: blurHandleRects(for: annotation, transform: transform), in: context, transform: transform)
    }

    private static func drawMosaicSelection(
        _ annotation: MosaicAnnotation,
        in context: CGContext,
        transform: CanvasTransform
    ) {
        drawRectSelection(annotation.rect, handleRects: mosaicHandleRects(for: annotation, transform: transform), in: context, transform: transform)
    }

    static func drawDraftRect(
        _ rect: CGRect,
        in context: CGContext,
        transform: CanvasTransform
    ) {
        let viewRect = transform.imageRectToViewRect(rect)
        context.saveGState()
        context.setFillColor(NSColor.white.withAlphaComponent(0.08).cgColor)
        context.fill(viewRect)
        context.setStrokeColor(SelectionStyle.outlineColor.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: SelectionStyle.dashPattern)
        context.stroke(viewRect)
        context.restoreGState()
    }

    private static func drawRectSelection(
        _ rect: CGRect,
        handleRects: [ResizeHandle: CGRect],
        in context: CGContext,
        transform: CanvasTransform
    ) {
        let rect = transform.imageRectToViewRect(rect).insetBy(dx: -2, dy: -2)
        context.saveGState()
        context.setStrokeColor(SelectionStyle.outlineColor.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: SelectionStyle.dashPattern)
        context.stroke(rect)
        context.restoreGState()

        for rect in handleRects.values {
            drawHandle(in: rect, context: context)
        }
    }

    private static func strokeArrowPath(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        lineWidth: CGFloat,
        in context: CGContext
    ) {
        let headLength = max(lineWidth * 4, 12)
        let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
        let leftWing = CGPoint(
            x: endPoint.x - cos(angle - (.pi / 6)) * headLength,
            y: endPoint.y - sin(angle - (.pi / 6)) * headLength
        )
        let rightWing = CGPoint(
            x: endPoint.x - cos(angle + (.pi / 6)) * headLength,
            y: endPoint.y - sin(angle + (.pi / 6)) * headLength
        )

        context.beginPath()
        context.move(to: startPoint)
        context.addLine(to: endPoint)
        context.move(to: endPoint)
        context.addLine(to: leftWing)
        context.move(to: endPoint)
        context.addLine(to: rightWing)
        context.strokePath()
    }

    private static func drawHandle(in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.setFillColor(SelectionStyle.handleFillColor.cgColor)
        context.fill(rect)
        context.setStrokeColor(SelectionStyle.handleStrokeColor.cgColor)
        context.setLineWidth(1)
        context.stroke(rect)
        context.restoreGState()
    }

    private static func drawRoundHandle(in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.setFillColor(SelectionStyle.handleFillColor.cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(SelectionStyle.handleStrokeColor.cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: rect)
        context.restoreGState()
    }

    private static func scaledLineWidth(_ lineWidth: CGFloat, transform: CanvasTransform) -> CGFloat {
        guard transform.imageSize.width > 0 else {
            return lineWidth
        }

        let scale = transform.displayedImageRect.width / max(transform.visibleImageRect.width, 1)
        return max(1, lineWidth * scale)
    }

    private static func scaledFont(for annotation: TextAnnotation, transform: CanvasTransform) -> NSFont {
        let scale = max(0.01, transform.displayedImageRect.width / max(transform.visibleImageRect.width, 1))
        let baseFontSize = annotation.fontSize > 0 && annotation.fontSize.isFinite ? annotation.fontSize : 24
        let fontSize = max(8, baseFontSize * scale)
        if let fontName = annotation.fontName, let font = NSFont(name: fontName, size: fontSize) {
            return font
        }

        return .systemFont(ofSize: fontSize)
    }

}

private enum AnnotationRenderError: LocalizedError {
    case invalidRect
    case invalidPoint

    var errorDescription: String? {
        switch self {
        case .invalidRect:
            return "annotation rect is invalid"
        case .invalidPoint:
            return "annotation point is invalid"
        }
    }
}
