import AppKit
import Darwin
import XCTest
@testable import SnapNook

@MainActor
final class CaptureCursorTests: XCTestCase {
    func testBackgroundSelectionHidesCursorWithoutChangingForegroundAndRestoresOnce() throws {
        _ = NSApplication.shared
        guard !NSApp.isActive, try cursorIsVisible() else {
            throw XCTSkip("Requires an inactive test app and a visible system cursor")
        }
        let session = try startInputSession()
        defer { session.stop() }
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for mode in [CaptureSelectionMode.screenshot, .textOCR] {
            let controller = CaptureOverlayController(screens: [], mode: mode) { _ in }
            defer { controller.restoreCursor() }
            XCTAssertTrue(controller.hideCursor())
            XCTAssertTrue(controller.hideCursor())
            waitForCursor(visible: false)
            XCTAssertFalse(NSApp.isActive)
            XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, foreground)
            controller.cleanup()
            controller.cleanup()
            controller.restoreCursor()
            waitForCursor(visible: true)
            XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, foreground)
        }
    }

    private func startInputSession() throws -> CaptureInputSession {
        guard AXIsProcessTrusted() else {
            throw XCTSkip("Requires existing Accessibility permission to test the real selection input context")
        }
        let session = CaptureInputSession(onEvent: { _, _ in }, onFailure: {})
        guard session.start() else { throw XCTSkip("Could not create the selection input tap") }
        return session
    }

    private func waitForCursor(visible: Bool, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<20 {
            if (try? cursorIsVisible()) == visible { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(try cursorIsVisible(), visible, file: file, line: line)
    }

    private func cursorIsVisible() throws -> Bool {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGCursorIsVisible") else {
            throw XCTSkip("WindowServer cursor visibility probe is unavailable")
        }
        return unsafeBitCast(symbol, to: (@convention(c) () -> UInt32).self)() != 0
    }

    func testDeinitRestoresHiddenCursor() throws {
        _ = NSApplication.shared
        guard !NSApp.isActive, try cursorIsVisible() else {
            throw XCTSkip("Requires an inactive test app and a visible system cursor")
        }
        let session = try startInputSession()
        defer { session.stop() }
        var controller: CaptureOverlayController? = CaptureOverlayController(screens: [], mode: .screenshot) { _ in }
        XCTAssertTrue(controller!.hideCursor())
        waitForCursor(visible: false)
        controller = nil
        waitForCursor(visible: true)
    }
}
