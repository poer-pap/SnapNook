import AppKit
import XCTest
@testable import SnapNook

@MainActor
final class ScreenshotPreviewFillTests: XCTestCase {
    func testRenderedThumbnailHasNoLetterboxing() throws {
        for size in [NSSize(width: 10, height: 10), NSSize(width: 800, height: 100),
                     NSSize(width: 100, height: 800)] {
            let image = NSImage(size: size, flipped: false) { rect in
                NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1).setFill()
                rect.fill()
                return true
            }
            let view = ScreenshotPreviewView(item: ScreenshotPreviewItem(
                image: image, pngData: Data(), createdAt: Date(), captureRect: nil, screenFrame: .zero
            ))
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let center = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?
                .usingColorSpace(.deviceRGB))
            // Compare against the rendered center to allow for display color conversion.
            // Check all four edge midpoints, inside the border and rounded corners.
            for point in [NSPoint(x: 3, y: 75), NSPoint(x: 206, y: 75),
                          NSPoint(x: 105, y: 3), NSPoint(x: 105, y: 146)] {
                let x = Int(point.x / view.bounds.width * CGFloat(bitmap.pixelsWide))
                let y = Int(point.y / view.bounds.height * CGFloat(bitmap.pixelsHigh))
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                XCTAssertGreaterThan(color.redComponent, 0.9, "Image \(size), point \(point)")
                XCTAssertEqual(color.redComponent, center.redComponent, accuracy: 0.02)
                XCTAssertEqual(color.greenComponent, center.greenComponent, accuracy: 0.02)
                XCTAssertEqual(color.blueComponent, center.blueComponent, accuracy: 0.02)
            }
        }
    }

    func testThumbnailFillsCardWithoutDistortingOrChangingOriginal() throws {
        for size in [NSSize(width: 10, height: 10),
                     NSSize(width: 1000, height: 100),
                     NSSize(width: 100, height: 1000),
                     NSSize(width: 420, height: 300)] {
            let image = NSImage(size: size)
            let data = Data([1, 2, 3])
            let item = ScreenshotPreviewItem(image: image, pngData: data, createdAt: Date(),
                                             captureRect: nil, screenFrame: .zero)
            let view = ScreenshotPreviewView(item: item)
            let content = try XCTUnwrap(view.subviews.first)
            let thumbnail = try XCTUnwrap(content.subviews.first as? NSImageView)
            XCTAssertEqual(view.bounds.size, NSSize(width: 210, height: 150))
            XCTAssertGreaterThanOrEqual(thumbnail.frame.width, content.bounds.width)
            XCTAssertGreaterThanOrEqual(thumbnail.frame.height, content.bounds.height)
            XCTAssertEqual(min(thumbnail.frame.width / content.bounds.width,
                               thumbnail.frame.height / content.bounds.height), 1, accuracy: 0.0001)
            XCTAssertEqual(thumbnail.frame.midX, content.bounds.midX, accuracy: 0.0001)
            XCTAssertEqual(thumbnail.frame.midY, content.bounds.midY, accuracy: 0.0001)
            XCTAssertEqual(thumbnail.frame.width / thumbnail.frame.height,
                           size.width / size.height, accuracy: 0.0001)
            XCTAssertEqual(thumbnail.imageScaling, .scaleProportionallyUpOrDown)
            XCTAssertTrue(content.layer?.masksToBounds == true)
            XCTAssertEqual(content.layer?.cornerRadius, 16)
            XCTAssertTrue(thumbnail.image === image)
            XCTAssertTrue(item.originalImage === image)
            XCTAssertEqual(image.size, size)
            XCTAssertEqual(item.pngData, data)
        }
    }
}
