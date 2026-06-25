import AppKit
import Vision

enum OCRError: LocalizedError {
    case cgImageUnavailable

    var errorDescription: String? {
        switch self {
        case .cgImageUnavailable:
            return "SnapNook could not prepare the captured image for OCR."
        }
    }
}

final class OCRService {
    func recognizeText(from image: NSImage) async throws -> String {
        guard let cgImage = image.snapNookCGImage else {
            throw OCRError.cgImageUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "en-US"]
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                do {
                    try handler.perform([request])
                    let observations = request.results ?? []
                    let text = Self.joinedText(from: observations)
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func joinedText(from observations: [VNRecognizedTextObservation]) -> String {
        let sorted = observations.sorted { lhs, rhs in
            let yDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
            if yDelta > 0.025 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        return sorted
            .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

private extension NSImage {
    var snapNookCGImage: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        if let cgImage = cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            return cgImage
        }

        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.cgImage
    }
}
