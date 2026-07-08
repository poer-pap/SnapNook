import AppKit
import OSLog

private let scrollingLogger = Logger(subsystem: "com.ethan.snapnook", category: "ScrollingCapture")

final class ScrollingCaptureController {
    private enum Constants {
        static let captureInterval: TimeInterval = 0.2
    }

    private let onFinish: (NSImage, CGRect, CGRect) -> Void
    private let onCancel: () -> Void
    private var state: ScrollingCaptureState = .idle
    private var screen: NSScreen?
    private var selectionWindow: ScrollingSelectionWindow?
    private var selectionView: ScrollingSelectionOverlayView?
    private var previewPanel: ScrollingPreviewPanel?
    private var controlPanel: ScrollingCaptureControlPanel?
    private var keyMonitor: Any?
    private var captureTimer: Timer?
    private let stitcher = ScrollingStitcher()
    private var isCapturingFrame = false
    private var didCleanup = false

    init(onFinish: @escaping (NSImage, CGRect, CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    deinit {
        cleanup()
    }

    var isActive: Bool {
        state != .idle && state != .cancelled
    }

    func startSelection() {
        guard state == .idle || state == .cancelled else {
            scrollingLogger.notice("Ignoring duplicate scrolling capture request.")
            return
        }

        didCleanup = false
        stitcher.reset()
        let targetScreen = NSScreen.screenContainingMouse ?? NSScreen.main
        guard let targetScreen else { return }

        screen = targetScreen
        state = .selecting

        let view = ScrollingSelectionOverlayView(screen: targetScreen) { [weak self] interaction in
            self?.handle(interaction)
        }
        let window = ScrollingSelectionWindow(screen: targetScreen, contentView: view)
        selectionView = view
        selectionWindow = window
        window.show()
    }

    private func handle(_ interaction: ScrollingSelectionOverlayView.Interaction) {
        switch interaction {
        case .startCapture:
            startCapture()
        case .done:
            finishCapture()
        case .cancel, .escape:
            cancelCapture()
        }
    }

    private func startCapture() {
        guard state == .selecting,
              let selectionView,
              let selectionWindow,
              let screen
        else {
            return
        }

        state = .capturing
        let selectionRect = selectionView.selectedScreenRect
        selectionView.setCapturing(true)
        selectionWindow.ignoresMouseEvents = true

        let previewPanel = ScrollingPreviewPanel(selectionRect: selectionRect, screen: screen)
        previewPanel.orderFrontRegardless()
        self.previewPanel = previewPanel

        let controlPanel = ScrollingCaptureControlPanel(selectionRect: selectionRect, screen: screen)
        controlPanel.onDone = { [weak self] in self?.finishCapture() }
        controlPanel.onCancel = { [weak self] in self?.cancelCapture() }
        controlPanel.orderFrontRegardless()
        self.controlPanel = controlPanel

        installEventMonitors()
        startContinuousCapture()
        captureFrame()
    }

    private func installEventMonitors() {
        removeEventMonitors()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancelCapture()
                return nil
            }
            return event
        }
    }

    private func captureFrame() {
        guard state == .capturing,
              !isCapturingFrame,
              let selectionView,
              let selectionWindow,
              let screen
        else {
            return
        }

        isCapturingFrame = true
        let rect = selectionView.selectedScreenRect

        defer {
            isCapturingFrame = false
        }

        guard let image = ScreenCapturer.capture(
            rect: rect,
            screenFrame: screen.frame,
            belowWindowID: CGWindowID(selectionWindow.windowNumber)
        ) else {
            scrollingLogger.error("Scrolling capture frame returned nil.")
            return
        }

        let didUpdate = stitcher.append(ScrollingCaptureFrame(image: image, capturedAt: Date()))
        if didUpdate {
            previewPanel?.update(image: stitcher.previewImage, pixelHeight: stitcher.stitchedPixelHeight)
        }
    }

    private func startContinuousCapture() {
        captureTimer?.invalidate()
        captureTimer = Timer.scheduledTimer(withTimeInterval: Constants.captureInterval, repeats: true) { [weak self] _ in
            self?.captureFrame()
        }
    }

    private func finishCapture() {
        guard state == .capturing else { return }
        state = .finishing
        captureTimer?.invalidate()
        captureTimer = nil
        removeEventMonitors()

        guard let selectionView,
              let screen,
              let finalImage = stitcher.finalImage()
        else {
            cleanup()
            onCancel()
            return
        }

        let rect = selectionView.selectedScreenRect
        cleanup()
        onFinish(finalImage, rect, screen.frame)
    }

    private func cancelCapture() {
        guard state != .idle && state != .cancelled else { return }
        state = .cancelled
        cleanup()
        onCancel()
    }

    private func cleanup() {
        guard !didCleanup else { return }
        didCleanup = true
        captureTimer?.invalidate()
        captureTimer = nil
        removeEventMonitors()

        selectionWindow?.closeIfNeeded()
        previewPanel?.closeIfNeeded()
        controlPanel?.closeIfNeeded()
        selectionWindow = nil
        selectionView = nil
        previewPanel = nil
        controlPanel = nil
        screen = nil
        isCapturingFrame = false
        stitcher.reset()

        if state != .cancelled {
            state = .idle
        }
    }

    private func removeEventMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

private extension NSScreen {
    static var screenContainingMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) }
    }
}
