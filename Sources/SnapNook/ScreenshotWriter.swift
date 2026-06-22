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
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw ScreenshotWriterError.pngEncodingFailed
        }

        return pngData
    }
}

enum ScreenshotWriterError: LocalizedError {
    case pngEncodingFailed

    var errorDescription: String? {
        "Could not encode the captured image as PNG."
    }
}
