import AppKit
import OSLog

private let captureLogger = Logger(subsystem: "com.ethan.snapnook", category: "Capture")

final class CaptureCoordinator {
    private enum ActiveFlow {
        case captureArea
        case captureText
        case scrollingCapture
    }

    private let permissionService = ScreenCapturePermissionService()
    private let previewController = ScreenshotPreviewController()
    private let ocrService = OCRService()
    private let toastController = ToastController()
    private var overlayController: CaptureOverlayController?
    private var scrollingCaptureController: ScrollingCaptureController?
    private var activeFlow: ActiveFlow?
    private var ocrTask: Task<Void, Never>?

    func captureArea() {
        startCapture(flow: .captureArea, mode: .screenshot)
    }

    func captureText() {
        startCapture(flow: .captureText, mode: .textOCR)
    }

    func scrollingCapture() {
        guard activeFlow == nil, overlayController == nil, ocrTask == nil, scrollingCaptureController == nil else {
            captureLogger.notice("Ignoring duplicate scrolling capture request while busy.")
            return
        }

        guard permissionService.hasPermission else {
            captureLogger.notice("Screen capture permission missing.")
            permissionService.requestPermission()
            return
        }

        activeFlow = .scrollingCapture
        let controller = ScrollingCaptureController(
            onFinish: { [weak self] item in
                self?.handleScrollingCaptureFinished(item: item)
            },
            onCancel: { [weak self] in
                captureLogger.notice("Scrolling capture cancelled.")
                self?.scrollingCaptureController = nil
                self?.activeFlow = nil
            }
        )
        scrollingCaptureController = controller
        controller.startSelection()
    }

    private func startCapture(flow: ActiveFlow, mode: CaptureSelectionMode) {
        guard activeFlow == nil, overlayController == nil, ocrTask == nil else {
            captureLogger.notice("Ignoring duplicate capture request while busy.")
            return
        }

        captureLogger.notice("Capture area requested.")

        guard permissionService.hasPermission else {
            captureLogger.notice("Screen capture permission missing.")
            permissionService.requestPermission()
            return
        }

        activeFlow = flow
        guard let screens = ScreenCapturer.screens() else {
            activeFlow = nil
            if flow == .captureText {
                toastController.show(message: "OCR failed.")
            } else {
                AlertPresenter.show(message: "Capture failed.", informativeText: "SnapNook could not read the screen configuration.")
            }
            return
        }
        overlayController = CaptureOverlayController(screens: screens, mode: mode) { [weak self] result in
            guard let self else { return }

            if case .captured(let screen, let rect) = result {
                captureLogger.notice("Overlay captured rect: x=\(rect.origin.x), y=\(rect.origin.y), width=\(rect.size.width), height=\(rect.size.height).")
                self.handleCapture(screen: screen, rect: rect, flow: flow)
            } else if case .failed = result {
                self.activeFlow = nil
                self.toastController.show(message: flow == .captureText ? "OCR failed." : "Capture failed.")
            } else {
                captureLogger.notice("Overlay capture cancelled.")
                self.activeFlow = nil
            }

            self.overlayController?.cleanup()
            self.overlayController = nil
        }
        overlayController?.show()
    }

    private func handleCapture(screen: CaptureScreen, rect: CGRect, flow: ActiveFlow) {
        let capturedImage = ScreenCapturer.capture(screen: screen, rect: rect)
        overlayController?.cleanup()
        guard let image = capturedImage else {
            if flow == .captureText {
                toastController.show(message: "OCR failed.")
            } else {
                AlertPresenter.show(message: "Capture failed.", informativeText: "SnapNook could not capture the selected area.")
            }
            activeFlow = nil
            return
        }
        switch flow {
        case .captureArea:
            capture(image: image, rect: rect, screenFrame: screen.screenFrame)
        case .captureText:
            recognizeText(in: image)
        case .scrollingCapture:
            break
        }
    }

    private func capture(image: NSImage, rect: CGRect, screenFrame: CGRect) {
        do {
            let item = ScreenshotPreviewItem(
                image: image,
                pngData: try ScreenshotWriter.pngData(from: image),
                createdAt: Date(),
                captureRect: rect,
                screenFrame: screenFrame
            )
            previewController.show(item: item)
            captureLogger.notice("Screenshot preview shown.")
            activeFlow = nil
        } catch {
            captureLogger.error("Screenshot PNG encoding failed: \(error.localizedDescription, privacy: .public).")
            AlertPresenter.show(message: "Capture failed.", informativeText: error.localizedDescription)
            activeFlow = nil
        }
    }

    private func recognizeText(in image: NSImage) {
        captureLogger.notice("OCR capture started.")
        toastController.show(message: "Recognizing text...", duration: 2.5)

        self.ocrTask = Task { [weak self] in
            guard let self else { return }

            do {
                let rawText = try await self.ocrService.recognizeText(from: image)
                let recognizedText = OCRTextPostProcessor.process(rawText)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                print("[OCR] raw:", rawText)
                print("[OCR] processed:", recognizedText)

                await MainActor.run {
                    if recognizedText.isEmpty {
                        captureLogger.notice("OCR returned no text.")
                        self.toastController.show(message: "No text recognized.")
                    } else if ClipboardWriter.copy(text: recognizedText) {
                        captureLogger.notice("OCR text copied to clipboard.")
                        self.toastController.show(message: "Text copied.")
                    } else {
                        captureLogger.error("OCR text copy failed.")
                        self.toastController.show(message: "OCR failed.")
                    }

                    self.ocrTask = nil
                    self.activeFlow = nil
                }
            } catch {
                await MainActor.run {
                    captureLogger.error("OCR failed: \(error.localizedDescription, privacy: .public).")
                    self.toastController.show(message: "OCR failed.")
                    self.ocrTask = nil
                    self.activeFlow = nil
                }
            }
        }
    }

    private func handleScrollingCaptureFinished(item: ScreenshotPreviewItem) {
        previewController.show(item: item)
        captureLogger.notice("Scrolling capture preview shown.")
        scrollingCaptureController = nil
        activeFlow = nil
    }
}
