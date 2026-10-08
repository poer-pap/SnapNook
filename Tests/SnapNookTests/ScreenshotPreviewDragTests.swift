import AppKit
import XCTest
@testable import SnapNook

@MainActor
final class ScreenshotPreviewDragTests: XCTestCase {
    func testSuccessfulDropReportsAcceptedForCopyAndOtherOperations() {
        for operation: NSDragOperation in [.copy, .generic, .link, .move] {
            let view = makeView()
            let session = NSDraggingSession()
            var results: [Bool] = []
            view.onDragEnded = { results.append($0) }
            view.draggingSession(session, willBeginAt: .zero)
            view.draggingSession(session, endedAt: .zero, operation: operation)
            XCTAssertEqual(results, [true], "Accepted drop operation: \(operation.rawValue)")
            // Duplicate completion must not remove another preview or release the source twice.
            view.draggingSession(session, endedAt: .zero, operation: operation)
            XCTAssertEqual(results, [true])
        }
    }

    func testCancelledOrRejectedDropReportsNotAccepted() {
        let view = makeView()
        let session = NSDraggingSession()
        var results: [Bool] = []
        view.onDragEnded = { results.append($0) }
        view.draggingSession(session, willBeginAt: .zero)
        view.draggingSession(session, endedAt: .zero, operation: [])
        XCTAssertEqual(results, [false])
    }

    func testSourceStillOnlyOffersCopy() {
        let view = makeView()
        let session = NSDraggingSession()
        XCTAssertEqual(view.draggingSession(session, sourceOperationMaskFor: .outsideApplication), .copy)
    }

    private func makeView() -> ScreenshotPreviewView {
        ScreenshotPreviewView(item: ScreenshotPreviewItem(
            image: NSImage(size: NSSize(width: 10, height: 10)), pngData: Data(),
            createdAt: Date(), captureRect: nil, screenFrame: .zero
        ))
    }
}
