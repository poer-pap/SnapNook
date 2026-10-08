import AppKit
import XCTest
@testable import SnapNook

@MainActor
final class CaptureOverlayRenderingTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 320, height: 240)
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

    func testIdleHUDShowsPixelCoordinatesWithoutOtherOverlayGraphics() throws {
        for mode in [CaptureSelectionMode.screenshot, .textOCR] {
            for scale in [1, 2] {
                let point = CGPoint(x: 120.75, y: 140.25)
                let text = scale == 1 ? "120\n99" : "241\n199"
                let image = try renderOverlay(mode: mode, scale: scale, pointer: point)
                try assertHUD(image, text: text, pointer: point, scale: scale)
                assertUniform(image, ignoring: hudRect(text: text, pointer: point).insetBy(dx: -4, dy: -4),
                              scale: scale)
            }
        }
    }

    func testDraggingHUDShowsOutwardRoundedCropPixelDimensions() throws {
        for mode in [CaptureSelectionMode.screenshot, .textOCR] {
            for scale in [1, 2] {
                let point = CGPoint(x: 140.75, y: 160.75)
                let image = try renderOverlay(mode: mode, scale: scale, pointer: point,
                                              anchor: CGPoint(x: 42.25, y: 55.25))
                // These dimensions come from the fixture's fractional pixel edges,
                // independently of CaptureScreen.pixelRect(for:).
                let text = scale == 1 ? "99\n106" : "198\n212"
                try assertHUD(image, text: text, pointer: point, scale: scale,
                              selection: CGRect(x: 42.25, y: 55.25, width: 98.5, height: 105.5))
            }
        }
    }

    func testCornerHUDChangesSideAndStaysInsideScreen() throws {
        let fixtures: [(CGPoint, String, String)] = [
            (CGPoint(x: 1, y: 1), "1\n239", "2\n478"),
            (CGPoint(x: 319, y: 1), "319\n239", "638\n478"),
            (CGPoint(x: 1, y: 239), "1\n1", "2\n2"),
            (CGPoint(x: 319, y: 239), "319\n1", "638\n2")
        ]
        for mode in [CaptureSelectionMode.screenshot, .textOCR] {
            for scale in [1, 2] {
                for (point, text1x, text2x) in fixtures {
                    let text = scale == 1 ? text1x : text2x
                    let image = try renderOverlay(mode: mode, scale: scale, pointer: point)
                    try assertHUD(image, text: text, pointer: point, scale: scale)
                    assertUniform(image, ignoring: hudRect(text: text, pointer: point).insetBy(dx: -4, dy: -4),
                                  scale: scale)
                }
            }
        }
    }

    func testPixelCoordinatesClampToLastValidPixelAtScreenBounds() throws {
        for scale in [1, 2] {
            for (point, text) in [
                (CGPoint(x: 0, y: 240), "0\n0"),
                (CGPoint(x: 320, y: 0), scale == 1 ? "319\n239" : "639\n479")
            ] {
                let image = try renderOverlay(mode: .screenshot, scale: scale, pointer: point)
                try assertHUD(image, text: text, pointer: point, scale: scale)
            }
        }
    }

    func testMouseExitRemovesHUDFromBothModes() throws {
        for mode in [CaptureSelectionMode.screenshot, .textOCR] {
            for scale in [1, 2] {
                let point = CGPoint(x: 120.75, y: 140.25)
                let before = try renderOverlay(mode: mode, scale: scale, pointer: point)
                let after = try renderOverlay(mode: mode, scale: scale, pointer: point, exited: true)
                XCTAssertEqual(pixels(after)[0..<4], pixels(before)[0..<4])
                assertUniform(after, scale: scale)
            }
        }
    }

    func testRedrawClearsOldHUDAndLeavesChangingBackgroundUnaltered() throws {
        _ = NSApplication.shared
        let screen = CaptureScreen(displayID: 1, screenFrame: bounds, captureFrame: bounds,
                                   pixelWidth: 320, pixelHeight: 240)
        let view = CaptureOverlayView(screen: screen, mode: .screenshot) { _ in }
        let overlay = try bitmap(scale: 1) {
            view.handle(type: .mouseMoved, point: CGPoint(x: 120, y: 140))
            view.draw(bounds)
            view.pointerExited()
            view.draw(bounds)
        }
        assertUniform(overlay, scale: 1)
        for color in [NSColor.red, .blue] {
            let composite = try bitmap(scale: 1) {
                color.setFill()
                bounds.fill()
                NSGraphicsContext.current?.cgContext.draw(overlay.cgImage!, in: bounds)
            }
            let reference = try bitmap(scale: 1) {
                color.setFill()
                bounds.fill()
            }
            XCTAssertTrue(pixels(composite) == pixels(reference), "Transparent overlay changed the live background")
        }
    }

    private func renderOverlay(mode: CaptureSelectionMode, scale: Int, pointer: CGPoint,
                               anchor: CGPoint? = nil, exited: Bool = false) throws -> NSBitmapImageRep {
        _ = NSApplication.shared
        let screen = CaptureScreen(displayID: 1,
                                   screenFrame: bounds.offsetBy(dx: -400, dy: 80),
                                   captureFrame: bounds, pixelWidth: 320 * scale, pixelHeight: 240 * scale)
        let view = CaptureOverlayView(screen: screen, mode: mode) { _ in }
        let window = NSPanel(contentRect: bounds, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }

        if let anchor {
            view.handle(type: .leftMouseDown, point: anchor)
            view.handle(type: .leftMouseDragged, point: pointer)
        } else {
            view.handle(type: .mouseMoved, point: pointer)
        }
        if exited { view.pointerExited() }
        return try bitmap(scale: scale) { view.draw(bounds) }
    }

    private func bitmap(scale: Int, draw: () -> Void) throws -> NSBitmapImageRep {
        let image = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                                                  pixelsWide: 320 * scale, pixelsHigh: 240 * scale,
                                                  bitsPerSample: 8, samplesPerPixel: 4,
                                                  hasAlpha: true, isPlanar: false,
                                                  colorSpaceName: .deviceRGB,
                                                  bytesPerRow: 320 * scale * 4, bitsPerPixel: 32))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: image))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        draw()
        return image
    }

    private var attributes: [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        return [.font: font, .foregroundColor: NSColor.white, .shadow: shadow]
    }

    private func hudRect(text: String, pointer: CGPoint) -> CGRect {
        let size = (text as NSString).size(withAttributes: attributes)
        var origin = CGPoint(x: pointer.x + 10, y: pointer.y - 10 - size.height)
        if origin.x + size.width > bounds.maxX - 4 { origin.x = pointer.x - 10 - size.width }
        if origin.y < 4 { origin.y = pointer.y + 10 }
        origin.x = min(max(4, origin.x), bounds.maxX - 4 - size.width)
        origin.y = min(max(4, origin.y), bounds.maxY - 4 - size.height)
        return CGRect(origin: origin, size: size)
    }

    private func assertHUD(_ actual: NSBitmapImageRep, text: String, pointer: CGPoint, scale: Int,
                           selection: CGRect? = nil, file: StaticString = #filePath,
                           line: UInt = #line) throws {
        let rect = hudRect(text: text, pointer: pointer)
        let actualPixels = pixels(actual)
        let expected = try bitmap(scale: scale) {
            NSColor(deviceRed: CGFloat(actualPixels[0]) / 255,
                    green: CGFloat(actualPixels[1]) / 255,
                    blue: CGFloat(actualPixels[2]) / 255, alpha: 1).setFill()
            bounds.fill()
            (text as NSString).draw(at: rect.origin, withAttributes: attributes)
        }
        let expectedPixels = pixels(expected)
        let hudBounds = rect.insetBy(dx: -2, dy: -2)
        let selectionBounds = selection?.insetBy(dx: -2, dy: -2)
        var actualCount = 0
        var expectedCount = 0
        var matchedCount = 0
        for y in 0..<actual.pixelsHigh {
            for x in 0..<actual.pixelsWide {
                let offset = y * actual.bytesPerRow + x * 4
                let expectedWhite = isWhite(expectedPixels, at: offset)
                var actualWhite = isWhite(actualPixels, at: offset)
                if let selectionBounds {
                    let point = viewPoint(x: x, y: y, scale: scale)
                    if !hudBounds.contains(point) && selectionBounds.contains(point) {
                        actualWhite = false // Ignore the retained selection border.
                    }
                }
                if expectedWhite { expectedCount += 1 }
                if actualWhite { actualCount += 1 }
                if expectedWhite && actualWhite { matchedCount += 1 }
            }
        }
        XCTAssertGreaterThan(expectedCount, 0, file: file, line: line)
        XCTAssertGreaterThan(actualCount, 0, "Expected visible HUD: \(text)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(Double(matchedCount) / Double(max(1, expectedCount)), 0.95,
                                    "HUD glyphs differ from expected digits: \(text)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(Double(matchedCount) / Double(max(1, actualCount)), 0.95,
                                    "Unexpected white overlay graphics", file: file, line: line)
    }

    private func assertUniform(_ image: NSBitmapImageRep, ignoring allowed: CGRect = .null,
                               scale: Int, file: StaticString = #filePath, line: UInt = #line) {
        let data = pixels(image)
        let baseline = [UInt8](repeating: 0, count: 4)
        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide where !allowed.contains(viewPoint(x: x, y: y, scale: scale)) {
                let offset = y * image.bytesPerRow + x * 4
                if (0..<4).contains(where: { abs(Int(data[offset + $0]) - Int(baseline[$0])) > 2 }) {
                    XCTFail("Graphics outside compact HUD at bitmap pixel (\(x), \(y))", file: file, line: line)
                    return
                }
            }
        }
    }

    private func viewPoint(x: Int, y: Int, scale: Int) -> CGPoint {
        CGPoint(x: (CGFloat(x) + 0.5) / CGFloat(scale),
                y: bounds.height - (CGFloat(y) + 0.5) / CGFloat(scale))
    }

    private func pixels(_ image: NSBitmapImageRep) -> [UInt8] {
        Array(UnsafeBufferPointer(start: image.bitmapData!, count: image.bytesPerRow * image.pixelsHigh))
    }

    private func isWhite(_ pixels: [UInt8], at offset: Int) -> Bool {
        pixels[offset] > 242 && pixels[offset + 1] > 242 && pixels[offset + 2] > 242
    }
}
