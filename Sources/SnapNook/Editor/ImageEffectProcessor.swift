import AppKit
import CoreImage
import CoreGraphics
import OSLog

final class ImageEffectProcessor {
    private let logger = Logger(subsystem: "com.ethan.snapnook", category: "ImageEffectProcessor")

    private enum EffectKey: Hashable {
        case blur(Int)
        case mosaic(Int)
    }

    private let sourceImage: CGImage
    private let ciContext = CIContext()
    private var processedImageCache: [EffectKey: CGImage] = [:]

    init(sourceImage: CGImage) {
        self.sourceImage = sourceImage
    }

    func drawPreviewEffects(
        for annotations: [AnnotationItem],
        displayedImageRect: CGRect,
        transform: CanvasTransform
    ) {
        guard displayedImageRect.isEmpty == false else { return }

        for annotation in annotations {
            guard let rect = effectRect(for: annotation, imageSize: transform.imageSize) else { continue }
            guard let processedImage = processedImage(for: annotation) else { continue }

            let clipRect = transform.imageRectToViewRect(rect)
            guard clipRect.isEmpty == false else { continue }

            NSGraphicsContext.saveGraphicsState()
            let path = NSBezierPath(rect: clipRect)
            path.addClip()
            NSImage(cgImage: processedImage, size: NSSize(width: sourceImage.width, height: sourceImage.height)).draw(
                in: displayedImageRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    func drawExportEffects(
        for annotations: [AnnotationItem],
        in context: CGContext,
        imageSize: CGSize
    ) {
        let imageRect = CGRect(origin: .zero, size: imageSize)

        for annotation in annotations {
            guard let rect = effectRect(for: annotation, imageSize: imageSize) else { continue }
            guard let processedImage = processedImage(for: annotation) else {
                logger.error("Skipping export effect because processed image creation failed for annotation \(annotation.id.uuidString, privacy: .public).")
                continue
            }

            context.saveGState()
            context.clip(to: exportClipRect(from: rect, imageSize: imageSize))
            context.draw(processedImage, in: imageRect)
            context.restoreGState()
        }
    }

    private func exportClipRect(from rect: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: rect.minX,
            y: imageSize.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func processedImage(for annotation: AnnotationItem) -> CGImage? {
        switch annotation {
        case .blur(let blur):
            return cachedImage(for: .blur(Int(blur.radius.rounded()))) {
                self.makeBlurredImage(radius: blur.radius)
            }
        case .mosaic(let mosaic):
            return cachedImage(for: .mosaic(Int(mosaic.blockSize.rounded()))) {
                self.makeMosaicImage(blockSize: mosaic.blockSize)
            }
        default:
            return nil
        }
    }

    private func cachedImage(for key: EffectKey, builder: () -> CGImage?) -> CGImage? {
        if let cached = processedImageCache[key] {
            return cached
        }

        guard let image = builder() else { return nil }
        processedImageCache[key] = image
        return image
    }

    private func makeBlurredImage(radius: CGFloat) -> CGImage? {
        let sanitizedRadius = max(1, radius.isFinite ? radius : 1)
        let ciImage = CIImage(cgImage: sourceImage)
        let extent = ciImage.extent
        let clamped = ciImage.clampedToExtent()
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(clamped, forKey: kCIInputImageKey)
        filter?.setValue(sanitizedRadius, forKey: kCIInputRadiusKey)

        guard let outputImage = filter?.outputImage?.cropped(to: extent) else {
            logger.error("Blur output image creation failed.")
            return nil
        }

        guard let cgImage = ciContext.createCGImage(outputImage, from: extent) else {
            logger.error("Blur CGImage creation failed.")
            return nil
        }

        return cgImage
    }

    private func makeMosaicImage(blockSize: CGFloat) -> CGImage? {
        let sanitizedBlockSize = max(2, blockSize.isFinite ? blockSize : 2)
        let ciImage = CIImage(cgImage: sourceImage)
        let extent = ciImage.extent
        let filter = CIFilter(name: "CIPixellate")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(sanitizedBlockSize, forKey: kCIInputScaleKey)
        filter?.setValue(CIVector(x: extent.midX, y: extent.midY), forKey: kCIInputCenterKey)

        guard let outputImage = filter?.outputImage?.cropped(to: extent) else {
            logger.error("Mosaic output image creation failed.")
            return nil
        }

        guard let cgImage = ciContext.createCGImage(outputImage, from: extent) else {
            logger.error("Mosaic CGImage creation failed.")
            return nil
        }

        return cgImage
    }

    private func effectRect(for annotation: AnnotationItem, imageSize: CGSize) -> CGRect? {
        let rawRect: CGRect?
        switch annotation {
        case .blur(let blur):
            rawRect = blur.rect
        case .mosaic(let mosaic):
            rawRect = mosaic.rect
        default:
            rawRect = nil
        }

        guard let rawRect else { return nil }
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        return Self.sanitizedRect(rawRect, imageBounds: imageBounds)
    }

    static func sanitizedRect(_ rect: CGRect, imageBounds: CGRect) -> CGRect? {
        guard
            rect.origin.x.isFinite,
            rect.origin.y.isFinite,
            rect.width.isFinite,
            rect.height.isFinite
        else {
            return nil
        }

        let sanitized = rect.standardized.intersection(imageBounds).integral
        guard sanitized.width >= 1, sanitized.height >= 1 else { return nil }
        return sanitized
    }
}
