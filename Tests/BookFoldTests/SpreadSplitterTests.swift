//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import XCTest

@testable import BookFold

final class SpreadSplitterTests: XCTestCase {
    func testHalvesOfUprightSpread() {
        let spread = Quad(
            topLeft: CGPoint(x: 0.1, y: 0.9),
            topRight: CGPoint(x: 0.9, y: 0.9),
            bottomRight: CGPoint(x: 0.9, y: 0.1),
            bottomLeft: CGPoint(x: 0.1, y: 0.1)
        )
        let halves = SpreadSplitter.orderedHalves(of: spread)
        XCTAssertEqual(halves.count, 2)
        XCTAssertEqual(halves[0].side, .left)
        XCTAssertEqual(halves[1].side, .right)
        XCTAssertLessThan(halves[0].quad.center.x, halves[1].quad.center.x)

        // Left half covers the left part of the spread.
        XCTAssertEqual(halves[0].quad.topLeft, spread.topLeft)
        XCTAssertEqual(halves[0].quad.bottomLeft, spread.bottomLeft)
        XCTAssertEqual(halves[1].quad.topRight, spread.topRight)
        XCTAssertEqual(halves[1].quad.bottomRight, spread.bottomRight)

        // The split edges coincide.
        XCTAssertEqual(halves[0].quad.topRight, halves[1].quad.topLeft)
        XCTAssertEqual(halves[0].quad.bottomRight, halves[1].quad.bottomLeft)
    }

    func testMirroredSpreadStillOrdersImageLeftFirst() {
        // A scene mirrored horizontally: the quad's "left" corners sit at
        // larger x. Reading order is defined by *image* position, so the
        // half with the smaller centroid must come first regardless.
        let mirrored = Quad(
            topLeft: CGPoint(x: 0.9, y: 0.9),
            topRight: CGPoint(x: 0.1, y: 0.9),
            bottomRight: CGPoint(x: 0.1, y: 0.1),
            bottomLeft: CGPoint(x: 0.9, y: 0.1)
        )
        let halves = SpreadSplitter.orderedHalves(of: mirrored)
        XCTAssertLessThanOrEqual(halves[0].quad.center.x, halves[1].quad.center.x)
        // The first half is the one constructed from the *right* corners.
        XCTAssertEqual(halves[0].side, .right)
    }

    func testAsymmetricRatioKeepsBothHalvesValid() {
        let spread = Quad(
            topLeft: CGPoint(x: 0.2, y: 0.9),
            topRight: CGPoint(x: 0.8, y: 0.9),
            bottomRight: CGPoint(x: 1.0, y: 0.1),
            bottomLeft: CGPoint(x: 0.0, y: 0.1)
        )
        for ratio: CGFloat in [0.3, 0.5, 0.7] {
            let halves = SpreadSplitter.orderedHalves(of: spread, ratio: ratio)
            XCTAssertEqual(halves[0].quad.area + halves[1].quad.area, spread.area, accuracy: 1e-9,
                           "split at \(ratio) must conserve area")
        }
    }

    func testOrderedPixelQuadsMatchPixelMapping() {
        let spread = Quad(
            topLeft: CGPoint(x: 0.1, y: 0.9),
            topRight: CGPoint(x: 0.9, y: 0.9),
            bottomRight: CGPoint(x: 0.9, y: 0.1),
            bottomLeft: CGPoint(x: 0.1, y: 0.1)
        )
        let size = CGSize(width: 4032, height: 3024)
        let expected = SpreadSplitter.orderedHalves(of: spread).map(\.quad).map { $0.pixelPoints(in: size) }
        let actual = SpreadSplitter.orderedPixelQuads(of: spread, sourceSize: size).map(\.corners)
        for (e, a) in zip(expected, actual) {
            for i in 0..<4 {
                XCTAssertEqual(e[i].x, a[i].x, accuracy: 1e-6)
                XCTAssertEqual(e[i].y, a[i].y, accuracy: 1e-6)
            }
        }
    }
}
