import AppKit

struct ScreenshotPreviewItem {
    let image: NSImage
    let pngData: Data
    let createdAt: Date
    let captureRect: CGRect?
    let screenFrame: CGRect

    var originalImage: NSImage {
        image
    }
}
