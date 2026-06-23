import CoreGraphics

struct CanvasTransform {
    let imageSize: CGSize
    let containerRect: CGRect
    let displayedImageRect: CGRect

    init(imageSize: CGSize, containerRect: CGRect) {
        self.imageSize = imageSize
        self.containerRect = containerRect
        self.displayedImageRect = Self.makeDisplayedImageRect(imageSize: imageSize, containerRect: containerRect)
    }

    func viewPointToImagePoint(_ point: CGPoint) -> CGPoint? {
        guard
            imageSize.width > 0,
            imageSize.height > 0,
            displayedImageRect.width > 0,
            displayedImageRect.height > 0,
            displayedImageRect.contains(point)
        else {
            return nil
        }

        let normalizedX = (point.x - displayedImageRect.minX) / displayedImageRect.width
        let normalizedY = (point.y - displayedImageRect.minY) / displayedImageRect.height

        return CGPoint(
            x: normalizedX * imageSize.width,
            y: normalizedY * imageSize.height
        )
    }

    func imagePointToViewPoint(_ point: CGPoint) -> CGPoint {
        guard
            imageSize.width > 0,
            imageSize.height > 0,
            displayedImageRect.width > 0,
            displayedImageRect.height > 0
        else {
            return displayedImageRect.origin
        }

        let normalizedX = point.x / imageSize.width
        let normalizedY = point.y / imageSize.height

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

    private static func makeDisplayedImageRect(imageSize: CGSize, containerRect: CGRect) -> CGRect {
        guard
            imageSize.width > 0,
            imageSize.height > 0,
            containerRect.width > 0,
            containerRect.height > 0
        else {
            return .zero
        }

        let scale = min(containerRect.width / imageSize.width, containerRect.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale

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
}
