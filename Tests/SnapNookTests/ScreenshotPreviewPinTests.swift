import AppKit
import XCTest
@testable import SnapNook

@MainActor
final class ScreenshotPreviewPinTests: XCTestCase {
    func testPinMatchesCornerControlsAndInvokesCallback() throws {
        let view = ScreenshotPreviewView(item: ScreenshotPreviewItem(
            image: NSImage(size: NSSize(width: 10, height: 10)), pngData: Data(),
            createdAt: Date(), captureRect: nil, screenFrame: .zero
        ))
        view.layoutSubtreeIfNeeded()
        let buttons = allButtons(in: view)
        let pin = try XCTUnwrap(buttons.first { $0.toolTip == "Pin" })
        let close = try XCTUnwrap(buttons.first { $0.toolTip == "Close" })
        let controls = try XCTUnwrap(pin.superview)
        XCTAssertEqual(buttons.count, 5)
        XCTAssertEqual(pin.frame.size, NSSize(width: 22, height: 22))
        XCTAssertEqual(pin.frame.size, close.frame.size)
        XCTAssertEqual(controls.bounds.maxX - pin.frame.maxX, 6, accuracy: 0.01)
        XCTAssertEqual(controls.bounds.maxY - pin.frame.maxY, 6, accuracy: 0.01)
        XCTAssertEqual(pin.frame.maxY, close.frame.maxY, accuracy: 0.01)
        XCTAssertNotNil(pin.image)
        XCTAssertTrue(pin.image?.isTemplate == true)
        XCTAssertNotNil(pin.action)
        XCTAssertTrue(pin.target === view)
        XCTAssertEqual(controls.alphaValue, 0, "Pin shares the existing hover-only controls")
        var pinned = false
        view.onPin = { pinned = true }
        pin.performClick(nil)
        XCTAssertTrue(pinned)
        XCTAssertTrue(view.isEnabled)
    }

    private func allButtons(in view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { allButtons(in: $0) }
    }
}
