import AppKit
import OSLog

private let previewLogger = Logger(subsystem: "com.ethan.snapnook", category: "ScreenshotPreview")

final class ScreenshotPreviewController {
    private static let previewInset: CGFloat = 24
    private let writer = ScreenshotWriter()
    private var panel: ScreenshotPreviewPanel?
    private var timer: Timer?
    private var isPinned = false

    func show(item: ScreenshotPreviewItem) {
        close()

        let panel = ScreenshotPreviewPanel(contentRect: NSRect(origin: .zero, size: ScreenshotPreviewPanel.previewPanelSize))
        let view = ScreenshotPreviewView(image: item.image)

        view.onCopy = {
            ClipboardWriter.copy(image: item.image)
            previewLogger.notice("Screenshot preview copied to clipboard.")
        }
        view.onSave = { [weak self] in
            do {
                let fileURL = try self?.writer.write(data: item.pngData)
                previewLogger.notice("Screenshot preview saved to \(fileURL?.path ?? "", privacy: .public).")
            } catch {
                previewLogger.error("Screenshot preview save failed: \(error.localizedDescription, privacy: .public).")
                AlertPresenter.show(message: "Save failed.", informativeText: error.localizedDescription)
            }
        }
        view.onClose = { [weak self] in
            self?.close()
        }
        view.onPin = { [weak self] in
            self?.pin()
        }
        view.onHoverChanged = { [weak self] isHovering in
            if isHovering {
                self?.pauseAutoClose()
            } else {
                self?.startAutoClose()
            }
        }

        panel.contentView = view
        positionPreviewPanel(panel, for: item)
        panel.orderFrontRegardless()
        self.panel = panel
        startAutoClose()
    }

    func positionPreviewPanel(_ panel: NSPanel, for item: ScreenshotPreviewItem) {
        let screen = Self.screen(for: item) ?? NSScreen.screenContainingMouse ?? NSScreen.main
        let frame = Self.previewFrame(size: ScreenshotPreviewPanel.previewPanelSize, screen: screen)
        panel.setFrame(frame, display: true)
    }

    private func pin() {
        isPinned = true
        pauseAutoClose()
    }

    private func startAutoClose() {
        guard !isPinned else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            self?.close()
        }
    }

    private func pauseAutoClose() {
        timer?.invalidate()
        timer = nil
    }

    private func close() {
        pauseAutoClose()
        panel?.closeIfNeeded()
        panel = nil
        isPinned = false
    }

    private static func previewFrame(size: NSSize, screen: NSScreen?) -> NSRect {
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        return NSRect(
            x: visibleFrame.minX + previewInset,
            y: visibleFrame.minY + previewInset,
            width: size.width,
            height: size.height
        )
    }

    private static func screen(for item: ScreenshotPreviewItem) -> NSScreen? {
        if let captureRect = item.captureRect {
            let center = CGPoint(x: captureRect.midX, y: captureRect.midY)
            if let match = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
                return match
            }
        }

        return NSScreen.screens.first { $0.frame.intersects(item.screenFrame) }
    }
}

private extension NSScreen {
    static var screenContainingMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) }
    }
}
