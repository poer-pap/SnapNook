import AppKit
import XCTest
@testable import SnapNook

@MainActor
final class ScreenshotPreviewEditTests: XCTestCase {
    func testEditingKeepsPreviewUntilManuallyClosed() async throws {
        let app = NSApplication.shared
        let existingWindows = Set(app.windows.map(ObjectIdentifier.init))
        let controller = ScreenshotPreviewController()
        defer {
            for window in app.windows where !existingWindows.contains(ObjectIdentifier(window)) {
                window.close()
            }
        }
        controller.show(item: ScreenshotPreviewItem(
            image: NSImage(size: NSSize(width: 10, height: 10)), pngData: Data(),
            createdAt: Date(), captureRect: nil, screenFrame: .zero
        ))
        let panel = try XCTUnwrap(app.windows.first {
            $0 is ScreenshotPreviewPanel && !existingWindows.contains(ObjectIdentifier($0))
        })
        let view = try XCTUnwrap(panel.contentView.flatMap(findPreview))
        view.onEdit?()
        XCTAssertTrue(app.windows.contains { $0.title == "SnapNook Editor" && $0.isVisible })
        XCTAssertTrue(view.isEnabled, "Opening the editor must not start removing the preview")
        try await Task.sleep(nanoseconds: 650_000_000)
        XCTAssertNotNil(view.superview)
        XCTAssertTrue(panel.isVisible)

        view.onClose?()
        XCTAssertFalse(view.isEnabled)
        try await Task.sleep(nanoseconds: 650_000_000)
        XCTAssertNil(view.superview)
        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(app.windows.contains { $0.title == "SnapNook Editor" && $0.isVisible })
    }

    private func findPreview(in view: NSView) -> ScreenshotPreviewView? {
        if let preview = view as? ScreenshotPreviewView { return preview }
        return view.subviews.lazy.compactMap { self.findPreview(in: $0) }.first
    }
}
