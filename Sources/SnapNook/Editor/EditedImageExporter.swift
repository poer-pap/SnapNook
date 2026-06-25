import AppKit
import CoreGraphics
import ImageIO
import OSLog
import UniformTypeIdentifiers

final class EditedImageExporter {
    private let writer = ScreenshotWriter()
    private let logger = Logger(subsystem: "com.ethan.snapnook", category: "EditedImageExporter")

    func export(
        originalImage: NSImage,
        originalPNGData: Data,
        createdAt: Date,
        annotations: [AnnotationItem],
        activeCropRect: CGRect?,
        from window: NSWindow,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.nameFieldStringValue = ScreenshotWriter.filename(createdAt: createdAt)
        savePanel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")

        if #available(macOS 11.0, *) {
            savePanel.allowedContentTypes = [.png]
        } else {
            savePanel.allowedFileTypes = [UTType.png.identifier]
        }

        savePanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let fileURL = savePanel.url else { return }
            guard let self else { return }

            do {
                print("[Save] start")
                print("[Save] target url:", fileURL.path)
                let renderedData = try self.renderedPNGData(
                    originalImage: originalImage,
                    fallbackPNGData: originalPNGData,
                    annotations: annotations,
                    activeCropRect: activeCropRect
                )
                print("[Save] rendered data size:", renderedData.count)
                do {
                    try self.writer.write(data: renderedData, to: fileURL)
                } catch {
                    throw EditedImageExporterError.failedToWriteFile(path: fileURL.path, underlying: error)
                }
                completion(.success(fileURL))
            } catch {
                print("[Save] failed:", error.localizedDescription)
                completion(.failure(error))
            }
        }
    }

    private func renderedPNGData(
        originalImage: NSImage,
        fallbackPNGData: Data,
        annotations: [AnnotationItem],
        activeCropRect: CGRect?
    ) throws -> Data {
        guard annotations.isEmpty == false || activeCropRect != nil else {
            print("[Exporter] annotations count: 0, using fallback PNG data:", fallbackPNGData.count)
            return fallbackPNGData
        }

        print("[Exporter] original image size:", NSStringFromSize(originalImage.size))
        print("[Exporter] annotations count:", annotations.count)

        guard
            let cgImageSource = CGImageSourceCreateWithData(fallbackPNGData as CFData, nil),
            let originalCGImage = CGImageSourceCreateImageAtIndex(cgImageSource, 0, nil)
        else {
            print("[Exporter] fallback PNG decode failed, encoding original image directly")
            return try ScreenshotWriter.pngData(from: originalImage)
        }

        let sourceWidth = originalCGImage.width
        let sourceHeight = originalCGImage.height
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw ScreenshotWriterError.invalidImageSize(width: CGFloat(sourceWidth), height: CGFloat(sourceHeight))
        }

        let imageSize = CGSize(width: sourceWidth, height: sourceHeight)
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let exportRect = sanitizedCropRect(activeCropRect, imageBounds: imageBounds)
        let effectProcessor = ImageEffectProcessor(sourceImage: originalCGImage)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let width = Int(exportRect.width)
        let height = Int(exportRect.height)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw EditedImageExporterError.failedToCreateBitmapContext
        }

        context.interpolationQuality = .high
        context.draw(
            originalCGImage,
            in: CGRect(
                x: -exportRect.minX,
                y: -(imageSize.height - exportRect.maxY),
                width: imageSize.width,
                height: imageSize.height
            )
        )
        effectProcessor.drawExportEffects(
            for: annotations,
            in: context,
            imageSize: imageSize,
            activeCropRect: exportRect
        )

        context.translateBy(x: 0, y: exportRect.height)
        context.scaleBy(x: 1, y: -1)
        AnnotationRenderer.draw(
            annotations: annotations,
            in: context,
            imageSize: imageSize,
            visibleImageRect: exportRect
        )

        guard let renderedCGImage = context.makeImage() else {
            throw EditedImageExporterError.failedToCreateRenderedImage
        }

        print("[Exporter] rendered image size:", "\(renderedCGImage.width)x\(renderedCGImage.height)")
        print("[Exporter] cgImage:", renderedCGImage)

        let pngData = try ScreenshotWriter.pngData(from: renderedCGImage)
        print("[Exporter] pngData size:", pngData.count)
        logger.notice("Rendered edited image with \(annotations.count, privacy: .public) annotations.")
        return pngData
    }

    private func sanitizedCropRect(_ cropRect: CGRect?, imageBounds: CGRect) -> CGRect {
        guard let cropRect else {
            return imageBounds
        }

        let sanitized = cropRect.standardized.intersection(imageBounds).integral
        guard sanitized.width >= 1, sanitized.height >= 1 else {
            return imageBounds
        }

        return sanitized
    }
}

enum EditedImageExporterError: LocalizedError {
    case failedToCreateBitmapContext
    case failedToCreateRenderedImage
    case failedToWriteFile(path: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .failedToCreateBitmapContext:
            return "Could not create a bitmap context for the edited image."
        case .failedToCreateRenderedImage:
            return "Could not render the edited image into a CGImage."
        case .failedToWriteFile(let path, let underlying):
            return "Could not write the edited PNG to \(path): \(underlying.localizedDescription)"
        }
    }
}
