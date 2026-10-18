//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import XCTest

@testable import BookFold

final class QuadTests: XCTestCase {
    // A perspective-distorted page quad (normalized, bottom-left origin).
    private let perspectiveQuad = Quad(
        topLeft: CGPoint(x: 0.18, y: 0.88),
        topRight: CGPoint(x: 0.86, y: 0.94),
        bottomRight: CGPoint(x: 0.92, y: 0.10),
        bottomLeft: CGPoint(x: 0.08, y: 0.06)
    )

    func testNormalizedCanonicalizesShuffledCorners() {
        // Every rotation of the corner list must reconstruct the same quad.
        let corners = perspectiveQuad.corners
        for shift in 0..<4 {
            let rotated = Array(corners[shift...] + corners[..<shift])
            let result = Quad.normalized(rotated)
            XCTAssertNotNil(result, "shift \(shift) failed")
            let expected = perspectiveQuad.corners
            let actual = result!.corners
            for i in 0..<4 {
                XCTAssertEqual(expected[i].x, actual[i].x, accuracy: 1e-9, "corner \(i)")
                XCTAssertEqual(expected[i].y, actual[i].y, accuracy: 1e-9, "corner \(i)")
            }
        }
    }

    func testNormalizedRejectsDegenerateInput() {
        let tl = CGPoint(x: 0.1, y: 0.9), tr = CGPoint(x: 0.9, y: 0.9)
        let br = CGPoint(x: 0.9, y: 0.1), bl = CGPoint(x: 0.1, y: 0.1)
        XCTAssertNil(Quad.normalized([tl, tr, br])) // 3 points
        XCTAssertNil(Quad.normalized([tl, tr, br, bl].map { CGPoint(x: $0.x, y: 0.5) })) // collinear
        // Concave (dart): mid-point pulled inside.
        let dart = [tl, CGPoint(x: 0.5, y: 0.5), tr, br]
        XCTAssertNil(Quad.normalized(dart + []))
        // All corners collapsed near centroid.
        XCTAssertNil(Quad.normalized([tl, tr, br, bl].map { CGPoint(x: $0.x * 0.01, y: $0.y * 0.01) }))
    }

