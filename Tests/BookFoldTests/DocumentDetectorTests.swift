//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import XCTest

@testable import BookFold

final class DocumentDetectorTests: XCTestCase {
    private let unit = Quad(
        topLeft: CGPoint(x: 0, y: 1),
        topRight: CGPoint(x: 1, y: 1),
        bottomRight: CGPoint(x: 1, y: 0),
        bottomLeft: CGPoint(x: 0, y: 0)
    )

    // MARK: - Pure selection logic

    func testSelectBestPrefersLargestValidCandidate() {
        let small = Quad(
            topLeft: CGPoint(x: 0.4, y: 0.6),
            topRight: CGPoint(x: 0.6, y: 0.6),
            bottomRight: CGPoint(x: 0.6, y: 0.4),
            bottomLeft: CGPoint(x: 0.4, y: 0.4)
        )
        let large = Quad(
            topLeft: CGPoint(x: 0.1, y: 0.9),
            topRight: CGPoint(x: 0.9, y: 0.9),
            bottomRight: CGPoint(x: 0.9, y: 0.1),
            bottomLeft: CGPoint(x: 0.1, y: 0.1)
        )
        let best = DocumentDetector.selectBest(
            candidates: [(small, 0.99), (large, 0.8)]
        )
        XCTAssertEqual(best, large)
    }

    func testSelectBestFiltersExtremeAspectAndLowConfidence() {
        // Extreme aspect (a strip) — rejected even with high confidence.
        let strip = Quad(
            topLeft: CGPoint(x: 0.1, y: 0.9),
            topRight: CGPoint(x: 0.95, y: 0.9),
            bottomRight: CGPoint(x: 0.95, y: 0.85),
            bottomLeft: CGPoint(x: 0.1, y: 0.85)
        )
        XCTAssertNil(DocumentDetector.selectBest(candidates: [(strip, 0.95)]))

        // Low confidence — rejected.
        XCTAssertNil(DocumentDetector.selectBest(candidates: [(unit, 0.3)]))
    }

    // MARK: - Vision integration (synthetic photo, on-device)

    func testDetectsPageInSyntheticPhoto() throws {
        let page = TestImageFactory.pageContent(width: 500, height: 700)
        let canvasSize = CGSize(width: 800, height: 1000)
        let trueQuad = Quad(
            topLeft: CGPoint(x: 0.15, y: 0.9),
            topRight: CGPoint(x: 0.85, y: 0.87),
            bottomRight: CGPoint(x: 0.88, y: 0.12),
            bottomLeft: CGPoint(x: 0.12, y: 0.1)
        )
        let photo = TestImageFactory.photographed(page: page, canvasSize: canvasSize, quad: trueQuad)

        let detector = DocumentDetector(minimumConfidence: 0.4)
        let detected = try XCTUnwrap(detector.bestQuad(in: photo), "Vision should find the white page on dark background")

        // Rough agreement with ground truth.
        XCTAssertGreaterThan(detected.boundingBoxIoU(with: trueQuad), 0.55)
        XCTAssertEqual(detected.center.x, trueQuad.center.x, accuracy: 0.08)
        XCTAssertEqual(detected.center.y, trueQuad.center.y, accuracy: 0.08)
    }
}
