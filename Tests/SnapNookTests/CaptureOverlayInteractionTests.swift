import AppKit
import XCTest
@testable import SnapNook

@MainActor
final class CaptureOverlayInteractionTests: XCTestCase {
    private func view(completion: @escaping (CaptureOverlayResult) -> Void) -> CaptureOverlayView {
        _ = NSApplication.shared
        let frame = CGRect(x: -400, y: 80, width: 320, height: 240)
        return CaptureOverlayView(screen: CaptureScreen(displayID: 1, screenFrame: frame,
                                                       captureFrame: .zero, pixelWidth: 640, pixelHeight: 480),
                                  mode: .textOCR, completion: completion)
    }

    func testTapRoutedShiftAndSpaceProduceOneGlobalSelection() {
        var results: [CaptureOverlayResult] = []
        let view = view { results.append($0) }
        view.handle(type: .leftMouseDown, point: CGPoint(x: 20, y: 30))
        view.handle(type: .leftMouseDragged, point: CGPoint(x: 100, y: 90), shift: true)
        view.handle(type: .keyDown, point: .zero, keyCode: 49)
        view.handle(type: .leftMouseDragged, point: CGPoint(x: 110, y: 100), shift: true)
        view.handle(type: .leftMouseUp, point: CGPoint(x: 110, y: 100), shift: true)
        view.handle(type: .leftMouseUp, point: CGPoint(x: 110, y: 100))
        view.handle(type: .keyDown, point: .zero, keyCode: 53)
        XCTAssertEqual(results.count, 1)
        guard case .captured(let screen, let rect) = results.first else {
            return XCTFail("Expected selected screen metadata and rect")
        }
        XCTAssertEqual(rect, CGRect(x: -370, y: 120, width: 60, height: 60))
        XCTAssertEqual(screen.pixelRect(for: rect).size, CGSize(width: 120, height: 120))
    }

    func testEscapeAndSmallSelectionCancelWithoutOutput() {
        for escape in [true, false] {
            var results: [CaptureOverlayResult] = []
            let view = view { results.append($0) }
            view.handle(type: .leftMouseDown, point: CGPoint(x: 20, y: 30))
            if escape {
                view.handle(type: .keyDown, point: .zero, keyCode: 53)
            } else {
                view.handle(type: .leftMouseUp, point: CGPoint(x: 24, y: 34))
            }
            view.handle(type: .leftMouseUp, point: CGPoint(x: 150, y: 180))
            XCTAssertEqual(results.count, 1)
            guard case .cancelled = results.first else { return XCTFail("Expected cancellation") }
        }
    }
}
