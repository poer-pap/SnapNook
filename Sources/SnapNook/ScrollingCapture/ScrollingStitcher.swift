import AppKit
import CoreGraphics

final class ScrollingStitcher {
    private enum Constants {
        static let minOverlapRatio: CGFloat = 0.15
        static let maxOverlapRatio: CGFloat = 0.985
        static let duplicateOverlapRatio: CGFloat = 0.995
        static let duplicateFrameScore: Double = 3
        static let goodMatchScore: Double = 30
        static let weakMatchScore: Double = 55
    }

    private struct OverlapMatch {
        let height: Int
        let score: Double

        var isReliable: Bool {
            score <= Constants.goodMatchScore
        }

        var isUsable: Bool {
            score <= Constants.weakMatchScore
        }
    }

    private(set) var acceptedCaptureCount = 0
    private var stitchedImage: CGImage?
    private var previousFrame: CGImage?
    private var scale: CGFloat = 1

    var stitchedPixelHeight: Int {
        stitchedImage?.height ?? 0
    }

    var previewImage: NSImage? {
        guard let stitchedImage else { return nil }
        return NSImage(cgImage: stitchedImage, size: NSSize(width: CGFloat(stitchedImage.width) / scale, height: CGFloat(stitchedImage.height) / scale))
    }

    func reset() {
        acceptedCaptureCount = 0
        stitchedImage = nil
        previousFrame = nil
        scale = 1
    }

    @discardableResult
    func append(_ frame: ScrollingCaptureFrame) -> Bool {
        guard let source = frame.image.normalizedCGImage() else { return false }
        let current = normalizedFrame(source)
        print("[ScrollCapture] frame size:", current.width, current.height)

        if acceptedCaptureCount == 0 {
            scale = max(1, CGFloat(current.width) / max(1, frame.image.size.width))
            stitchedImage = current
            previousFrame = current
            acceptedCaptureCount = 1
            print("[Stitcher] captures:", acceptedCaptureCount)
            print("[Stitcher] stitched size:", current.width, current.height)
            return true
        }

        guard let stitchedImage else { return false }
        let match = bestVerticalOverlap(previous: stitchedImage, current: current)
        print("[Stitcher] best overlap:", match.height, "score:", match.score)

        if isDuplicate(current: current, match: match) {
            print("[Stitcher] duplicate ignored")
            return false
        }

        guard match.isUsable else {
            print("[Stitcher] warning: unusable overlap match; capture ignored")
            return false
        }

        if !match.isReliable {
            print("[Stitcher] warning: weak overlap match; using best overlap")
        }

        let overlap = match.height
        let duplicateThreshold = Int(CGFloat(current.height) * Constants.duplicateOverlapRatio)
        if overlap >= duplicateThreshold {
            print("[Stitcher] duplicate ignored")
            return false
        }

        let appendY = max(0, min(current.height - 1, overlap))
        guard let newPart = current.cropping(to: CGRect(x: 0, y: appendY, width: current.width, height: current.height - appendY)) else {
            return false
        }

        self.stitchedImage = compose(top: stitchedImage, bottom: newPart)
        self.previousFrame = current
        acceptedCaptureCount += 1
        print("[Stitcher] appended height:", newPart.height)
        print("[Stitcher] captures:", acceptedCaptureCount)
        if let stitchedImage = self.stitchedImage {
            print("[Stitcher] stitched size:", stitchedImage.width, stitchedImage.height)
        }
        return true
    }

    func finalImage() -> NSImage? {
        previewImage
    }

