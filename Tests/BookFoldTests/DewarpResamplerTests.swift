//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import BookFold

/// Pure Float32 grid sampling — no model, no simulator-specific behaviour.
final class DewarpResamplerTests: XCTestCase {
    private func gradientPixels(width: Int, height: Int) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                px[i] = UInt8((x * 5) % 256)
                px[i + 1] = UInt8((y * 3) % 256)
                px[i + 2] = UInt8((x + y) % 256)
                px[i + 3] = 255
            }
        }
        return px
    }

    func testIdentityGridReproducesImage() {
        let w = 37, h = 53
        let px = gradientPixels(width: w, height: h)
        let out = DewarpResampler.resample(
            pixels: px, width: w, height: h,
            grid: .identity(rows: 6, cols: 5)
        )
        var maxDiff = 0
        for i in 0..<px.count where i % 4 != 3 {
            maxDiff = max(maxDiff, abs(Int(out[i]) - Int(px[i])))
        }
        XCTAssertLessThanOrEqual(maxDiff, 1, "identity grid must be a no-op")
        XCTAssertTrue((0..<(w * h)).allSatisfy { out[$0 * 4 + 3] == 255 })
    }

    /// Output x samples source x + 3 (align_corners mapping: 2 * 3 / (w - 1)
    /// in normalized units). Columns whose source falls off the image are paper.
    func testShiftedGridSamplesSourceOffset() {
        let w = 40, h = 30, shift = 3
        let px = gradientPixels(width: w, height: h)
        let base = DewarpGrid.identity(rows: 5, cols: 4)
        let shiftNorm = Float(2 * shift) / Float(w - 1)
        let grid = DewarpGrid(
            rows: base.rows,
            cols: base.cols,
            sourceX: base.sourceX.map { $0 + shiftNorm },
            sourceY: base.sourceY
        )
        let out = DewarpResampler.resample(pixels: px, width: w, height: h, grid: grid)

        for y in 0..<h {
            for x in 0..<(w - shift) {
                let o = (y * w + x) * 4
                let s = (y * w + x + shift) * 4
                XCTAssertLessThanOrEqual(abs(Int(out[o]) - Int(px[s])), 1, "x=\(x) y=\(y)")
            }
            for x in (w - shift)..<w {
                let o = (y * w + x) * 4
                XCTAssertEqual(out[o], 255, "source beyond the right edge must be paper, x=\(x)")
            }
        }
    }

    func testSourceOutsideImageIsPaperWhite() {
        let w = 16, h = 12
        let px = [UInt8](repeating: 0, count: w * h * 4) // solid black source
        let grid = DewarpGrid(
            rows: 3, cols: 3,
            sourceX: [Float](repeating: -2, count: 9),
            sourceY: [Float](repeating: 0, count: 9)
        )
        let out = DewarpResampler.resample(pixels: px, width: w, height: h, grid: grid)
        XCTAssertTrue(stride(from: 0, to: out.count, by: 4).allSatisfy {
            out[$0] == 255 && out[$0 + 1] == 255 && out[$0 + 2] == 255
        })
    }
}
