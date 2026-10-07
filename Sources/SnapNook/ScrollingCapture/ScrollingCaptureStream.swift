import AppKit
import ScreenCaptureKit

final class ScrollingCaptureStream: NSObject, SCStreamOutput, SCStreamDelegate {
    private let outputQueue = DispatchQueue(label: "com.ethan.snapnook.scrolling.frames", qos: .userInitiated)
    private let pipeline: ScrollingCapturePipeline
    private let pointerRect: CGRect
    private var stream: SCStream?
    var onFailure: ((Error) -> Void)?

    init(pipeline: ScrollingCapturePipeline, rect: CGRect) {
        self.pipeline = pipeline
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        pointerRect = CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }

    @MainActor
    func start(rect: CGRect, screenFrame: CGRect, displayID: CGDirectDisplayID, scale: CGFloat) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayUnavailable
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let configuration = Self.configuration(rect: rect, screenFrame: screenFrame, scale: scale)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        self.stream = stream
        try await stream.startCapture()
    }

    static func configuration(rect: CGRect, screenFrame: CGRect, scale: CGFloat) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(x: rect.minX - screenFrame.minX, y: screenFrame.maxY - rect.maxY, width: rect.width, height: rect.height)
        configuration.width = Int((rect.width * scale).rounded())
        configuration.height = Int((rect.height * scale).rounded())
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = false
        configuration.capturesAudio = false
        return configuration
    }

    @MainActor
    func stop() async {
        if let stream { try? await stream.stopCapture() }
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pointer = CGEvent(source: nil)?.location,
              let buffer = sampleBuffer.imageBuffer else { return }
        pipeline.submit(.pixelBuffer(buffer), pointerInsideSelection: pointerRect.contains(pointer))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onFailure?(error)
    }

    private enum CaptureError: LocalizedError {
        case displayUnavailable
        var errorDescription: String? { "The selected display is no longer available." }
    }
}
