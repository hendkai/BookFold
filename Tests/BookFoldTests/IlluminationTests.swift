//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import CoreImage
import XCTest

@testable import BookFold

final class IlluminationTests: XCTestCase {
    private let context = Illumination.makeContext()

    func testNeutralSceneHasUnitGains() {
        let gains = Illumination.whiteBalanceGains(average: (0.8, 0.8, 0.8))
        XCTAssertEqual(gains.r, 1.0, accuracy: 1e-9)
        XCTAssertEqual(gains.g, 1.0, accuracy: 1e-9)
        XCTAssertEqual(gains.b, 1.0, accuracy: 1e-9)
    }

    func testWarmCastIsNeutralized() {
        // Warm incandescent light: red strongest, blue weak.
        let gains = Illumination.whiteBalanceGains(average: (0.8, 0.7, 0.55))
        XCTAssertEqual(gains.r, 1.0, accuracy: 1e-9)
        XCTAssertEqual(gains.g, 0.8 / 0.7, accuracy: 1e-9)
        XCTAssertEqual(gains.b, 0.8 / 0.55, accuracy: 1e-9)
    }

    func testGainsNeverDarkenAndAreClamped() {
        // Extreme cast would demand gain 3.2 → clamped to maxGain.
        let gains = Illumination.whiteBalanceGains(average: (0.8, 0.5, 0.25), maxGain: 1.6)
        XCTAssertEqual(gains.r, 1.0, accuracy: 1e-9)
        XCTAssertEqual(gains.g, 1.6, accuracy: 1e-9)
        XCTAssertEqual(gains.b, 1.6, accuracy: 1e-9)

        // Nearly dark estimate → unit gains (nothing to balance).
        let dark = Illumination.whiteBalanceGains(average: (0.004, 0.002, 0.003))
        XCTAssertEqual(dark.r, 1.0)
        XCTAssertEqual(dark.g, 1.0)
        XCTAssertEqual(dark.b, 1.0)
    }

    func testNormalizedChainNeutralizesSolidWarmImage() {
        // A solid warm image: the border average equals the fill color, so
        // white balance must map it to a neutral gray.
        let warm = TestImageFactory.solid(width: 120, height: 160, r: 0.6, g: 0.5, b: 0.4)
        let ci = CIImage(cgImage: warm)
        let out = Illumination.normalized(image: ci, context: context)
        let cg = context.createCGImage(out, from: ci.extent)!

        let (w, h, pixels) = TestImageFactory.rgba(cg)
        let i = ((h / 2) * w + w / 2) * 4
        let r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
        // All channels equal within a small tolerance (neutral gray).
        let mean = (r + g + b) / 3
        XCTAssertLessThan(abs(r - mean), 4, "red must be neutral, got (\(r), \(g), \(b))")
        XCTAssertLessThan(abs(g - mean), 4, "green must be neutral")
        XCTAssertLessThan(abs(b - mean), 4, "blue must be neutral")
    }

    func testBorderAverageOfUniformImageEqualsFillColor() {
        let fill = TestImageFactory.solid(width: 200, height: 140, r: 0.9, g: 0.8, b: 0.7)
        let ci = CIImage(cgImage: fill)
        let avg = Illumination.borderAverage(of: ci, context: context)
        XCTAssertNotNil(avg)
        XCTAssertEqual(avg!.r, 0.9, accuracy: 0.01)
        XCTAssertEqual(avg!.g, 0.8, accuracy: 0.01)
        XCTAssertEqual(avg!.b, 0.7, accuracy: 0.01)
    }
}