    private func bestVerticalOverlap(previous: CGImage, current: CGImage) -> OverlapMatch {
        guard previous.width == current.width,
              let previousBitmap = Bitmap(cgImage: previous),
              let currentBitmap = Bitmap(cgImage: current)
        else {
            return OverlapMatch(height: 0, score: Double.greatestFiniteMagnitude)
        }

        let height = current.height
        let minOverlap = max(1, Int(CGFloat(height) * Constants.minOverlapRatio))
        let maxOverlap = min(height - 1, max(minOverlap, Int(CGFloat(height) * Constants.maxOverlapRatio)))
        let step = 2
        var bestOverlap = minOverlap
        var bestScore = Double.greatestFiniteMagnitude

        for overlap in stride(from: minOverlap, through: maxOverlap, by: step) {
            let score = differenceScore(
                previous: previousBitmap,
                previousStartY: previous.height - overlap,
                current: currentBitmap,
                currentStartY: 0,
                height: overlap,
                sampleStep: step
            )

            if score < bestScore {
                bestScore = score
                bestOverlap = overlap
            }
        }

        return OverlapMatch(height: bestOverlap, score: bestScore)
    }

    private func isDuplicate(current: CGImage, match: OverlapMatch) -> Bool {
        let duplicateOverlap = Int(CGFloat(current.height) * Constants.duplicateOverlapRatio)
        if match.height >= duplicateOverlap && match.score <= Constants.goodMatchScore {
            return true
        }

        guard let previousFrame,
              previousFrame.width == current.width,
              previousFrame.height == current.height,
              let previousBitmap = Bitmap(cgImage: previousFrame),
              let currentBitmap = Bitmap(cgImage: current)
        else {
            return false
        }

        let score = differenceScore(
            previous: previousBitmap,
            previousStartY: 0,
            current: currentBitmap,
            currentStartY: 0,
            height: current.height,
            sampleStep: max(4, current.height / 100)
        )
        return score <= Constants.duplicateFrameScore
    }

    private func differenceScore(
        previous: Bitmap,
        previousStartY: Int,
        current: Bitmap,
        currentStartY: Int,
        height: Int,
        sampleStep: Int
    ) -> Double {
        var total: Double = 0
        var count = 0
        let xStep = max(4, previous.width / 80)

        for yOffset in stride(from: 0, to: height, by: sampleStep) {
            let previousY = previousStartY + yOffset
            let currentY = currentStartY + yOffset
            guard previousY >= 0, previousY < previous.height, currentY >= 0, currentY < current.height else {
                continue
            }

            for x in stride(from: 0, to: previous.width, by: xStep) {
                total += abs(Double(previous.luma(x: x, y: previousY)) - Double(current.luma(x: x, y: currentY)))
                count += 1
            }
        }

        return count == 0 ? Double.greatestFiniteMagnitude : total / Double(count)
    }

    private func compose(top: CGImage, bottom: CGImage) -> CGImage? {
        let width = top.width
        let height = top.height + bottom.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .none
        context.draw(top, in: CGRect(x: 0, y: bottom.height, width: top.width, height: top.height))
        context.draw(bottom, in: CGRect(x: 0, y: 0, width: bottom.width, height: bottom.height))
        return context.makeImage()
    }

    private func normalizedFrame(_ image: CGImage) -> CGImage {
        guard let stitchedImage, image.width != stitchedImage.width else {
            return image
        }

        let newHeight = max(1, Int(round(CGFloat(image.height) * CGFloat(stitchedImage.width) / CGFloat(image.width))))
        guard let context = CGContext(
            data: nil,
            width: stitchedImage.width,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: stitchedImage.width, height: newHeight))
        print("[Stitcher] warning: resized frame width from", image.width, "to", stitchedImage.width)
        return context.makeImage() ?? image
    }
}

private struct Bitmap {
    let width: Int
    let height: Int
    private let bytes: [UInt8]
    private let bytesPerRow: Int

    init?(cgImage: CGImage) {
        width = cgImage.width
        height = cgImage.height
        bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = data
    }

    func luma(x: Int, y: Int) -> UInt8 {
        let index = y * bytesPerRow + x * 4
        guard index + 2 < bytes.count else { return 0 }
        let r = Double(bytes[index])
        let g = Double(bytes[index + 1])
        let b = Double(bytes[index + 2])
        return UInt8(max(0, min(255, 0.299 * r + 0.587 * g + 0.114 * b)))
    }
}

private extension NSImage {
    func normalizedCGImage() -> CGImage? {
        var rect = NSRect(origin: .zero, size: size)
        if let cgImage = cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return cgImage
        }

        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmap.cgImage
    }
}
