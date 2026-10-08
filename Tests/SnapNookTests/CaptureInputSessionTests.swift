import AppKit
import XCTest
@testable import SnapNook

final class CaptureInputSessionTests: XCTestCase {
    func testSelectionInputIsConsumedUntilCaptureCleanup() throws {
        var received: [CGEventType] = []
        let session = CaptureInputSession(initiallyPressedKeys: [], onEvent: { type, _ in received.append(type) }, onFailure: {
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

    func testStartingShortcutReleasesPassThroughAcrossRepeatedSelections() throws {
        for _ in 0..<5 {
            var received: [CGEventType] = []
            let session = CaptureInputSession(initiallyPressedKeys: [0, 58, 59], onEvent: {
                type, _ in received.append(type)
            }, onFailure: { XCTFail("Unexpected input failure") })
            let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false))
            // The hotkey down reached the system before selection started.
            for (type, key) in [(CGEventType.flagsChanged, 58), (.keyUp, 0), (.flagsChanged, 59)] {
                event.setIntegerValueField(.keyboardEventKeycode, value: Int64(key))
                XCTAssertFalse(session.receive(type: type, event: event), "Starting key release must reach the system")
            }
            // Later presses and releases of the same keys belong to selection.
            event.setIntegerValueField(.keyboardEventKeycode, value: 0)
            XCTAssertTrue(session.receive(type: .keyDown, event: event))
            XCTAssertTrue(session.receive(type: .keyUp, event: event))
            event.setIntegerValueField(.keyboardEventKeycode, value: 58)
            XCTAssertTrue(session.receive(type: .flagsChanged, event: event))
            XCTAssertTrue(session.receive(type: .flagsChanged, event: event))
            XCTAssertEqual(received.count, 7)
            session.stop()
            XCTAssertFalse(session.receive(type: .keyDown, event: event))
        }
    }

    func testStartingKeyRepeatIsConsumedBeforeItsReleasePassesThrough() throws {
        let session = CaptureInputSession(initiallyPressedKeys: [0], onEvent: { _, _ in },
                                          onFailure: { XCTFail("Unexpected input failure") })
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        XCTAssertTrue(session.receive(type: .keyDown, event: event))
        XCTAssertFalse(session.receive(type: .keyUp, event: event))
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        XCTAssertTrue(session.receive(type: .keyDown, event: event))
        XCTAssertTrue(session.receive(type: .keyUp, event: event))
    }

    func testStartingShortcutReleasePassesWhenHotkeyIsAbsentFromSystemKeyState() throws {
        // Carbon has consumed A-down; both system state tables only report the modifiers.
        let session = CaptureInputSession(initiallyPressedKeys: [58, 59], onEvent: { _, _ in },
                                          onFailure: { XCTFail("Unexpected input failure") })
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false))
        XCTAssertFalse(session.receive(type: .keyUp, event: event))
        XCTAssertTrue(session.receive(type: .keyDown, event: event))
        XCTAssertTrue(session.receive(type: .keyUp, event: event))
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
