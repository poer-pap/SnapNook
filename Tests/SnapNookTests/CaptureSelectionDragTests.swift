import XCTest
@testable import SnapNook

final class CaptureSelectionDragTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 100, height: 80)

    func testFourDirectionsAndSingleScreenClamping() {
        for point in [CGPoint(x: -20, y: -20), CGPoint(x: 120, y: -20),
                      CGPoint(x: -20, y: 100), CGPoint(x: 120, y: 100)] {
            var drag = CaptureSelectionDrag(start: CGPoint(x: 50, y: 40))
            drag.update(to: point, bounds: bounds, square: false, moving: false)
            XCTAssertEqual(drag.rect.width, 50)
            XCTAssertEqual(drag.rect.height, 40)
            XCTAssertTrue(bounds.contains(drag.rect))
        }
    }

    func testShiftKeepsSquareInsideScreen() {
        var drag = CaptureSelectionDrag(start: CGPoint(x: 50, y: 40))
        drag.update(to: CGPoint(x: 120, y: 70), bounds: bounds, square: true, moving: false)
        XCTAssertEqual(drag.rect, CGRect(x: 50, y: 40, width: 30, height: 30))
    }

    func testSpaceMovesWithoutResizingAndClampsAtEdge() {
        var drag = CaptureSelectionDrag(start: CGPoint(x: 10, y: 10))
        drag.update(to: CGPoint(x: 40, y: 30), bounds: bounds, square: false, moving: false)
        drag.update(to: CGPoint(x: 140, y: 130), bounds: bounds, square: false, moving: true)
        XCTAssertEqual(drag.rect, CGRect(x: 70, y: 60, width: 30, height: 20))
        drag.update(to: CGPoint(x: 100, y: 80), bounds: bounds, square: false, moving: false)
        XCTAssertEqual(drag.rect, CGRect(x: 70, y: 60, width: 30, height: 20))
    }
}
