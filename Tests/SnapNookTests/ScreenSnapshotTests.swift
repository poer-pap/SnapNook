import AppKit
import XCTest
@testable import SnapNook

final class ScreenSnapshotTests: XCTestCase {
    private func snapshot(frame: CGRect, width: Int = 8, height: Int = 6) -> (screen: CaptureScreen, image: CGImage) {
        var pixels = [UInt8]()
        for y in 0..<height {
            for x in 0..<width { pixels += [UInt8(x), UInt8(y), 0, 255] }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return (CaptureScreen(displayID: 1, screenFrame: frame, captureFrame: frame,
                              pixelWidth: width, pixelHeight: height), image)
    }

    func testChangedDisplayPixelSizeRejectsCaptureInsteadOfMismatchingHUD() {
        let fixture = snapshot(frame: CGRect(x: 0, y: 0, width: 8, height: 6))
        let changed = CaptureScreen(displayID: 1, screenFrame: fixture.screen.screenFrame,
                                    captureFrame: fixture.screen.captureFrame, pixelWidth: 16, pixelHeight: 12)
        XCTAssertNil(changed.crop(image: fixture.image, rect: fixture.screen.screenFrame))
    }

    func testFractionalEdgesRoundOutwardAtRetinaScale() {
        let snapshot = snapshot(frame: CGRect(x: -4, y: 10, width: 4, height: 3))
        XCTAssertEqual(snapshot.screen.pixelRect(for: CGRect(x: -3.75, y: 10.25, width: 2.5, height: 2.5)),
                       CGRect(x: 0, y: 0, width: 6, height: 6))
    }

    func testScreenOriginsDoNotChangeLocalPixels() {
        for origin in [CGPoint(x: -8, y: 0), CGPoint(x: 0, y: -6), CGPoint(x: 0, y: 6)] {
            let snapshot = snapshot(frame: CGRect(origin: origin, size: CGSize(width: 8, height: 6)))
            let rect = CGRect(x: origin.x + 2, y: origin.y + 1, width: 3, height: 2)
            XCTAssertEqual(snapshot.screen.pixelRect(for: rect), CGRect(x: 2, y: 3, width: 3, height: 2))
        }
    }

    func testCropClampsToOriginalPixelsAndRejectsOutside() {
        let snapshot = snapshot(frame: CGRect(x: 0, y: 0, width: 8, height: 6))
        XCTAssertEqual(snapshot.screen.pixelRect(for: CGRect(x: -2, y: -2, width: 12, height: 10)),
                       CGRect(x: 0, y: 0, width: 8, height: 6))
        XCTAssertNil(snapshot.screen.crop(image: snapshot.image, rect: CGRect(x: 20, y: 20, width: 2, height: 2)))
        XCTAssertNil(snapshot.screen.crop(image: snapshot.image, rect: .zero))
    }

    func testCropPreservesSourcePixelsAndTopBottomOrientation() {
        let snapshot = snapshot(frame: CGRect(x: 0, y: 0, width: 8, height: 6))
        for y in [0, 5] {
            let rect = CGRect(x: 3, y: CGFloat(5 - y), width: 1, height: 1)
            let crop = snapshot.screen.crop(image: snapshot.image, rect: rect)!
            var proposed = CGRect(origin: .zero, size: crop.size)
            let image = crop.cgImage(forProposedRect: &proposed, context: nil, hints: nil)!
            var pixel = [UInt8](repeating: 0, count: 4)
            pixel.withUnsafeMutableBytes { bytes in
                let context = CGContext(data: bytes.baseAddress, width: 1, height: 1,
                                        bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            XCTAssertEqual(pixel, [3, UInt8(y), 0, 255])
        }
    }

    func testLabelAndCropUseIdenticalPixelDimensionsAtDifferentScales() {
        for scale: CGFloat in [1, 1.5, 2] {
            let snapshot = snapshot(frame: CGRect(x: 0, y: 0, width: 8 / scale, height: 6 / scale))
            let rect = CGRect(x: 0.2, y: 0.3, width: 2.1, height: 1.4)
            let pixels = snapshot.screen.pixelRect(for: rect)
            let crop = snapshot.screen.crop(image: snapshot.image, rect: rect)!
            var proposed = CGRect(origin: .zero, size: crop.size)
            let image = crop.cgImage(forProposedRect: &proposed, context: nil, hints: nil)!
            XCTAssertEqual(image.width, Int(pixels.width))
            XCTAssertEqual(image.height, Int(pixels.height))
        }
    }
}
