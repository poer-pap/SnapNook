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
        try pngData.write(to: fileURL)
        return fileURL
    }

    static func pngData(from image: NSImage) throws -> Data {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw ScreenshotWriterError.pngEncodingFailed
        }

        return pngData
    }

    private static func filename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "SnapNook-\(formatter.string(from: Date())).png"
    }
}

enum ScreenshotWriterError: LocalizedError {
    case pngEncodingFailed

    var errorDescription: String? {
        "Could not encode the captured image as PNG."
    }
}
