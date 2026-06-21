import AppKit

struct ScreenshotPreviewItem {
    let image: NSImage
    let pngData: Data
    let captureRect: CGRect?
    let screenFrame: CGRect
}
