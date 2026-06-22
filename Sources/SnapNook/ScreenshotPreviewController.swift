import AppKit
import OSLog
import UniformTypeIdentifiers

private let previewLogger = Logger(subsystem: "com.ethan.snapnook", category: "ScreenshotPreview")

final class ScreenshotPreviewController {
    private static let previewInset: CGFloat = 24
    private let writer = ScreenshotWriter()
    private var panel: ScreenshotPreviewPanel?
    private var timer: Timer?
    private var isClosed = true

    func show(item: ScreenshotPreviewItem) {
        close()
        isClosed = false

        let panel = ScreenshotPreviewPanel(contentRect: NSRect(origin: .zero, size: ScreenshotPreviewPanel.previewPanelSize))
        let view = ScreenshotPreviewView(image: item.image)

        view.onCopy = { [weak self] in
            guard let self else { return }
            guard ClipboardWriter.copy(image: item.image, pngData: item.pngData) else {
                previewLogger.error("Screenshot preview copy failed.")
                AlertPresenter.show(message: "Copy failed.", informativeText: "SnapNook could not copy the captured image.")
                return
            }
            previewLogger.notice("Screenshot preview copied to clipboard.")
            self.close()
        }
        view.onSave = { [weak self] in
            self?.presentSavePanel(for: item)
        }
        view.onClose = { [weak self] in
            self?.close()
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

    private func startAutoClose() {
        guard !isClosed else { return }
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
        guard !isClosed else { return }
        isClosed = true
        pauseAutoClose()
        panel?.closeIfNeeded()
        panel = nil
    }

    private func presentSavePanel(for item: ScreenshotPreviewItem) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isClosed else { return }

            self.pauseAutoClose()
            NSApp.activate(ignoringOtherApps: true)

            let savePanel = NSSavePanel()
            savePanel.canCreateDirectories = true
            savePanel.isExtensionHidden = false
            savePanel.nameFieldStringValue = ScreenshotWriter.filename(createdAt: item.createdAt)
            savePanel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")

            if #available(macOS 11.0, *) {
                savePanel.allowedContentTypes = [.png]
            } else {
                savePanel.allowedFileTypes = [UTType.png.identifier]
            }

            savePanel.begin { [weak self] response in
                guard let self, !self.isClosed else { return }

                guard response == .OK, let fileURL = savePanel.url else {
                    self.startAutoClose()
                    return
                }

                do {
                    try self.writer.write(data: item.pngData, to: fileURL)
                    previewLogger.notice("Screenshot preview saved to \(fileURL.path, privacy: .public).")
                    self.close()
                } catch {
                    previewLogger.error("Screenshot preview save failed: \(error.localizedDescription, privacy: .public).")
                    AlertPresenter.show(message: "Save failed.", informativeText: error.localizedDescription)
                    self.startAutoClose()
                }
            }
        }
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
