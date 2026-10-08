import AppKit
import CoreGraphics

struct CaptureScreen {
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let captureFrame: CGRect
    let pixelWidth: Int
    let pixelHeight: Int

    func pixelRect(for rect: CGRect) -> CGRect {
        let clipped = rect.standardized.intersection(screenFrame)
        guard !clipped.isNull, !clipped.isEmpty else { return .zero }
        let scaleX = CGFloat(pixelWidth) / screenFrame.width
        let scaleY = CGFloat(pixelHeight) / screenFrame.height
        let left = max(0, floor((clipped.minX - screenFrame.minX) * scaleX))
        let top = max(0, floor((screenFrame.maxY - clipped.maxY) * scaleY))
        let right = min(CGFloat(pixelWidth), ceil((clipped.maxX - screenFrame.minX) * scaleX))
        let bottom = min(CGFloat(pixelHeight), ceil((screenFrame.maxY - clipped.minY) * scaleY))
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    func crop(image: CGImage, rect: CGRect) -> NSImage? {
        guard image.width == pixelWidth, image.height == pixelHeight else { return nil }
        let pixels = pixelRect(for: rect)
        guard !pixels.isEmpty, let cropped = image.cropping(to: pixels) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(
            width: pixels.width * screenFrame.width / CGFloat(pixelWidth),
            height: pixels.height * screenFrame.height / CGFloat(pixelHeight)
        ))
    }
}

enum ScreenCapturer {
    static func screens() -> [CaptureScreen]? {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return nil }
        var result: [CaptureScreen] = []
        for screen in screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let displayMode = CGDisplayCopyDisplayMode(number.uint32Value) else { return nil }
            result.append(CaptureScreen(
                displayID: number.uint32Value, screenFrame: screen.frame,
                captureFrame: CGRect(x: screen.frame.minX, y: primary.frame.maxY - screen.frame.maxY,
                                     width: screen.frame.width, height: screen.frame.height),
                pixelWidth: displayMode.pixelWidth, pixelHeight: displayMode.pixelHeight
            ))
        }
        return result
    }

    static func capture(screen: CaptureScreen, rect: CGRect) -> NSImage? {
        guard let image = CGWindowListCreateImage(screen.captureFrame, .optionOnScreenOnly,
                                                 kCGNullWindowID, [.bestResolution]) else { return nil }
        return screen.crop(image: image, rect: rect)
    }

    static func capture(rect: CGRect, screenFrame: CGRect, belowWindowID windowID: CGWindowID) -> NSImage? {
        let captureRect = convertToCoreGraphicsRect(rect, screenFrame: screenFrame)

        guard let cgImage = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenBelowWindow,
            windowID,
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
