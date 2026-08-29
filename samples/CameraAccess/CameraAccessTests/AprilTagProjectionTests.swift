@testable import CameraAccess
import XCTest

final class AprilTagProjectionTests: XCTestCase {
  func testProjectsCornersThroughAspectFillCrop() throws {
    let observation = try XCTUnwrap(
      AprilTagObservation(
        id: 0,
        imageSize: CGSize(width: 400, height: 200),
        corners: [
          CGPoint(x: 150, y: 150),
          CGPoint(x: 250, y: 150),
          CGPoint(x: 250, y: 50),
          CGPoint(x: 150, y: 50),
        ]
      )
    )

    let transform = try XCTUnwrap(observation.projected(in: CGSize(width: 200, height: 200)))

    XCTAssertEqual(transform.center.x, 100, accuracy: 0.001)
    XCTAssertEqual(transform.center.y, 100, accuracy: 0.001)
    XCTAssertEqual(transform.markerSize, 100, accuracy: 0.001)
    XCTAssertEqual(transform.rotation, 0, accuracy: 0.001)
  }

  func testDerivesRotationFromOrientedCorners() throws {
    let observation = try XCTUnwrap(
      AprilTagObservation(
        id: 1,
        imageSize: CGSize(width: 200, height: 200),
        corners: [
          CGPoint(x: 50, y: 50),
          CGPoint(x: 50, y: 150),
          CGPoint(x: 150, y: 150),
          CGPoint(x: 150, y: 50),
        ]
      )
    )

    let transform = try XCTUnwrap(observation.projected(in: CGSize(width: 200, height: 200)))

    XCTAssertEqual(transform.rotation, .pi / 2, accuracy: 0.001)
  }

  func testDerivesPerspectiveFromOpposingEdgeLengths() throws {
    let observation = try XCTUnwrap(
      AprilTagObservation(
        id: 2,
        imageSize: CGSize(width: 200, height: 200),
        corners: [
          CGPoint(x: 40, y: 160),
          CGPoint(x: 160, y: 140),
          CGPoint(x: 160, y: 60),
          CGPoint(x: 40, y: 40),
        ]
      )
    )

    let transform = try XCTUnwrap(observation.projected(in: CGSize(width: 200, height: 200)))

    XCTAssertEqual(transform.rotation, 0, accuracy: 0.001)
    XCTAssertEqual(transform.pitch, 0, accuracy: 0.001)
    XCTAssertEqual(transform.yaw, 0.3, accuracy: 0.001)
  }
}