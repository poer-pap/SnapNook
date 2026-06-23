import AppKit
import CoreGraphics
import Foundation

enum AnnotationItem: Identifiable {
    case rectangle(RectangleAnnotation)
    case arrow(ArrowAnnotation)
    case text(TextAnnotation)
    case highlight(HighlightAnnotation)

    var id: UUID {
        switch self {
        case .rectangle(let annotation):
            annotation.id
        case .arrow(let annotation):
            annotation.id
        case .text(let annotation):
            annotation.id
        case .highlight(let annotation):
            annotation.id
        }
    }

    var strokeColor: NSColor {
        switch self {
        case .rectangle(let annotation):
            annotation.strokeColor
        case .arrow(let annotation):
            annotation.strokeColor
        case .text(let annotation):
            annotation.color
        case .highlight(let annotation):
            NSColor.black.withAlphaComponent(annotation.dimOpacity)
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .rectangle(let annotation):
            annotation.lineWidth
        case .arrow(let annotation):
            annotation.lineWidth
        case .text:
            0
        case .highlight:
            0
        }
    }

    var rectangle: RectangleAnnotation? {
        guard case .rectangle(let annotation) = self else { return nil }
        return annotation
    }

    var arrow: ArrowAnnotation? {
        guard case .arrow(let annotation) = self else { return nil }
        return annotation
    }

    var text: TextAnnotation? {
        guard case .text(let annotation) = self else { return nil }
        return annotation
    }

    var highlight: HighlightAnnotation? {
        guard case .highlight(let annotation) = self else { return nil }
        return annotation
    }

    func updatingRectangle(_ rect: CGRect) -> AnnotationItem {
        guard case .rectangle(let annotation) = self else { return self }
        return .rectangle(annotation.updatingRect(rect))
    }

    func updatingArrow(startPoint: CGPoint? = nil, endPoint: CGPoint? = nil) -> AnnotationItem {
        guard case .arrow(let annotation) = self else { return self }
        return .arrow(annotation.updatingPoints(
            startPoint: startPoint ?? annotation.startPoint,
            endPoint: endPoint ?? annotation.endPoint
        ))
    }

    func updatingText(text: String? = nil, rect: CGRect? = nil) -> AnnotationItem {
        guard case .text(let annotation) = self else { return self }
        return .text(annotation.updating(
            text: text ?? annotation.text,
            rect: rect ?? annotation.rect
        ))
    }

    func updatingHighlight(_ rect: CGRect) -> AnnotationItem {
        guard case .highlight(let annotation) = self else { return self }
        return .highlight(annotation.updatingRect(rect))
    }
}

struct RectangleAnnotation: Identifiable {
    let id: UUID
    let rect: CGRect
    let strokeColor: NSColor
    let lineWidth: CGFloat

    init(
        id: UUID = UUID(),
        rect: CGRect,
        strokeColor: NSColor = .systemRed,
        lineWidth: CGFloat = 4
    ) {
        self.id = id
        self.rect = rect
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
    }

    func updatingRect(_ rect: CGRect) -> RectangleAnnotation {
        RectangleAnnotation(id: id, rect: rect, strokeColor: strokeColor, lineWidth: lineWidth)
    }
}

struct ArrowAnnotation: Identifiable {
    let id: UUID
    let startPoint: CGPoint
    let endPoint: CGPoint
    let strokeColor: NSColor
    let lineWidth: CGFloat

    init(
        id: UUID = UUID(),
        startPoint: CGPoint,
        endPoint: CGPoint,
        strokeColor: NSColor = .systemRed,
        lineWidth: CGFloat = 4
    ) {
        self.id = id
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
    }

    func updatingPoints(startPoint: CGPoint, endPoint: CGPoint) -> ArrowAnnotation {
        ArrowAnnotation(
            id: id,
            startPoint: startPoint,
            endPoint: endPoint,
            strokeColor: strokeColor,
            lineWidth: lineWidth
        )
    }
}

struct TextAnnotation: Identifiable {
    let id: UUID
    let text: String
    let rect: CGRect
    let fontSize: CGFloat
    let color: NSColor
    let fontName: String?

    init(
        id: UUID = UUID(),
        text: String,
        rect: CGRect,
        fontSize: CGFloat = 24,
        color: NSColor = .systemRed,
        fontName: String? = nil
    ) {
        self.id = id
        self.text = text
        self.rect = rect
        self.fontSize = fontSize
        self.color = color
        self.fontName = fontName
    }

    var font: NSFont {
        if let fontName, let font = NSFont(name: fontName, size: fontSize) {
            return font
        }

        return .systemFont(ofSize: fontSize)
    }

    func updating(text: String, rect: CGRect) -> TextAnnotation {
        TextAnnotation(
            id: id,
            text: text,
            rect: rect,
            fontSize: fontSize,
            color: color,
            fontName: fontName
        )
    }
}

struct HighlightAnnotation: Identifiable {
    let id: UUID
    let rect: CGRect
    let dimOpacity: CGFloat

    init(
        id: UUID = UUID(),
        rect: CGRect,
        dimOpacity: CGFloat = 0.45
    ) {
        self.id = id
        self.rect = rect
        self.dimOpacity = dimOpacity
    }

    func updatingRect(_ rect: CGRect) -> HighlightAnnotation {
        HighlightAnnotation(id: id, rect: rect, dimOpacity: dimOpacity)
    }
}

enum ResizeHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

enum ArrowEndpoint {
    case start
    case end
}

enum EditorCommand {
    case add(AnnotationItem)
    case update(before: AnnotationItem, after: AnnotationItem)
    case delete(AnnotationItem)

    var affectedAnnotationID: UUID {
        switch self {
        case .add(let annotation):
            annotation.id
        case .update(_, let after):
            after.id
        case .delete(let annotation):
            annotation.id
        }
    }
}
