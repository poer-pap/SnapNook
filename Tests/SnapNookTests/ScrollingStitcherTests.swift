import XCTest
import CoreGraphics
import ScreenCaptureKit
@testable import SnapNook

final class ScrollingStitcherTests: XCTestCase {
    func testDownwardOddOffsetsProduceExactReferencePixels() throws {
        let scene = try makeScene(width: 128, height: 1500)
        let stitcher = ScrollingStitcher()
        for offset in [0, 37, 98, 175, 310, 451, 592, 733, 874, 1015] {
            XCTAssertEqual(stitcher.append(try viewport(scene, offset: offset)), .appended, "offset \(offset)")
        }
        XCTAssertEqual(stitcher.stitchedPixelHeight, 1272)
        try assertImage(stitcher.finalImage(), equals: scene.cropping(to: CGRect(x: 0, y: 0, width: 128, height: 1272)))
        XCTAssertLessThanOrEqual(try XCTUnwrap(stitcher.previewImage()).height, 380)
    }

    func testDuplicateAndUpwardReturnDoNotAppendTwice() throws {
        let scene = try makeScene(width: 128, height: 1200)
        let stitcher = ScrollingStitcher()
        for offset in [0, 101, 202, 303] { XCTAssertEqual(stitcher.append(try viewport(scene, offset: offset)), .appended) }
        for offset in [303, 202, 101, 0, 101, 202, 303] {
            XCTAssertEqual(stitcher.append(try viewport(scene, offset: offset)), .unchanged, "offset \(offset)")
            XCTAssertEqual(stitcher.stitchedPixelHeight, 560)
        }
        XCTAssertEqual(stitcher.append(try viewport(scene, offset: 404)), .appended)
        try assertImage(stitcher.finalImage(), equals: scene.cropping(to: CGRect(x: 0, y: 0, width: 128, height: 661)))
    }

    func testMismatchPreservesReliableBaselineAndRecovers() throws {
        let scene = try makeScene(width: 128, height: 1200)
        let stitcher = ScrollingStitcher()
        XCTAssertEqual(stitcher.append(try viewport(scene, offset: 0)), .appended)
        XCTAssertEqual(stitcher.append(try viewport(scene, offset: 101)), .appended)
        XCTAssertEqual(stitcher.append(try viewport(scene, offset: 800)), .waitingForOverlap)
        XCTAssertEqual(stitcher.stitchedPixelHeight, 358)
        XCTAssertEqual(stitcher.append(try viewport(scene, offset: 202)), .appended)
        try assertImage(stitcher.finalImage(), equals: scene.cropping(to: CGRect(x: 0, y: 0, width: 128, height: 459)))
    }

    func testRepeatedTextureIsRejected() throws {
        let scene = try makeScene(width: 128, height: 1200, repeated: true)
        let stitcher = ScrollingStitcher()
        XCTAssertEqual(stitcher.append(try viewport(scene, offset: 0)), .appended)
        XCTAssertEqual(stitcher.append(try viewport(scene, offset: 7)), .waitingForOverlap)
        XCTAssertEqual(stitcher.stitchedPixelHeight, 257)
    }

    func testLimitKeepsLastConfirmedImageAndIsTerminal() throws {
        let scene = try makeScene(width: 128, height: 1200)
        let stitcher = ScrollingStitcher(pixelLimit: 128 * 400)
        XCTAssertEqual(stitcher.append(try viewport(scene, offset: 0)), .appended)
        XCTAssertEqual(stitcher.append(try viewport(scene, offset: 101)), .appended)
        XCTAssertEqual(stitcher.append(try viewport(scene, offset: 202)), .limitReached)
        XCTAssertEqual(stitcher.append(try viewport(scene, offset: 101)), .limitReached)
        try assertImage(stitcher.finalImage(), equals: scene.cropping(to: CGRect(x: 0, y: 0, width: 128, height: 358)))
    }

    func testFinishDrainsLatestReceivedFrame() throws {
        let scene = try makeScene(width: 128, height: 1200)
        let pipeline = ScrollingCapturePipeline()
        let processing = expectation(description: "first frame processing")
        let release = DispatchSemaphore(value: 0)
        pipeline.onUpdate = { _, _, _ in processing.fulfill(); release.wait() }
        pipeline.submit(.image(try viewport(scene, offset: 0)), pointerInsideSelection: true)
        wait(for: [processing], timeout: 5)
        pipeline.onUpdate = nil
        pipeline.submit(.image(try viewport(scene, offset: 101)), pointerInsideSelection: true)
        let finished = expectation(description: "drained")
        pipeline.finish { image, data in
            XCTAssertEqual(image?.height, 358)
            XCTAssertNotNil(data)
            finished.fulfill()
        }
        // Frames received after Done (including paused page changes) cannot enter the result.
        pipeline.submit(.image(try viewport(scene, offset: 202)), pointerInsideSelection: true)
        release.signal()
        wait(for: [finished], timeout: 5)
    }

