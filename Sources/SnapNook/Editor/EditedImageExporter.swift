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
                    annotations: annotations
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
        annotations: [AnnotationItem]
    ) throws -> Data {
        guard annotations.isEmpty == false else {
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

        let width = originalCGImage.width
        let height = originalCGImage.height
        guard width > 0, height > 0 else {
            throw ScreenshotWriterError.invalidImageSize(width: CGFloat(width), height: CGFloat(height))
        }

        let effectProcessor = ImageEffectProcessor(sourceImage: originalCGImage)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
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

        let imageSize = CGSize(width: width, height: height)
        context.interpolationQuality = .high
        context.draw(originalCGImage, in: CGRect(origin: .zero, size: imageSize))
        effectProcessor.drawExportEffects(for: annotations, in: context, imageSize: imageSize)

        context.translateBy(x: 0, y: imageSize.height)
        context.scaleBy(x: 1, y: -1)
        AnnotationRenderer.draw(annotations: annotations, in: context, imageSize: imageSize)

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
