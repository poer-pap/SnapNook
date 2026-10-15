import AppKit
import XCTest
@testable import SnapNook

@MainActor
final class PinnedScreenshotTests: XCTestCase {
    func testAspectRatioScaleHoverAndNonactivation() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        for size in [NSSize(width: 320, height: 180), NSSize(width: 8000, height: 16000)] {
            let controller = PinnedScreenshotWindowController(item: item(size), screen: screen)
            let window = try XCTUnwrap(controller.window)
            defer { window.close() }
            let view = try XCTUnwrap(window.contentView as? PinnedScreenshotView)
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.bounds.width / view.bounds.height, size.width / size.height, accuracy: 0.001)
            XCTAssertLessThanOrEqual(window.frame.height, screen.visibleFrame.height)
            XCTAssertEqual(window.level, .floating)
            XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel))
            XCTAssertFalse(window.canBecomeKey)
            XCTAssertFalse(window.canBecomeMain)
            let controls = try XCTUnwrap(view.subviews.last)
            let percentage = try XCTUnwrap(controls.subviews.compactMap { $0 as? NSTextField }.first)
            XCTAssertEqual(percentage.stringValue, "\(Int((view.bounds.width / size.width * 100).rounded()))%")
            XCTAssertTrue(controls.isHidden)
            let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, trackingNumber: 0, userData: nil))
            view.mouseEntered(with: event)
            XCTAssertFalse(controls.isHidden)
            XCTAssertFalse(controls.subviews.contains { $0 is NSButton }, "Hover icons have no actions yet")
            view.mouseExited(with: event)
            XCTAssertTrue(controls.isHidden)
        }
    }

    func testPinKeepsPreviewAndHidesPinnedWindowDuringCapture() throws {
        let app = NSApplication.shared
        let existing = Set(app.windows.map(ObjectIdentifier.init))
        defer {
            for window in app.windows where !existing.contains(ObjectIdentifier(window)) { window.close() }
        }
        let controller = ScreenshotPreviewController()
        controller.show(item: item(NSSize(width: 320, height: 180)))
        let previewPanel = try XCTUnwrap(app.windows.first {
            $0 is ScreenshotPreviewPanel && !existing.contains(ObjectIdentifier($0))
        })
        let preview = try XCTUnwrap(findPreview(in: try XCTUnwrap(previewPanel.contentView)))
        preview.onPin?()
        let pinned = try XCTUnwrap(app.windows.first { $0.contentView is PinnedScreenshotView })
        XCTAssertTrue(pinned.isVisible)
        XCTAssertTrue(previewPanel.isVisible)
        XCTAssertTrue(preview.isEnabled)
        XCTAssertNotNil(preview.superview)
        controller.hideForCapture()
        XCTAssertFalse(pinned.isVisible)
        controller.restoreAfterCapture()
        XCTAssertTrue(pinned.isVisible)
    }

    private func item(_ size: NSSize) -> ScreenshotPreviewItem {
        ScreenshotPreviewItem(image: NSImage(size: size), pngData: Data(), createdAt: Date(), captureRect: nil, screenFrame: .zero)
    }

    private func findPreview(in view: NSView) -> ScreenshotPreviewView? {
        if let preview = view as? ScreenshotPreviewView { return preview }
        return view.subviews.lazy.compactMap { self.findPreview(in: $0) }.first
    }
}
