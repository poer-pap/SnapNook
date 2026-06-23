import AppKit

final class ScreenshotWriter {
    func write(image: NSImage) throws -> URL {
        try write(data: Self.pngData(from: image))
    }

    func write(data pngData: Data) throws -> URL {
        let folderURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("SnapNook")

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let fileURL = folderURL.appendingPathComponent(Self.filename())
        try write(data: pngData, to: fileURL)
        return fileURL
    }

    func write(data pngData: Data, to fileURL: URL) throws {
        try pngData.write(to: fileURL, options: .atomic)
    }

    static func filename(createdAt: Date = Date()) -> String {
        "SnapNook-\(filenameTimestamp(from: createdAt)).png"
    }

    private static func filenameTimestamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func filename() -> String {
        filename(createdAt: Date())
    }

    static func pngData(from image: NSImage) throws -> Data {
        guard image.size.width > 0, image.size.height > 0 else {
            throw ScreenshotWriterError.invalidImageSize(width: image.size.width, height: image.size.height)
        }

        var proposedRect = NSRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            return try pngData(from: cgImage)
        }

        if
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let cgImage = bitmap.cgImage
        {
            return try pngData(from: cgImage)
        }

        throw ScreenshotWriterError.failedToCreateCGImage
    }

    static func pngData(from cgImage: CGImage) throws -> Data {
        guard cgImage.width > 0, cgImage.height > 0 else {
            throw ScreenshotWriterError.invalidImageSize(
                width: CGFloat(cgImage.width),
                height: CGFloat(cgImage.height)
            )
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ScreenshotWriterError.failedToEncodePNG
        }

        return pngData
    }
}

enum ScreenshotWriterError: LocalizedError {
    case invalidImageSize(width: CGFloat, height: CGFloat)
    case failedToCreateCGImage
    case failedToEncodePNG

    var errorDescription: String? {
        switch self {
        case .invalidImageSize(let width, let height):
            return "Could not export image because its size is invalid (\(Int(width))x\(Int(height)))."
        case .failedToCreateCGImage:
            return "Could not export image because no CGImage backing was available."
        case .failedToEncodePNG:
            return "Could not encode the rendered image as PNG."
        }
    }
}