    func testGeometryProperties() {
        let unit = Quad(
            topLeft: CGPoint(x: 0, y: 1),
            topRight: CGPoint(x: 1, y: 1),
            bottomRight: CGPoint(x: 1, y: 0),
            bottomLeft: CGPoint(x: 0, y: 0)
        )
        XCTAssertEqual(unit.area, 1.0, accuracy: 1e-9)
        XCTAssertEqual(unit.edgeAspect, 1.0, accuracy: 1e-9)
        XCTAssertEqual(unit.center.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(unit.center.y, 0.5, accuracy: 1e-9)

        let wide = Quad(
            topLeft: CGPoint(x: 0, y: 1),
            topRight: CGPoint(x: 2, y: 1),
            bottomRight: CGPoint(x: 2, y: 0),
            bottomLeft: CGPoint(x: 0, y: 0)
        )
        XCTAssertEqual(wide.edgeAspect, 2.0, accuracy: 1e-9)
    }

    func testSplitAtMidline() {
        let unit = Quad(
            topLeft: CGPoint(x: 0, y: 1),
            topRight: CGPoint(x: 1, y: 1),
            bottomRight: CGPoint(x: 1, y: 0),
            bottomLeft: CGPoint(x: 0, y: 0)
        )
        let halves = unit.split()
        XCTAssertEqual(halves.left.topRight, CGPoint(x: 0.5, y: 1))
        XCTAssertEqual(halves.left.bottomRight, CGPoint(x: 0.5, y: 0))
        XCTAssertEqual(halves.right.topLeft, CGPoint(x: 0.5, y: 1))
        XCTAssertEqual(halves.right.bottomLeft, CGPoint(x: 0.5, y: 0))
        XCTAssertEqual(halves.left.area, 0.5, accuracy: 1e-9)
        XCTAssertEqual(halves.right.area, 0.5, accuracy: 1e-9)
    }

    func testSplitAsymmetricRatioOnPerspectiveQuad() {
        // A trapezoid where the top edge is shorter: the split line must
        // interpolate *along the edges*, not in bounding-box space.
        let trapezoid = Quad(
            topLeft: CGPoint(x: 0.2, y: 0.9),
            topRight: CGPoint(x: 0.8, y: 0.9),
            bottomRight: CGPoint(x: 1.0, y: 0.1),
            bottomLeft: CGPoint(x: 0.0, y: 0.1)
        )
        let halves = trapezoid.split(at: 0.5)
        XCTAssertEqual(halves.left.topRight.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(halves.left.topRight.y, 0.9, accuracy: 1e-9)
        XCTAssertEqual(halves.left.bottomRight.x, 0.5, accuracy: 1e-9)
        // Left/right width ratio is equal by construction.
        XCTAssertEqual(halves.left.area, halves.right.area, accuracy: 1e-9)
    }

    func testPixelPointsMapToCoreImageSpace() {
        let quad = Quad(
            topLeft: CGPoint(x: 0.5, y: 1),
            topRight: CGPoint(x: 1, y: 1),
            bottomRight: CGPoint(x: 1, y: 0),
            bottomLeft: CGPoint(x: 0.5, y: 0)
        )
        let pts = quad.pixelPoints(in: CGSize(width: 4000, height: 3000))
        XCTAssertEqual(pts[0], CGPoint(x: 2000, y: 3000)) // TL
        XCTAssertEqual(pts[1], CGPoint(x: 4000, y: 3000)) // TR
        XCTAssertEqual(pts[2], CGPoint(x: 4000, y: 0)) // BR
        XCTAssertEqual(pts[3], CGPoint(x: 2000, y: 0)) // BL
    }

    func testLayerPointsFlipYAxis() {
        let quad = Quad(
            topLeft: CGPoint(x: 0, y: 1),
            topRight: CGPoint(x: 1, y: 1),
            bottomRight: CGPoint(x: 1, y: 0),
            bottomLeft: CGPoint(x: 0, y: 0)
        )
        let size = CGSize(width: 390, height: 844)
        let pts = quad.layerPoints(in: size)
        XCTAssertEqual(pts[0], CGPoint(x: 0, y: 0)) // vision-TL → layer top-left
        XCTAssertEqual(pts[1], CGPoint(x: 390, y: 0))
        XCTAssertEqual(pts[2], CGPoint(x: 390, y: 844))
        XCTAssertEqual(pts[3], CGPoint(x: 0, y: 844))
    }

    func testSimilarityAndIoU() {
        let q = Quad(
            topLeft: CGPoint(x: 0.1, y: 0.9),
            topRight: CGPoint(x: 0.9, y: 0.9),
            bottomRight: CGPoint(x: 0.9, y: 0.1),
            bottomLeft: CGPoint(x: 0.1, y: 0.1)
        )
        let jittered = Quad(
            topLeft: CGPoint(x: 0.11, y: 0.92),
            topRight: CGPoint(x: 0.91, y: 0.9),
            bottomRight: CGPoint(x: 0.9, y: 0.12),
            bottomLeft: CGPoint(x: 0.1, y: 0.1)
        )
        XCTAssertTrue(q.isSimilar(to: jittered, tolerance: 0.03))
        XCTAssertFalse(q.isSimilar(to: jittered, tolerance: 0.01))

        let shifted = Quad(
            topLeft: CGPoint(x: 0.4, y: 0.6),
            topRight: CGPoint(x: 0.8, y: 0.6),
            bottomRight: CGPoint(x: 0.8, y: 0.3),
            bottomLeft: CGPoint(x: 0.4, y: 0.3)
        )
        XCTAssertEqual(q.boundingBoxIoU(with: q), 1.0, accuracy: 1e-9)
        XCTAssertLessThan(q.boundingBoxIoU(with: shifted), 0.3)
        let disjoint = Quad(
            topLeft: CGPoint(x: 0, y: 0.2),
            topRight: CGPoint(x: 0.05, y: 0.2),
            bottomRight: CGPoint(x: 0.05, y: 0),
            bottomLeft: CGPoint(x: 0, y: 0)
        )
        XCTAssertEqual(q.boundingBoxIoU(with: disjoint), 0, accuracy: 1e-9)
    }

    func testFullFrameConstantIsCanonical() {
        XCTAssertEqual(Quad.fullFrame.corners[0], CGPoint(x: 0, y: 1))
        XCTAssertEqual(Quad.fullFrame.corners[2], CGPoint(x: 1, y: 0))
        XCTAssertEqual(Quad.fullFrame.area, 1.0, accuracy: 1e-9)
    }
}
