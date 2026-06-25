import CoreGraphics

struct CanvasTransform {
    let imageSize: CGSize
    let visibleImageRect: CGRect
    let containerRect: CGRect
    let displayedImageRect: CGRect

    init(imageSize: CGSize, visibleImageRect: CGRect? = nil, containerRect: CGRect) {
        self.imageSize = imageSize
        self.visibleImageRect = Self.sanitizedVisibleImageRect(imageSize: imageSize, visibleImageRect: visibleImageRect)
        self.containerRect = containerRect
        self.displayedImageRect = Self.makeDisplayedImageRect(
            visibleImageRect: self.visibleImageRect,
            containerRect: containerRect
        )
    }

    init(imageSize: CGSize, visibleImageRect: CGRect? = nil, canvasSize: CGSize) {
        self.init(
            imageSize: imageSize,
            visibleImageRect: visibleImageRect,
            containerRect: CGRect(origin: .zero, size: canvasSize)
        )
    }

    func viewPointToImagePoint(_ point: CGPoint) -> CGPoint? {
        guard
            visibleImageRect.width > 0,
            visibleImageRect.height > 0,
            displayedImageRect.width > 0,
            displayedImageRect.height > 0,
            displayedImageRect.contains(point)
        else {
            return nil
        }

        let normalizedX = (point.x - displayedImageRect.minX) / displayedImageRect.width
        let normalizedY = (point.y - displayedImageRect.minY) / displayedImageRect.height

        return CGPoint(
            x: visibleImageRect.minX + normalizedX * visibleImageRect.width,
            y: visibleImageRect.minY + normalizedY * visibleImageRect.height
        )
    }

    func imagePointToViewPoint(_ point: CGPoint) -> CGPoint {
        guard
            visibleImageRect.width > 0,
            visibleImageRect.height > 0,
            displayedImageRect.width > 0,
            displayedImageRect.height > 0
        else {
            return displayedImageRect.origin
        }

        let normalizedX = (point.x - visibleImageRect.minX) / visibleImageRect.width
        let normalizedY = (point.y - visibleImageRect.minY) / visibleImageRect.height

        return CGPoint(
            x: displayedImageRect.minX + normalizedX * displayedImageRect.width,
            y: displayedImageRect.minY + normalizedY * displayedImageRect.height
        )
    }

    func viewRectToImageRect(_ rect: CGRect) -> CGRect {
        let start = imagePoint(fromClampedViewPoint: rect.origin)
        let end = imagePoint(fromClampedViewPoint: CGPoint(x: rect.maxX, y: rect.maxY))
        return Self.normalizedRect(from: start, to: end)
    }

    func imageRectToViewRect(_ rect: CGRect) -> CGRect {
        let start = imagePointToViewPoint(rect.origin)
        let end = imagePointToViewPoint(CGPoint(x: rect.maxX, y: rect.maxY))
        return Self.normalizedRect(from: start, to: end)
    }

    func clampedViewPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, displayedImageRect.minX), displayedImageRect.maxX),
            y: min(max(point.y, displayedImageRect.minY), displayedImageRect.maxY)
        )
    }

    func clampedImagePoint(fromViewPoint point: CGPoint) -> CGPoint {
        imagePoint(fromClampedViewPoint: point)
    }

    private func imagePoint(fromClampedViewPoint point: CGPoint) -> CGPoint {
        guard displayedImageRect.width > 0, displayedImageRect.height > 0 else {
            return .zero
        }

        let clampedX = min(max(point.x, displayedImageRect.minX), displayedImageRect.maxX)
        let clampedY = min(max(point.y, displayedImageRect.minY), displayedImageRect.maxY)

        return viewPointToImagePoint(CGPoint(x: clampedX, y: clampedY)) ?? .zero
    }

    private static func makeDisplayedImageRect(visibleImageRect: CGRect, containerRect: CGRect) -> CGRect {
        guard
            visibleImageRect.width > 0,
            visibleImageRect.height > 0,
            containerRect.width > 0,
            containerRect.height > 0
        else {
            return .zero
        }

        let scale = min(containerRect.width / visibleImageRect.width, containerRect.height / visibleImageRect.height)
        let width = visibleImageRect.width * scale
        let height = visibleImageRect.height * scale

        return CGRect(
            x: containerRect.midX - width / 2,
            y: containerRect.midY - height / 2,
            width: width,
            height: height
        )
    }

    private static func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private static func sanitizedVisibleImageRect(imageSize: CGSize, visibleImageRect: CGRect?) -> CGRect {
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        guard let visibleImageRect else {
            return imageBounds
        }

        let sanitized = visibleImageRect.standardized.intersection(imageBounds)
        guard sanitized.width > 0, sanitized.height > 0 else {
            return imageBounds
        }

        return sanitized
    }
}
