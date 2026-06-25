import AppKit
import OSLog

private let captureLogger = Logger(subsystem: "com.ethan.snapnook", category: "Capture")

final class CaptureCoordinator {
    private enum ActiveFlow {
        case captureArea
        case captureText
    }

    private let permissionService = ScreenCapturePermissionService()
    private let previewController = ScreenshotPreviewController()
    private let ocrService = OCRService()
    private let toastController = ToastController()
    private var overlayController: CaptureOverlayController?
    private var activeFlow: ActiveFlow?
    private var ocrTask: Task<Void, Never>?

    func captureArea() {
        startCapture(flow: .captureArea, mode: .screenshot)
    }

    func captureText() {
        startCapture(flow: .captureText, mode: .textOCR)
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
        overlayController = CaptureOverlayController(mode: mode) { [weak self] result in
            guard let self else { return }

            if case .captured(let rect, let screenFrame) = result {
                captureLogger.notice("Overlay captured rect: x=\(rect.origin.x), y=\(rect.origin.y), width=\(rect.size.width), height=\(rect.size.height).")
                self.handleCapture(rect: rect, screenFrame: screenFrame, flow: flow)
            } else {
                captureLogger.notice("Overlay capture cancelled.")
                self.activeFlow = nil
            }

            self.overlayController?.cleanup()
            self.overlayController = nil
        }
        overlayController?.show()
    }

    private func handleCapture(rect: CGRect, screenFrame: CGRect, flow: ActiveFlow) {
        switch flow {
        case .captureArea:
            capture(rect: rect, screenFrame: screenFrame)
        case .captureText:
            recognizeText(in: rect, screenFrame: screenFrame)
        }
    }

    private func capture(rect: CGRect, screenFrame: CGRect) {
        captureLogger.notice("Screen capture started.")

        guard let image = ScreenCapturer.capture(rect: rect, screenFrame: screenFrame) else {
            captureLogger.error("Screen capture returned nil.")
            AlertPresenter.show(message: "Capture failed.", informativeText: "SnapNook could not capture the selected area.")
            activeFlow = nil
            return
        }

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

    private func recognizeText(in rect: CGRect, screenFrame: CGRect) {
        captureLogger.notice("OCR capture started.")
        toastController.show(message: "Recognizing text...", duration: 2.5)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            guard let image = ScreenCapturer.capture(rect: rect, screenFrame: screenFrame) else {
                captureLogger.error("OCR screen capture returned nil.")
                self.toastController.show(message: "OCR failed.")
                self.activeFlow = nil
                return
            }

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
    }
}
