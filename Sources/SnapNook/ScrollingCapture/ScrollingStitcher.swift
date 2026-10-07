import AppKit

/// Confined to the capture processing queue. Rows and offsets use top-left image coordinates.
final class ScrollingStitcher {
    enum AppendResult: Equatable {
        case appended, unchanged, waitingForOverlap, limitReached, failed
    }

    private let pixelLimit: Int
    private var strips: [CGImage] = []
    private var previous: Viewport?
    private var anchor: Viewport?
    private var position = 0
    private var endPosition = 0
    private(set) var stitchedPixelHeight = 0
    private var reachedLimit = false

    init(pixelLimit: Int = 64_000_000) {
        self.pixelLimit = pixelLimit
    }

    func reset() {
        strips.removeAll()
        previous = nil
        anchor = nil
        position = 0
        endPosition = 0
        stitchedPixelHeight = 0
        reachedLimit = false
    }

    @discardableResult
    func append(_ image: CGImage) -> AppendResult {
        guard !reachedLimit else { return .limitReached }
        guard let current = Viewport(image) else { return .failed }
        guard let previous, let anchor else {
            guard image.width * image.height <= pixelLimit else {
                reachedLimit = true
                return .limitReached
            }
            // Materialize a separate backing store instead of retaining an entire capture IOSurface.
            guard let first = copiedStrip(image, from: 0) else { return .failed }
            strips = [first]
            self.previous = current
            self.anchor = current
            stitchedPixelHeight = image.height
            return .appended
        }
        guard current.image.width == previous.image.width,
              current.image.height == previous.image.height else { return .failed }
        guard let delta = displacement(from: previous, to: current) else { return .waitingForOverlap }
        let nextPosition = position + delta
        if nextPosition <= endPosition {
            self.previous = current
            position = nextPosition
            return .unchanged
        }

        // Verify directly against the last appended viewport; do not accumulate tracking drift.
        let extensionHeight = nextPosition - endPosition
        guard extensionHeight <= image.height * 3 / 4,
              displacement(from: anchor, to: current) == extensionHeight else { return .waitingForOverlap }
        guard image.width * (stitchedPixelHeight + extensionHeight) <= pixelLimit else {
            reachedLimit = true
            return .limitReached
        }
        guard let strip = copiedStrip(image, from: image.height - extensionHeight) else { return .failed }
        strips.append(strip)
        stitchedPixelHeight += extensionHeight
        position = nextPosition
        endPosition = nextPosition
        self.previous = current
        self.anchor = current
        return .appended
    }

    func finalImage() -> CGImage? {
        render(maxSize: nil)
    }

    func previewImage() -> CGImage? {
        render(maxSize: CGSize(width: 196, height: 380))
    }

    private func render(maxSize: CGSize?) -> CGImage? {
        guard let first = strips.first else { return nil }
        let scale = maxSize.map { min(1, min($0.width / CGFloat(first.width), $0.height / CGFloat(stitchedPixelHeight))) } ?? 1
        let width = max(1, Int((CGFloat(first.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(stitchedPixelHeight) * scale).rounded()))
        guard let context = Self.context(width: width, height: height) else { return nil }
        context.interpolationQuality = maxSize == nil ? .none : .medium
        var top = 0
        for strip in strips {
            context.draw(strip, in: CGRect(x: 0, y: CGFloat(stitchedPixelHeight - top - strip.height) * CGFloat(height) / CGFloat(stitchedPixelHeight), width: CGFloat(width), height: CGFloat(strip.height) * CGFloat(height) / CGFloat(stitchedPixelHeight)))
            top += strip.height
        }
        return context.makeImage()
    }

    private func copiedStrip(_ image: CGImage, from row: Int) -> CGImage? {
        guard let crop = image.cropping(to: CGRect(x: 0, y: row, width: image.width, height: image.height - row)),
              let context = Self.context(width: crop.width, height: crop.height) else { return nil }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        return context.makeImage()
    }

    private static func context(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private func displacement(from previous: Viewport, to current: Viewport) -> Int? {
        let height = previous.full.height
        // Static frames, including blank pages, do not need a unique displacement.
        if score(previous.full, current.full, shift: 0) <= 0.8 { return 0 }
        let coarseLimit = previous.small.height * 3 / 4
        let coarseScores = (-coarseLimit...coarseLimit).map {
            (shift: $0, score: score(previous.small, current.small, shift: $0))
        }
        let candidates = coarseScores.filter { candidate in
            let index = candidate.shift + coarseLimit
            return (index == 0 || candidate.score <= coarseScores[index - 1].score)
                && (index == coarseScores.count - 1 || candidate.score <= coarseScores[index + 1].score)
        }.sorted { $0.score < $1.score }.prefix(8)
        let factor = Double(height) / Double(previous.small.height)
        let radius = Int(ceil(factor)) + 1
        var shifts = Set<Int>()
        for candidate in candidates {
            let center = Int((Double(candidate.shift) * factor).rounded())
            for shift in (center - radius)...(center + radius) where abs(shift) <= height * 3 / 4 {
                shifts.insert(shift)
            }
        }
        let ranked = shifts.map { (shift: $0, score: score(previous.full, current.full, shift: $0, dense: true)) }
            .sorted { $0.score < $1.score }
        guard let best = ranked.first, best.score <= 5 else { return nil }
        // Repeated textures and weakly distinguished offsets must not create new content.
        if let alternative = ranked.first(where: { abs($0.shift - best.shift) > 2 }),
           alternative.score <= best.score + 1.5 { return nil }
        return best.shift
    }

    private func score(_ a: GrayBitmap, _ b: GrayBitmap, shift: Int, dense: Bool = false) -> Double {
        let overlap = a.height - abs(shift)
        guard overlap > 0 else { return .infinity }
        let aStart = max(0, shift)
        let bStart = max(0, -shift)
        let yStep = dense ? 1 : max(1, overlap / 100)
        let xStep = max(1, a.width / 64)
        return a.bytes.withUnsafeBufferPointer { aBytes in
            b.bytes.withUnsafeBufferPointer { bBytes in
                var difference = 0
                var samples = 0
                let aBase = aBytes.baseAddress!
                let bBase = bBytes.baseAddress!
                for row in stride(from: 0, to: overlap, by: yStep) {
                    let aRow = aBase + (aStart + row) * a.width
                    let bRow = bBase + (bStart + row) * b.width
                    for x in stride(from: 0, to: a.width, by: xStep) {
                        difference += abs(Int(aRow[x]) - Int(bRow[x]))
                        samples += 1
                    }
                }
                return Double(difference) / Double(samples)
            }
        }
    }
}

private struct Viewport {
    let image: CGImage
    let full: GrayBitmap
    let small: GrayBitmap

    init?(_ image: CGImage) {
        guard let full = GrayBitmap(image, width: image.width, height: image.height),
              let small = GrayBitmap(image, width: min(64, image.width), height: min(240, image.height)) else { return nil }
        self.image = image
        self.full = full
        self.small = small
    }
}

private struct GrayBitmap {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(_ image: CGImage, width: Int, height: Int) {
        self.width = width
        self.height = height
        var bytes = [UInt8](repeating: 0, count: width * height)
        let succeeded = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard succeeded else { return nil }
        self.bytes = bytes
    }
}
