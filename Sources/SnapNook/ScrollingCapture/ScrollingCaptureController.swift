import AppKit

final class ScrollingCaptureController {
    private let onFinish: (ScreenshotPreviewItem) -> Void
    private let onCancel: () -> Void
    private var state: ScrollingCaptureState = .idle
    private var screen: NSScreen?
    private var selectionWindow: ScrollingSelectionWindow?
    private var selectionView: ScrollingSelectionOverlayView?
    private var previewPanel: ScrollingPreviewPanel?
    private var controlPanel: ScrollingCaptureControlPanel?
    private var escapeShortcut: ScrollingEscapeShortcut?
    private var pointerTimer: Timer?
    private var pipeline: ScrollingCapturePipeline?
    private var stream: ScrollingCaptureStream?
    private var startTask: Task<Void, Never>?
    private var lastResult: ScrollingStitcher.AppendResult = .unchanged
    private var lastImage: NSImage?
    private var pixelHeight = 0
    private var didCleanup = false

    init(onFinish: @escaping (ScreenshotPreviewItem) -> Void, onCancel: @escaping () -> Void) {
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    func startSelection() {
        guard state == .idle else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
            onCancel()
            return
        }
        self.screen = screen
        state = .selecting
        let view = ScrollingSelectionOverlayView(screen: screen) { [weak self] interaction in
            switch interaction {
            case .startCapture: self?.startCapture()
            case .done: self?.finishCapture()
            case .cancel, .escape: self?.cancelCapture()
            }
        }
        let window = ScrollingSelectionWindow(screen: screen, contentView: view)
        selectionView = view
        selectionWindow = window
        escapeShortcut = ScrollingEscapeShortcut { [weak self] in self?.cancelCapture() }
        window.show()
    }

    private func startCapture() {
        guard state == .selecting, let selectionView, let selectionWindow, let screen,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        state = .capturing
        let rect = selectionView.selectedScreenRect
        selectionView.setCapturing(true)
        selectionWindow.ignoresMouseEvents = true
        let preview = ScrollingPreviewPanel(selectionRect: rect, screen: screen)
        previewPanel = preview
        preview.orderFrontRegardless()
        let controls = ScrollingCaptureControlPanel(selectionRect: rect, screen: screen)
        controls.onDone = { [weak self] in self?.finishCapture() }
        controls.onCancel = { [weak self] in self?.cancelCapture() }
        controlPanel = controls
        controls.orderFrontRegardless()

        let pipeline = ScrollingCapturePipeline()
        self.pipeline = pipeline
        pipeline.onUpdate = { [weak self] result, image, height in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.state == .capturing else { return }
                if self.lastResult != .failed { self.lastResult = result }
                if let image { self.lastImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)) }
                self.pixelHeight = height
                self.updateStatus()
                if result == .limitReached || result == .failed { self.stopStream() }
            }
        }
        let stream = ScrollingCaptureStream(pipeline: pipeline, rect: rect)
        self.stream = stream
        stream.onFailure = { [weak self] error in
            DispatchQueue.main.async { [weak self] in self?.captureFailed(error) }
        }
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.updateStatus() }
        startTask = Task { [weak self] in
            do {
                try await stream.start(rect: rect, screenFrame: screen.frame, displayID: displayID.uint32Value, scale: screen.backingScaleFactor)
                guard let self, self.state == .capturing else { await stream.stop(); return }
                self.startTask = nil
            } catch {
                guard let self, self.state == .capturing else { await stream.stop(); return }
                self.startTask = nil
                self.captureFailed(error)
            }
        }
    }

    private func updateStatus() {
        guard state == .capturing, let selectionView else { return }
        let status: String
        switch lastResult {
        case .limitReached: status = "64MP limit · Done or Cancel"
        case .failed: status = "Capture failed · Done or Cancel"
        default:
            if !selectionView.selectedScreenRect.contains(NSEvent.mouseLocation) {
                status = "Paused · Move into selection"
            } else if lastResult == .waitingForOverlap {
                status = "Scroll back to restore overlap"
            } else {
                status = "Capturing..."
            }
        }
        previewPanel?.update(image: lastImage, pixelHeight: pixelHeight, status: status)
    }

    private func finishCapture() {
        guard state == .capturing, let pipeline, let selectionView, let screen else { return }
        state = .finishing
        pointerTimer?.invalidate()
        previewPanel?.update(image: lastImage, pixelHeight: pixelHeight, status: "Finishing...")
        let rect = selectionView.selectedScreenRect
        let screenFrame = screen.frame
        let scale = screen.backingScaleFactor
        pipeline.finish { [weak self] image, data in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.state == .finishing else { return }
                guard let image, let data else {
                    self.cancelCapture()
                    AlertPresenter.show(message: "Scrolling Capture failed.", informativeText: "No confirmed image could be exported.")
                    return
                }
                let item = ScreenshotPreviewItem(image: NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)), pngData: data, createdAt: Date(), captureRect: rect, screenFrame: screenFrame)
                self.cleanup()
                self.onFinish(item)
            }
        }
        stopStream()
    }

    private func captureFailed(_ error: Error) {
        guard state == .capturing else { return }
        lastResult = .failed
        pipeline?.stopReceiving()
        stopStream()
        updateStatus()
        // Keep confirmed content available for Done after a stream failure.
    }

    private func cancelCapture() {
        guard state != .idle && state != .cancelled else { return }
        state = .cancelled
        pipeline?.cancel()
        cleanup()
        onCancel()
    }

    private func stopStream() {
        if let stream {
            Task { await stream.stop() }
            self.stream = nil
        }
    }

    private func cleanup() {
        guard !didCleanup else { return }
        didCleanup = true
        pointerTimer?.invalidate()
        pointerTimer = nil
        escapeShortcut = nil
        startTask?.cancel()
        startTask = nil
        stopStream()
        let selectionWindow = selectionWindow
        let previewPanel = previewPanel
        let controlPanel = controlPanel
        selectionWindow?.orderOut(nil)
        previewPanel?.orderOut(nil)
        controlPanel?.orderOut(nil)
        self.selectionWindow = nil
        selectionView = nil
        self.previewPanel = nil
        self.controlPanel = nil
        screen = nil
        pipeline = nil
        DispatchQueue.main.async {
            selectionWindow?.closeIfNeeded()
            previewPanel?.closeIfNeeded()
            controlPanel?.closeIfNeeded()
        }
        if state != .cancelled { state = .idle }
    }
}
