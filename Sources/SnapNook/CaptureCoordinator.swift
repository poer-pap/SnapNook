import AppKit
import OSLog

private let captureLogger = Logger(subsystem: "com.ethan.snapnook", category: "Capture")

final class CaptureCoordinator {
    private let permissionService = ScreenCapturePermissionService()
    private let previewController = ScreenshotPreviewController()
    private var overlayController: CaptureOverlayController?

    func captureArea() {
        captureLogger.notice("Capture area requested.")

        guard permissionService.hasPermission else {
            captureLogger.notice("Screen capture permission missing.")
            permissionService.requestPermission()
            return
        }

        overlayController = CaptureOverlayController { [weak self] result in
            guard let self else { return }

            if case .captured(let rect, let screenFrame) = result {
                captureLogger.notice("Overlay captured rect: x=\(rect.origin.x), y=\(rect.origin.y), width=\(rect.size.width), height=\(rect.size.height).")
                self.capture(rect: rect, screenFrame: screenFrame)
            } else {
                captureLogger.notice("Overlay capture cancelled.")
            }

            self.overlayController?.cleanup()
            self.overlayController = nil
        }
        overlayController?.show()
    }

    private func capture(rect: CGRect, screenFrame: CGRect) {
        captureLogger.notice("Screen capture started.")

        guard let image = ScreenCapturer.capture(rect: rect, screenFrame: screenFrame) else {
            captureLogger.error("Screen capture returned nil.")
            AlertPresenter.show(message: "Capture failed.", informativeText: "SnapNook could not capture the selected area.")
            return
        }

        do {
            let item = ScreenshotPreviewItem(
                image: image,
                pngData: try ScreenshotWriter.pngData(from: image),
                captureRect: rect,
                screenFrame: screenFrame
            )
            previewController.show(item: item)
            captureLogger.notice("Screenshot preview shown.")
        } catch {
            captureLogger.error("Screenshot PNG encoding failed: \(error.localizedDescription, privacy: .public).")
            AlertPresenter.show(message: "Capture failed.", informativeText: error.localizedDescription)
        }
    }
}