    func testCancellationDiscardsPendingAndLateFrames() throws {
        let scene = try makeScene(width: 128, height: 1200)
        let pipeline = ScrollingCapturePipeline()
        let processing = expectation(description: "processing")
        let release = DispatchSemaphore(value: 0)
        pipeline.onUpdate = { _, _, _ in processing.fulfill(); release.wait() }
        pipeline.submit(.image(try viewport(scene, offset: 0)), pointerInsideSelection: true)
        wait(for: [processing], timeout: 5)
        pipeline.submit(.image(try viewport(scene, offset: 101)), pointerInsideSelection: true)
        let cancelledCompletion = expectation(description: "no completion after cancellation")
        cancelledCompletion.isInverted = true
        pipeline.finish { _, _ in cancelledCompletion.fulfill() }
        pipeline.cancel()
        pipeline.submit(.image(try viewport(scene, offset: 202)), pointerInsideSelection: true)
        release.signal()
        wait(for: [cancelledCompletion], timeout: 0.2)
    }

    func testPauseDrainsEarlierFrameButRejectsPageChangesOutsideSelection() throws {
        let scene = try makeScene(width: 128, height: 1200)
        let pipeline = ScrollingCapturePipeline()
        let processing = expectation(description: "first frame processing")
        let release = DispatchSemaphore(value: 0)
        var updates = 0
        pipeline.onUpdate = { _, _, _ in
            updates += 1
            if updates == 1 { processing.fulfill(); release.wait() }
        }
        pipeline.submit(.image(try viewport(scene, offset: 0)), pointerInsideSelection: true)
        wait(for: [processing], timeout: 5)
        // Replace pending frames rather than queueing every received frame.
        for offset in [37, 74, 111] {
            pipeline.submit(.image(try viewport(scene, offset: offset)), pointerInsideSelection: true)
        }
        pipeline.submit(.image(try viewport(scene, offset: 202)), pointerInsideSelection: false)
        let finished = expectation(description: "paused finish")
        pipeline.finish { image, _ in
            XCTAssertEqual(image?.height, 368)
            XCTAssertEqual(updates, 2)
            finished.fulfill()
        }
        release.signal()
        wait(for: [finished], timeout: 5)
    }

    func testCaptureCoordinatesAndPixelSizeOnExternalDisplays() {
        let display = CGRect(x: -1600, y: 300, width: 1600, height: 1000)
        let selection = CGRect(x: -1500, y: 500, width: 1024, height: 768)
        for scale: CGFloat in [1, 2] {
            let configuration = ScrollingCaptureStream.configuration(rect: selection, screenFrame: display, scale: scale)
            XCTAssertEqual(configuration.sourceRect, CGRect(x: 100, y: 32, width: 1024, height: 768))
            XCTAssertEqual(configuration.width, Int(1024 * scale))
            XCTAssertEqual(configuration.height, Int(768 * scale))
            XCTAssertEqual(configuration.queueDepth, 3)
            XCTAssertFalse(configuration.showsCursor)
            XCTAssertFalse(configuration.capturesAudio)
        }
    }

    func testRetinaTwentyScreenResultKeepsOriginalResolution() throws {
        let width = 2048
        let viewportHeight = 1536
        let height = viewportHeight * 20
        let source = try makeScene(width: 128, height: height)
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.interpolationQuality = .none
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let scene = try XCTUnwrap(context.makeImage())
        let stitcher = ScrollingStitcher()
        for offset in stride(from: 0, through: height - viewportHeight, by: viewportHeight / 2) {
            let frame = try XCTUnwrap(scene.cropping(to: CGRect(x: 0, y: offset, width: width, height: viewportHeight)))
            XCTAssertEqual(stitcher.append(frame), .appended, "offset \(offset)")
        }
        XCTAssertEqual(stitcher.stitchedPixelHeight, height)
        try assertImage(stitcher.finalImage(), equals: scene)
    }

    private func viewport(_ scene: CGImage, offset: Int) throws -> CGImage {
        try XCTUnwrap(scene.cropping(to: CGRect(x: 0, y: offset, width: scene.width, height: 257)))
    }

    private func makeScene(width: Int, height: Int, repeated: Bool = false) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let row = repeated ? y % 32 : y
                var hash = UInt32((row / 4) * 131 + (x / 8) * 977 + 17)
                hash = (hash ^ (hash >> 16)) &* 0x45d9f3b
                hash = (hash ^ (hash >> 16)) &* 0x45d9f3b
                let value = UInt8(hash & 255)
                let index = (y * width + x) * 4
                bytes[index] = value
                bytes[index + 1] = value
                bytes[index + 2] = value
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func assertImage(_ actual: CGImage?, equals expected: CGImage?) throws {
        let actual = try XCTUnwrap(actual)
        let expected = try XCTUnwrap(expected)
        XCTAssertEqual(actual.width, expected.width)
        XCTAssertEqual(actual.height, expected.height)
        func pixels(_ image: CGImage) throws -> Data {
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            try bytes.withUnsafeMutableBytes { storage in
                let context = try XCTUnwrap(CGContext(data: storage.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            return Data(bytes)
        }
        XCTAssertTrue(try pixels(actual) == pixels(expected), "Composed pixels must equal the reference crop")
    }
}
