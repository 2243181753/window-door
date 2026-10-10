import AppKit
import ScreenCaptureKit

func XCTAssertTrue(_ value: Bool) { precondition(value) }
func XCTAssertFalse(_ value: Bool) { precondition(!value) }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
func XCTAssertEqual<T: Equatable>(_ left: T, _ right: T) { precondition(left == right, "\(left) != \(right)") }
func XCTAssertEqual(_ left: CGFloat, _ right: CGFloat, accuracy: CGFloat) { precondition(abs(left - right) <= accuracy) }

@main
struct GeometryTests {
    static func main() {
        let tests = GeometryTests()
        tests.testPrimaryCoordinateConversion()
        tests.testSecondaryDisplayNegativeCoordinates()
        tests.testPositionFollowing()
        tests.testFollowToggleWithoutJump()
        tests.testFollowDuringManualEditing()
        tests.testSelectionSizingOnce()
        tests.testMouseInterception()
        tests.testOpacityBounds()
        tests.testDefaultSize()
        tests.testCornerHitTargets()
        tests.testAllFourCornerResizes()
        tests.testResizeMinimumAndMove()
        tests.testCropPreservesScreenPosition()
        tests.testPartialOverlapAndOutside()
        tests.testHoverLeaveDragStopAndMissingFrame()
        tests.testFailureClassification()
        print("PASS: 16 test groups; default size, four corners, anchored resize, minimum size, movement, crop, hover and errors")
    }
    func testFailureClassification() {
        let denied = CaptureFailure.describe(NSError(domain: SCStreamErrorDomain, code: -3801), operation: "测试")
        // Use the SDK constant: an arbitrary other domain with the same code must not be treated as permission denial.
        let other = CaptureFailure.describe(NSError(domain: "network.test", code: -3801), operation: "测试")
        XCTAssertFalse(other.contains("未获准"))
        XCTAssertTrue(other.contains("network.test / -3801"))
        let connection = CaptureFailure.describe(NSError(domain: SCStreamErrorDomain, code: -3804), operation: "测试")
        XCTAssertFalse(connection.contains("请授权"))
        XCTAssertTrue(denied.contains("未获准"))
    }
    func testPrimaryCoordinateConversion() {
        XCTAssertEqual(PortalGeometry.quartzRect(CGRect(x: 100, y: 200, width: 60, height: 30), primaryHeight: 900), CGRect(x: 100, y: 670, width: 60, height: 30))
    }
    func testSecondaryDisplayNegativeCoordinates() {
        XCTAssertEqual(PortalGeometry.quartzRect(CGRect(x: -500, y: 950, width: 60, height: 30), primaryHeight: 900), CGRect(x: -500, y: -80, width: 60, height: 30))
    }
    func testPositionFollowing() {
        var follower = SourcePositionFollower()
        XCTAssertNil(follower.translation(to: CGPoint(x: 100, y: 200), enabled: true, manipulating: false))
        XCTAssertEqual(follower.translation(to: CGPoint(x: 140, y: 230), enabled: true, manipulating: false), CGPoint(x: 40, y: -30))
        XCTAssertEqual(follower.translation(to: CGPoint(x: -100, y: -200), enabled: true, manipulating: false), CGPoint(x: -240, y: 430))
        // Position alone determines translation; a resize with the same top-left causes no movement.
        XCTAssertEqual(follower.translation(to: CGPoint(x: -100, y: -200), enabled: true, manipulating: false), .zero)
    }
    func testFollowToggleWithoutJump() {
        var follower = SourcePositionFollower()
        follower.reset(to: CGPoint(x: 100, y: 200))
        XCTAssertNil(follower.translation(to: CGPoint(x: 400, y: 500), enabled: false, manipulating: false))
        XCTAssertEqual(follower.translation(to: CGPoint(x: 410, y: 510), enabled: true, manipulating: false), CGPoint(x: 10, y: -10))
        follower.reset(to: CGPoint(x: 800, y: 900))
        XCTAssertEqual(follower.translation(to: CGPoint(x: 805, y: 903), enabled: true, manipulating: false), CGPoint(x: 5, y: -3))
    }
    func testFollowDuringManualEditing() {
        var follower = SourcePositionFollower()
        follower.reset(to: CGPoint(x: 100, y: 200))
        XCTAssertNil(follower.translation(to: CGPoint(x: 120, y: 230), enabled: true, manipulating: true))
        XCTAssertNil(follower.translation(to: CGPoint(x: 150, y: 260), enabled: true, manipulating: true))
        XCTAssertEqual(follower.translation(to: CGPoint(x: 160, y: 270), enabled: true, manipulating: false), CGPoint(x: 60, y: -70))
        XCTAssertNil(follower.translation(to: CGPoint(x: CGFloat.nan, y: 270), enabled: true, manipulating: false))
        XCTAssertEqual(follower.translation(to: CGPoint(x: 161, y: 271), enabled: true, manipulating: false), CGPoint(x: 1, y: -1))
    }
    func testSelectionSizingOnce() {
        var sizing = SelectionSizing()
        XCTAssertNil(sizing.takeSize(CGSize(width: 800, height: 600)))
        sizing.beginSelection()
        XCTAssertNil(sizing.takeSize(.zero))
        XCTAssertNil(sizing.takeSize(CGSize(width: CGFloat.infinity, height: 600)))
        XCTAssertEqual(sizing.takeSize(CGSize(width: 800, height: 600)), CGSize(width: 800, height: 600))
        // Subsequent frames, source-window resizes and manual portal changes do not consume another size.
        XCTAssertNil(sizing.takeSize(CGSize(width: 1000, height: 700)))
        sizing.beginSelection()
        XCTAssertEqual(sizing.takeSize(CGSize(width: 420, height: 320)), CGSize(width: 420, height: 320))
        sizing.beginSelection(); sizing.cancel()
        XCTAssertNil(sizing.takeSize(CGSize(width: 900, height: 700)))
    }
    func testMouseInterception() {
        XCTAssertTrue(PortalGeometry.shortcutScope(enabled: true, hovering: true, hasFrame: true, settingsShown: false))
        XCTAssertFalse(PortalGeometry.shortcutScope(enabled: false, hovering: true, hasFrame: true, settingsShown: false))
        XCTAssertFalse(PortalGeometry.shortcutScope(enabled: true, hovering: false, hasFrame: true, settingsShown: false))
        XCTAssertFalse(PortalGeometry.shortcutScope(enabled: true, hovering: true, hasFrame: false, settingsShown: false))
        XCTAssertFalse(PortalGeometry.shortcutScope(enabled: true, hovering: true, hasFrame: true, settingsShown: true))
        XCTAssertFalse(PortalGeometry.interceptsMouse(option: false, manipulating: false))
        XCTAssertTrue(PortalGeometry.interceptsMouse(option: true, manipulating: false))
        XCTAssertTrue(PortalGeometry.interceptsMouse(option: false, manipulating: true))
    }
    func testOpacityBounds() {
        XCTAssertEqual(PortalGeometry.opacity(0), 0)
        XCTAssertEqual(PortalGeometry.opacity(0.35), 0.35, accuracy: 0.00001)
        XCTAssertEqual(PortalGeometry.opacity(1), 1)
        XCTAssertEqual(PortalGeometry.opacity(-1), 0)
        XCTAssertEqual(PortalGeometry.opacity(2), 1)
        XCTAssertEqual(PortalGeometry.opacity(.nan), 1)
    }
    func testDefaultSize() {
        XCTAssertEqual(PortalGeometry.defaultSize, CGSize(width: 180, height: 90))
    }
    func testCornerHitTargets() {
        let frame = CGRect(x: 100, y: 200, width: 180, height: 90)
        XCTAssertEqual(PortalGeometry.corner(at: CGPoint(x: 101, y: 289), in: frame), .topLeft)
        XCTAssertEqual(PortalGeometry.corner(at: CGPoint(x: 279, y: 289), in: frame), .topRight)
        XCTAssertEqual(PortalGeometry.corner(at: CGPoint(x: 101, y: 201), in: frame), .bottomLeft)
        XCTAssertEqual(PortalGeometry.corner(at: CGPoint(x: 279, y: 201), in: frame), .bottomRight)
        XCTAssertNil(PortalGeometry.corner(at: CGPoint(x: 190, y: 245), in: frame))
        XCTAssertNil(PortalGeometry.corner(at: CGPoint(x: 190, y: 201), in: frame))
        XCTAssertNil(PortalGeometry.corner(at: CGPoint(x: 99, y: 201), in: frame))
    }
    func testAllFourCornerResizes() {
        let frame = CGRect(x: 100, y: 200, width: 180, height: 90)
        let cases: [(PortalCorner, CGPoint, CGRect)] = [
            (.topLeft, CGPoint(x: -20, y: 10), CGRect(x: 80, y: 200, width: 200, height: 100)),
            (.topRight, CGPoint(x: 20, y: 10), CGRect(x: 100, y: 200, width: 200, height: 100)),
            (.bottomLeft, CGPoint(x: -20, y: -10), CGRect(x: 80, y: 190, width: 200, height: 100)),
            (.bottomRight, CGPoint(x: 20, y: -10), CGRect(x: 100, y: 190, width: 200, height: 100))
        ]
        for (corner, delta, expected) in cases {
            XCTAssertEqual(PortalGeometry.manipulatedFrame(start: frame, delta: delta, corner: corner), expected)
            XCTAssertEqual(PortalGeometry.manipulatedFrame(start: expected, delta: CGPoint(x: -delta.x, y: -delta.y), corner: corner), frame)
        }
    }
    func testResizeMinimumAndMove() {
        let frame = CGRect(x: 100, y: 200, width: 180, height: 90)
        for corner in PortalCorner.allCases {
            let left = corner == .topLeft || corner == .bottomLeft
            let bottom = corner == .bottomLeft || corner == .bottomRight
            let result = PortalGeometry.manipulatedFrame(start: frame, delta: CGPoint(x: left ? 1000 : -1000, y: bottom ? 1000 : -1000), corner: corner)
            XCTAssertEqual(result.size, PortalGeometry.minimumSize)
            XCTAssertEqual(left ? result.maxX : result.minX, left ? frame.maxX : frame.minX)
            XCTAssertEqual(bottom ? result.maxY : result.minY, bottom ? frame.maxY : frame.minY)
        }
        XCTAssertEqual(PortalGeometry.manipulatedFrame(start: frame, delta: CGPoint(x: -400, y: 50), corner: nil), CGRect(x: -300, y: 250, width: 180, height: 90))
    }
    func testCropPreservesScreenPosition() {
        let source = CGRect(x: 100, y: 100, width: 500, height: 300)
        let crop = PortalGeometry.crop(portal: CGRect(x: 150, y: 160, width: 60, height: 30), source: source)!
        XCTAssertEqual(crop.minX, 0.1, accuracy: 0.00001)
        XCTAssertEqual(crop.minY, 0.2, accuracy: 0.00001)
        XCTAssertEqual(crop.width, 0.12, accuracy: 0.00001)
        XCTAssertEqual(crop.height, 0.1, accuracy: 0.00001)
    }
    func testPartialOverlapAndOutside() {
        let source = CGRect(x: 100, y: 100, width: 500, height: 300)
        XCTAssertEqual(PortalGeometry.crop(portal: CGRect(x: 90, y: 90, width: 60, height: 30), source: source), CGRect(x: 0, y: 0, width: 0.1, height: 20.0 / 300))
        XCTAssertNil(PortalGeometry.crop(portal: CGRect(x: -60, y: -30, width: 60, height: 30), source: source))
    }
    func testHoverLeaveDragStopAndMissingFrame() {
        XCTAssertTrue(PortalGeometry.reveals(enabled: true, hovering: true, dragging: false, hasFrame: true))
        XCTAssertFalse(PortalGeometry.reveals(enabled: true, hovering: false, dragging: false, hasFrame: true))
        XCTAssertTrue(PortalGeometry.reveals(enabled: true, hovering: true, dragging: true, hasFrame: true))
        XCTAssertTrue(PortalGeometry.reveals(enabled: true, hovering: false, dragging: true, hasFrame: true))
        XCTAssertFalse(PortalGeometry.reveals(enabled: false, hovering: true, dragging: false, hasFrame: true))
        XCTAssertFalse(PortalGeometry.reveals(enabled: true, hovering: true, dragging: false, hasFrame: false))
    }
}
