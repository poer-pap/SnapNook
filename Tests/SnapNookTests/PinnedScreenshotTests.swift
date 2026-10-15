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
            let close = try button("Close", in: view)
            let percentage = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first)
            XCTAssertEqual(percentage.stringValue, "\(Int((view.scale * 100).rounded()))%")
            view.mouseExited(with: event(window))
            XCTAssertTrue(close.isHidden)
            view.mouseEntered(with: event(window))
            XCTAssertFalse(close.isHidden)
            XCTAssertEqual(close.frame.size, NSSize(width: 22, height: 22))
            view.mouseExited(with: event(window))
            XCTAssertTrue(close.isHidden)
        }
    }

    func testLockFreezesSizeAndLeavesOnlyUnlockVisible() throws {
        let controller = PinnedScreenshotWindowController(item: item(NSSize(width: 540, height: 360)), screen: try XCTUnwrap(NSScreen.screens.first))
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        let view = try XCTUnwrap(window.contentView as? PinnedScreenshotView)
        view.layoutSubtreeIfNeeded()
        view.mouseEntered(with: event(window))
        let lock = try button("Lock", in: view)
        let before = window.frame
        lock.performClick(nil)
        XCTAssertTrue(view.isLocked)
        XCTAssertEqual(lock.toolTip, "Unlock")
        XCTAssertTrue(view.subviews.filter { $0 !== lock && !($0 is NSImageView) }.allSatisfy(\.isHidden))
        view.mouseExited(with: event(window))
        XCTAssertFalse(lock.isHidden)
        view.resize(to: 0.2)
        XCTAssertEqual(window.frame, before)
        lock.performClick(nil)
        XCTAssertFalse(view.isLocked)
        XCTAssertEqual(window.frame, before)
        view.mouseEntered(with: event(window))
        XCTAssertFalse(try button("Close", in: view).isHidden)
    }

    func testZoomBoundsAndPersistentCloseAtMinimum() throws {
        let controller = PinnedScreenshotWindowController(item: item(NSSize(width: 540, height: 360)), screen: try XCTUnwrap(NSScreen.screens.first))
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        let view = try XCTUnwrap(window.contentView as? PinnedScreenshotView)
        view.resize(to: 0.00001)
        view.layoutSubtreeIfNeeded()
        let minimum = view.scale
        XCTAssertGreaterThanOrEqual(minimum, 0.1)
        XCTAssertGreaterThanOrEqual(view.bounds.width, 96)
        XCTAssertGreaterThanOrEqual(view.bounds.height, 64)
        XCTAssertEqual(view.bounds.width / view.bounds.height, 1.5, accuracy: 0.01)
        view.mouseExited(with: event(window))
        let close = try button("Close", in: view)
        XCTAssertFalse(close.isHidden)
        XCTAssertTrue(view.bounds.contains(close.frame))
        XCTAssertTrue(view.hitTest(close.frame.center) === close)
        view.resize(to: 1000)
        XCTAssertLessThanOrEqual(view.scale, 4)
        XCTAssertLessThanOrEqual(window.frame.width, try XCTUnwrap(window.screen).visibleFrame.width)
        let percentage = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertEqual(percentage.stringValue, "\(Int((view.scale * 100).rounded()))%")
        view.resize(to: .nan)
        XCTAssertTrue(view.scale.isFinite)
    }

    func testWheelZoomChangesScaleAndIsIgnoredWhenLocked() throws {
        let controller = PinnedScreenshotWindowController(item: item(NSSize(width: 540, height: 360)), screen: try XCTUnwrap(NSScreen.screens.first))
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        let view = try XCTUnwrap(window.contentView as? PinnedScreenshotView)
        let cgEvent = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -2, wheel2: 0, wheel3: 0))
        let wheel = try XCTUnwrap(NSEvent(cgEvent: cgEvent))
        view.scrollWheel(with: wheel)
        XCTAssertLessThan(view.scale, 1)
        let resized = view.scale
        try button("Lock", in: view).performClick(nil)
        view.scrollWheel(with: wheel)
        XCTAssertEqual(view.scale, resized)
    }

    func testPinCloseIsIndependentAndCaptureRestoresOnlyOpenWindows() async throws {
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
        let view = try XCTUnwrap(pinned.contentView as? PinnedScreenshotView)
        XCTAssertTrue(pinned.isVisible)
        view.onDragStarted?()
        XCTAssertTrue(controller.isDragging)
        let session = NSDraggingSession()
        view.draggingSession(session, willBeginAt: .zero)
        view.draggingSession(session, endedAt: .zero, operation: [])
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(controller.isDragging)
        XCTAssertTrue(pinned.isVisible)
        XCTAssertTrue(previewPanel.isVisible)
        controller.hideForCapture()
        XCTAssertFalse(pinned.isVisible)
        controller.restoreAfterCapture()
        XCTAssertTrue(pinned.isVisible)
        view.mouseEntered(with: event(pinned))
        try button("Close", in: view).performClick(nil)
        try button("Close", in: view).performClick(nil)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(pinned.isVisible)
        controller.hideForCapture()
        controller.restoreAfterCapture()
        XCTAssertFalse(pinned.isVisible)
        XCTAssertTrue(previewPanel.isVisible)
        XCTAssertTrue(preview.isEnabled)
        XCTAssertNotNil(preview.superview)
    }

    func testSuccessfulFileDropClosesOnlyPinnedWindow() async throws {
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
        let view = try XCTUnwrap(pinned.contentView as? PinnedScreenshotView)
        view.onDragStarted?()
        let session = NSDraggingSession()
        view.draggingSession(session, willBeginAt: .zero)
        view.draggingSession(session, endedAt: .zero, operation: .copy)
        view.draggingSession(session, endedAt: .zero, operation: .copy)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(controller.isDragging)
        XCTAssertFalse(pinned.isVisible)
        controller.hideForCapture()
        controller.restoreAfterCapture()
        XCTAssertFalse(pinned.isVisible)
        XCTAssertTrue(previewPanel.isVisible)
        XCTAssertTrue(preview.isEnabled)
        XCTAssertNotNil(preview.superview)
    }

    func testFileDragUsesOriginalDataAndPreservesAcceptedFile() throws {
        _ = NSApplication.shared
        let data = Data([1, 2, 3, 4])
        let capture = ScreenshotPreviewItem(image: NSImage(size: NSSize(width: 540, height: 360)), pngData: data,
                                           createdAt: Date(), captureRect: nil, screenFrame: .zero)
        var view: PinnedScreenshotView? = PinnedScreenshotView(item: capture, scale: 0.5)
        let url = try XCTUnwrap(view).dragFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertEqual(try Data(contentsOf: url), data)
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(try view?.dragFileURL(), url)
        let session = NSDraggingSession()
        var completions = 0
        var closes = 0
        view?.onDragEnded = { completions += 1 }
        view?.onClose = { closes += 1 }
        XCTAssertEqual(view?.draggingSession(session, sourceOperationMaskFor: .outsideApplication), .copy)
        view?.draggingSession(session, willBeginAt: .zero)
        view?.draggingSession(session, endedAt: .zero, operation: .copy)
        view?.draggingSession(session, endedAt: .zero, operation: .copy)
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(closes, 1)
        view = nil
        XCTAssertEqual(try Data(contentsOf: url), data, "Accepted files must survive source closure for delayed target reads")
    }

    private func item(_ size: NSSize) -> ScreenshotPreviewItem {
        ScreenshotPreviewItem(image: NSImage(size: size), pngData: Data(), createdAt: Date(), captureRect: nil, screenFrame: .zero)
    }

    private func button(_ title: String, in view: NSView) throws -> NSButton {
        try XCTUnwrap(view.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == title })
    }

    private func event(_ window: NSWindow) -> NSEvent {
        NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
    }

    private func findPreview(in view: NSView) -> ScreenshotPreviewView? {
        if let preview = view as? ScreenshotPreviewView { return preview }
        return view.subviews.lazy.compactMap { self.findPreview(in: $0) }.first
    }
}

private extension NSRect {
    var center: NSPoint { NSPoint(x: midX, y: midY) }
}
