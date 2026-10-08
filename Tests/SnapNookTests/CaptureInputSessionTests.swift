import AppKit
import XCTest
@testable import SnapNook

final class CaptureInputSessionTests: XCTestCase {
    func testSelectionInputIsConsumedUntilCaptureCleanup() throws {
        var received: [CGEventType] = []
        let session = CaptureInputSession(onEvent: { type, _ in received.append(type) }, onFailure: {
            XCTFail("Unexpected input failure")
        })
        let event = try XCTUnwrap(CGEvent(source: nil))
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp,
                     .keyDown, .keyUp, .flagsChanged, .scrollWheel] {
            XCTAssertTrue(session.receive(type: type, event: event))
        }
        // Keep suppressing input after mouse-up until the captured image is available.
        XCTAssertTrue(session.receive(type: .mouseMoved, event: event))
        XCTAssertEqual(received.count, 9)
        session.stop()
        session.stop()
        XCTAssertFalse(session.receive(type: .leftMouseDown, event: event))
        XCTAssertEqual(received.count, 9)
    }

    func testDisabledTapStopsAndReportsFailureOnlyOnce() throws {
        for reason in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
            var failures = 0
            let session = CaptureInputSession(onEvent: { _, _ in XCTFail("Disabled tap delivered input") },
                                              onFailure: { failures += 1 })
            let event = try XCTUnwrap(CGEvent(source: nil))
            XCTAssertFalse(session.receive(type: reason, event: event))
            XCTAssertTrue(session.isStopped)
            XCTAssertFalse(session.receive(type: reason, event: event))
            XCTAssertEqual(failures, 1)
        }
    }
}
