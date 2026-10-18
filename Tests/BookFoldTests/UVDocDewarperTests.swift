//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import Foundation
import XCTest

@testable import BookFold

/// The bundled UVDoc Core ML model: loads, predicts a grid, flattens curl.
/// Synthetic fixtures only — real book photos are verified on device.
final class UVDocDewarperTests: XCTestCase {
    private let dewarper = UVDocDewarper()

    func testBundledModelPredictsExpectedGrid() throws {
        let page = TestImageFactory.pageContent(width: 600, height: 800)
        let grid = try XCTUnwrap(dewarper.predictGrid(for: page), "bundled UVDoc model must load")
        XCTAssertEqual(grid.rows, 45)
        XCTAssertEqual(grid.cols, 31)
        XCTAssertTrue(grid.sourceX.allSatisfy { $0.isFinite && abs($0) < 3 })
        XCTAssertTrue(grid.sourceY.allSatisfy { $0.isFinite && abs($0) < 3 })
    }

    func testMissingModelFallsBackToNil() {
        let page = TestImageFactory.pageContent(width: 600, height: 800)
        XCTAssertNil(UVDocDewarper(modelURL: nil).dewarp(page))
    }

    func testFlatPageStaysFlat() throws {
        let flat = TestImageFactory.pageContent(width: 600, height: 800)
        let out = try XCTUnwrap(dewarper.dewarp(flat))
        XCTAssertEqual(out.width, 600)
        XCTAssertEqual(out.height, 800)
        let bow = lineBow(out)
        print("dewarp flat bow=\(bow)")
        XCTAssertLessThan(bow, 0.01, "dewarp must not bend a flat page (bow \(bow))")
    }

    func testCurvedPageIsMeasurablyFlattened() throws {
        let curved = TestImageFactory.pageContent(width: 600, height: 800, curvature: 28)
        let before = lineBow(curved)
        let out = try XCTUnwrap(dewarper.dewarp(curved))
        let after = lineBow(out)
        print("dewarp curved bow before=\(before) after=\(after)")
        XCTAssertGreaterThan(before, 0.02, "fixture must actually be curved")
        XCTAssertLessThan(after, before * 0.5, "dewarp must remove most of the curl (before \(before), after \(after))")
    }

    /// Page size of a typical iPhone capture after perspective correction.
    /// Timing is printed for the record; device numbers are what count.
    func testDewarpTimingAtPhoneScanSize() throws {
        let page = TestImageFactory.pageContent(width: 1700, height: 2400, curvature: 28)
        _ = dewarper.dewarp(page) // warm-up: model load + first prediction
        let start = Date()
        let out = try XCTUnwrap(dewarper.dewarp(page))
        let elapsed = Date().timeIntervalSince(start)
        print("dewarp 1700x2400 elapsed=\(elapsed)s (simulator/host, not device)")
        XCTAssertEqual(out.width, 1700)
        XCTAssertEqual(out.height, 2400)
    }

    // MARK: - Line bow (same tracking as the geometry tests)

    /// Max deviation (fraction of page height) of one text line from its chord.
    private func lineBow(_ image: CGImage) -> CGFloat {
        let (w, h, pixels) = TestImageFactory.rgba(image)
        let x0 = Int(0.10 * Double(w)), x1 = Int(0.90 * Double(w))
        let y0 = Int(0.30 * Double(h)), y1 = Int(0.60 * Double(h))

        var rows: [(x: Int, y: Int)] = []
        var trackY: Int? = nil
        for x in x0...x1 {
            let lo = trackY.map { max(0, $0 - 12) } ?? y0
            let hi = trackY.map { min(h, $0 + 13) } ?? y1
            var bestY = -1
            var bestV: UInt8 = 255
            for y in lo..<hi {
                let i = (y * w + x) * 4
                let v = min(pixels[i], min(pixels[i + 1], pixels[i + 2]))
                if v < bestV {
                    bestV = v
                    bestY = y
                }
            }
            if bestY >= 0, bestV < 120 {
                rows.append((x, bestY))
                trackY = bestY
            }
        }
        guard rows.count > 10 else { return 0 }

        let edgeCount = max(3, rows.count * 3 / 100)
        let left = rows.prefix(edgeCount), right = rows.suffix(edgeCount)
        let lx = left.map { Double($0.x) }.reduce(0, +) / Double(left.count)
        let ly = left.map { Double($0.y) }.reduce(0, +) / Double(left.count)
        let rx = right.map { Double($0.x) }.reduce(0, +) / Double(right.count)
        let ry = right.map { Double($0.y) }.reduce(0, +) / Double(right.count)
        let slope = (ry - ly) / (rx - lx)

        var maxDev: Double = 0
        for r in rows {
            let fitted = ly + slope * (Double(r.x) - lx)
            maxDev = max(maxDev, abs(Double(r.y) - fitted))
        }
        return CGFloat(maxDev / Double(h))
    }
}
