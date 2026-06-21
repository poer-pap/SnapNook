import AppKit
import CoreGraphics

enum ScreenCapturer {
    static func capture(rect: CGRect, screenFrame: CGRect) -> NSImage? {
        let captureRect = convertToCoreGraphicsRect(rect, screenFrame: screenFrame)

        guard let cgImage = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: rect.size)
    }

    private static func convertToCoreGraphicsRect(_ rect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
