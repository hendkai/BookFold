//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import BookFold

/// The guard that keeps degenerate model output away from the user's pages.
final class DewarpGridPlausibilityTests: XCTestCase {
    func testIdentityIsPlausible() {
        XCTAssertTrue(DewarpGrid.identity(rows: 45, cols: 31).isPlausible)
    }

    /// Regression: on the iOS Simulator Core ML with `.all` returned this
    /// grid, which collapsed every page onto its centre pixel.
    func testAllZeroGridIsRejected() {
        let zeros = [Float](repeating: 0, count: 45 * 31)
        XCTAssertFalse(DewarpGrid(rows: 45, cols: 31, sourceX: zeros, sourceY: zeros).isPlausible)
    }

    func testRealisticCurlIsPlausible() {
        let id = DewarpGrid.identity(rows: 45, cols: 31)
        // Vertical bulge of up to 3 % of the page, strongest mid-page.
        let ys = zip(id.sourceX, id.sourceY).map { x, y in y + 0.06 * (1 - x * x) }
        XCTAssertTrue(DewarpGrid(rows: 45, cols: 31, sourceX: id.sourceX, sourceY: ys).isPlausible)
    }

    func testNonFiniteGridIsRejected() {
        let id = DewarpGrid.identity(rows: 5, cols: 4)
        var xs = id.sourceX
        xs[3] = .nan
        XCTAssertFalse(DewarpGrid(rows: 5, cols: 4, sourceX: xs, sourceY: id.sourceY).isPlausible)
    }

    func testMirroredGridIsRejected() {
        let id = DewarpGrid.identity(rows: 45, cols: 31)
        let xs = id.sourceX.map { -$0 }
        XCTAssertFalse(DewarpGrid(rows: 45, cols: 31, sourceX: xs, sourceY: id.sourceY).isPlausible)
    }

    func testCollapsedSpanIsRejected() {
        let id = DewarpGrid.identity(rows: 45, cols: 31)
        let xs = id.sourceX.map { $0 * 0.3 }
        XCTAssertFalse(DewarpGrid(rows: 45, cols: 31, sourceX: xs, sourceY: id.sourceY).isPlausible)
    }
}
