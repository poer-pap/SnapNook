import Foundation
import CoreGraphics
import CoreImage

/// One processing frame and one replaceable pending frame; no per-frame work queue buildup.
final class ScrollingCapturePipeline {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.ethan.snapnook.scrolling.stitch", qos: .userInitiated)
    private let stitcher = ScrollingStitcher()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var pending: ScrollingCaptureFrame?
    private var processing = false
    private var accepting = true
    private var cancelled = false
    private var finishRequested = false
    private var completion: ((CGImage?, Data?) -> Void)?
    private var lastPreview = Date.distantPast
    var onUpdate: ((ScrollingStitcher.AppendResult, CGImage?, Int) -> Void)?

    func submit(_ frame: ScrollingCaptureFrame, pointerInsideSelection: Bool) {
        guard pointerInsideSelection else { return }
        lock.lock()
        guard accepting && !cancelled else { lock.unlock(); return }
        pending = frame
        let shouldStart = !processing
        processing = true
        lock.unlock()
        if shouldStart { queue.async { [self] in drain() } }
    }

    func stopReceiving() {
        lock.lock()
        accepting = false
        lock.unlock()
    }

    func finish(_ completion: @escaping (CGImage?, Data?) -> Void) {
        lock.lock()
        guard !finishRequested && !cancelled else { lock.unlock(); return }
        finishRequested = true
        accepting = false
        self.completion = completion
        let shouldStart = !processing
        processing = true
        lock.unlock()
        if shouldStart { queue.async { [self] in drain() } }
    }

    func cancel() {
        lock.lock()
        accepting = false
        cancelled = true
        pending = nil
        completion = nil
        lock.unlock()
        queue.async { [self] in stitcher.reset() }
    }

    private func drain() {
        while true {
            lock.lock()
            if cancelled { processing = false; lock.unlock(); return }
            let frame = pending
            pending = nil
            if frame == nil {
                let completion = completion
                self.completion = nil
                processing = false
                lock.unlock()
                if let completion {
                    let image = stitcher.finalImage()
                    let data = image.flatMap { try? ScreenshotWriter.pngData(from: $0) }
                    lock.lock()
                    let shouldComplete = !cancelled
                    lock.unlock()
                    if shouldComplete { completion(image, data) }
                    stitcher.reset()
                }
                return
            }
            lock.unlock()
            autoreleasepool {
                let image: CGImage?
                switch frame! {
                case .image(let value): image = value
                case .pixelBuffer(let buffer):
                    let source = CIImage(cvPixelBuffer: buffer)
                    image = context.createCGImage(source, from: source.extent)
                }
                let result = image.map { stitcher.append($0) } ?? .failed
                if result == .limitReached || result == .failed {
                    lock.lock()
                    accepting = false
                    pending = nil
                    lock.unlock()
                }
                let now = Date()
                let preview = now.timeIntervalSince(lastPreview) >= 0.15 ? stitcher.previewImage() : nil
                if preview != nil { lastPreview = now }
                onUpdate?(result, preview, stitcher.stitchedPixelHeight)
            }
        }
    }
}
