import AppKit
import ImageIO
import UniformTypeIdentifiers

final class EditedImageExporter {
    private let writer = ScreenshotWriter()

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

            do {
                let renderedData = try self?.renderedPNGData(
                    originalImage: originalImage,
                    fallbackPNGData: originalPNGData,
                    annotations: annotations
                ) ?? originalPNGData
                try self?.writer.write(data: renderedData, to: fileURL)
                completion(.success(fileURL))
            } catch {
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
            return fallbackPNGData
        }

        guard
            let cgImageSource = CGImageSourceCreateWithData(fallbackPNGData as CFData, nil),
            let originalCGImage = CGImageSourceCreateImageAtIndex(cgImageSource, 0, nil)
        else {
            return try ScreenshotWriter.pngData(from: originalImage)
        }

        let width = originalCGImage.width
        let height = originalCGImage.height

        guard
            let colorSpace = originalCGImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return try ScreenshotWriter.pngData(from: originalImage)
        }

        let imageSize = CGSize(width: width, height: height)
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: imageSize.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(originalCGImage, in: CGRect(origin: .zero, size: imageSize))
        AnnotationRenderer.draw(annotations: annotations, in: context, imageSize: imageSize)

        guard let renderedCGImage = context.makeImage() else {
            return try ScreenshotWriter.pngData(from: originalImage)
        }

        let bitmap = NSBitmapImageRep(cgImage: renderedCGImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ScreenshotWriterError.pngEncodingFailed
        }

        return pngData
    }
}
