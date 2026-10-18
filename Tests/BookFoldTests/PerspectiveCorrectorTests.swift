//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import CoreImage
import XCTest

@testable import BookFold

final class PerspectiveCorrectorTests: XCTestCase {
    private let context = Illumination.makeContext()

    // A page quad as Vision would report it (normalized, bottom-left origin).
    private func quad(inset in1: CGFloat = 0.12) -> Quad {
        Quad(
            topLeft: CGPoint(x: in1, y: 0.9),
            topRight: CGPoint(x: 1 - in1, y: 0.92),
            bottomRight: CGPoint(x: 0.95 - in1 * 0.3, y: 0.08),
            bottomLeft: CGPoint(x: 0.05 + in1 * 0.3, y: 0.06)
        )
    }

    // MARK: - Plan math (pure)

    func testPlanMapsNormalizedQuadToPixels() {
        let source = CGSize(width: 4032, height: 3024)
        let q = Quad(
            topLeft: CGPoint(x: 0.1, y: 0.9),
            topRight: CGPoint(x: 0.9, y: 0.9),
            bottomRight: CGPoint(x: 0.9, y: 0.1),
            bottomLeft: CGPoint(x: 0.1, y: 0.1)
        )
        let plan = PerspectiveCorrector.plan(quad: q, sourceSize: source, targetLongEdge: 2400)
        XCTAssertEqual(plan.topLeft.x, 403.2, accuracy: 0.001)
        XCTAssertEqual(plan.topLeft.y, 2721.6, accuracy: 0.001)
        XCTAssertEqual(plan.bottomRight.x, 3628.8, accuracy: 0.001)
        XCTAssertEqual(plan.bottomRight.y, 302.4, accuracy: 0.001)
    }

    func testPlanCapsLongEdgeWithoutUpscaling() {
        let source = CGSize(width: 4032, height: 3024)

        // Big quad (~3200 px wide) → capped at 2400.
        let big = Quad(
            topLeft: CGPoint(x: 0.05, y: 0.95),
            topRight: CGPoint(x: 0.85, y: 0.95),
            bottomRight: CGPoint(x: 0.85, y: 0.15),
            bottomLeft: CGPoint(x: 0.05, y: 0.15)
        )
        let bigPlan = PerspectiveCorrector.plan(quad: big, sourceSize: source, targetLongEdge: 2400)
        XCTAssertEqual(max(bigPlan.outputSize.width, bigPlan.outputSize.height), 2400, accuracy: 1.0)
        XCTAssertLessThan(bigPlan.outputSize.width, 2401)

        // Small quad (~400 px wide) → not upscaled.
        let small = Quad(
            topLeft: CGPoint(x: 0.45, y: 0.6),
            topRight: CGPoint(x: 0.55, y: 0.6),
            bottomRight: CGPoint(x: 0.55, y: 0.5),
            bottomLeft: CGPoint(x: 0.45, y: 0.5)
        )
        let smallPlan = PerspectiveCorrector.plan(quad: small, sourceSize: source, targetLongEdge: 2400)
        XCTAssertEqual(smallPlan.outputSize.width, 403, accuracy: 2)
        XCTAssertEqual(smallPlan.outputSize.height, 302, accuracy: 2)
    }

    // MARK: - Integration (CoreImage round-trip)

    func testFlatPageRoundTripIsRectangular() {
        let page = TestImageFactory.pageContent(width: 600, height: 800)
        let canvasSize = CGSize(width: 900, height: 1100)
        let q = quad()
        let photo = TestImageFactory.photographed(page: page, canvasSize: canvasSize, quad: q)

        let pipeline = ScanPipeline(targetLongEdge: 800, context: context)
        let output = pipeline.page(source: photo, quad: q)

        XCTAssertNotNil(output)
        let out = output!
        XCTAssertEqual(max(out.width, out.height), 800, accuracy: 4)

        // Ground truth is 600:800 = 0.75, but this quad is a strong trapezoid
        // (~12 % inset per side). The mean-edge aspect estimator used by the
        // plan is biased by ~3 % here; the output must match the plan, and the
        // plan must stay within that known bias. Exact recovery for
        // non-keystoned pages: testAxisAlignedPageRecoversAspectExactly.
        let plan = PerspectiveCorrector.plan(quad: q, sourceSize: canvasSize, targetLongEdge: 800)
        XCTAssertEqual(
            Double(out.width) / Double(out.height),
            plan.outputSize.width / plan.outputSize.height,
            accuracy: 0.01
        )
        XCTAssertEqual(Double(out.width) / Double(out.height), 0.75, accuracy: 0.04)

        // Corners of the corrected page are paper (bright), not background.
        // Probes sit in the page margin (text starts at 10 % inset, the page
        // border is 1 %) so they never touch text bars.
        for region in [
            CGRect(x: 0.02, y: 0.02, width: 0.05, height: 0.05),
            CGRect(x: 0.93, y: 0.02, width: 0.05, height: 0.05),
            CGRect(x: 0.02, y: 0.93, width: 0.05, height: 0.05),
            CGRect(x: 0.93, y: 0.93, width: 0.05, height: 0.05),
        ] {
            XCTAssertGreaterThan(
                TestImageFactory.meanBrightness(out, in: region), 180,
                "corner region \(region) should be white paper"
            )
        }
    }

    /// Non-keystoned page: the axis-aligned quad is exactly 660×880 px, i.e.
    /// 0.75 — the plan must recover it within 1 %.
    func testAxisAlignedPageRecoversAspectExactly() {
        let page = TestImageFactory.pageContent(width: 600, height: 800)
        let canvasSize = CGSize(width: 900, height: 1100)
        let q = Quad(
            topLeft: CGPoint(x: 120.0 / 900, y: 0.9),
            topRight: CGPoint(x: 780.0 / 900, y: 0.9),
            bottomRight: CGPoint(x: 780.0 / 900, y: 0.1),
            bottomLeft: CGPoint(x: 120.0 / 900, y: 0.1)
        )
        let photo = TestImageFactory.photographed(page: page, canvasSize: canvasSize, quad: q)
        let pipeline = ScanPipeline(targetLongEdge: 800, context: context)
        guard let out = pipeline.page(source: photo, quad: q) else {
            return XCTFail("pipeline returned no page")
        }
        XCTAssertEqual(Double(out.width) / Double(out.height), 0.75, accuracy: 0.01)
    }

    /// The documented curved-page behavior: perspective is removed, curvature
    /// *survives* (dewarp is a later pipeline stage). We render the same page
    /// flat and curled, run both through the identical geometry pipeline and
    /// measure the bow of one text line.
    func testCurvedPageKeepsCurvatureWhileRemovingPerspective() {
        let canvasSize = CGSize(width: 900, height: 1100)
        let q = quad()
        let pipeline = ScanPipeline(targetLongEdge: 800, context: context)

        let flat = TestImageFactory.pageContent(width: 600, height: 800, curvature: 0)
        let curved = TestImageFactory.pageContent(width: 600, height: 800, curvature: 28)

        let flatPhoto = TestImageFactory.photographed(page: flat, canvasSize: canvasSize, quad: q)
        let curvedPhoto = TestImageFactory.photographed(page: curved, canvasSize: canvasSize, quad: q)

        let flatOut = pipeline.page(source: flatPhoto, quad: q)!
        let curvedOut = pipeline.page(source: curvedPhoto, quad: q)!

        // Perspective removed in both cases: page fills the output, corners
        // are bright paper.
        for out in [flatOut, curvedOut] {
            XCTAssertEqual(max(out.width, out.height), 800, accuracy: 4)
            XCTAssertGreaterThan(
                TestImageFactory.meanBrightness(out, in: CGRect(x: 0.03, y: 0.03, width: 0.94, height: 0.94)),
                120,
                "output should be dominated by paper, not dark background"
            )
        }

        let flatBow = maxLineBow(flatOut)
        let curvedBow = maxLineBow(curvedOut)

        // Flat control: text lines run essentially straight.
        XCTAssertLessThan(flatBow, 0.01, "flat page must come out flat (bow \(flatBow))")
        // Curved page: the bow clearly survives the geometry-only pipeline.
        XCTAssertGreaterThan(curvedBow, 0.02, "curvature must survive without dewarp (bow \(curvedBow))")
        XCTAssertGreaterThan(curvedBow / max(flatBow, 0.001), 3,
                             "curved output must be measurably more bowed than the flat control")
        // Ground truth: the fixture's chord-relative bow over the 10–90 % span
        // is 28 px × (1 − sin(0.1π)) on an 800 px page. The measurement must
        // agree with it (no hidden attenuation in the pipeline).
        let predicted = 28 * (1 - sin(0.1 * Double.pi)) / 800
        print("bow flat=\(flatBow) curved=\(curvedBow) predicted=\(predicted)")
        XCTAssertEqual(Double(curvedBow) / predicted, 1.0, accuracy: 0.25,
                       "measured bow \(curvedBow) vs analytic \(predicted)")
    }

    func testSpreadPipelineProducesTwoOrderedPages() {
        let spread = TestImageFactory.spreadContent(width: 1200, height: 700)
        let canvasSize = CGSize(width: 1500, height: 900)
        let q = Quad(
            topLeft: CGPoint(x: 0.1, y: 0.9),
            topRight: CGPoint(x: 0.9, y: 0.9),
            bottomRight: CGPoint(x: 0.9, y: 0.1),
            bottomLeft: CGPoint(x: 0.1, y: 0.1)
        )
        let photo = TestImageFactory.photographed(page: spread, canvasSize: canvasSize, quad: q)

        let pipeline = ScanPipeline(targetLongEdge: 1200, context: context)
        let pages = pipeline.processPages(source: photo, quad: q, mode: .spread)

        XCTAssertEqual(pages.count, 2, "a spread must produce exactly two pages")
        guard pages.count == 2 else { return }

        // Both pages have the expected aspect (~600:700 → ~0.86).
        for page in pages {
            XCTAssertEqual(Double(page.width) / Double(page.height), 600.0 / 700.0, accuracy: 0.06)
        }

        // Reading order: the FIRST page is the left one (dark center marker),
        // the second is the clean right page.
        let center = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        let firstBrightness = TestImageFactory.meanBrightness(pages[0], in: center)
        let secondBrightness = TestImageFactory.meanBrightness(pages[1], in: center)
        XCTAssertLessThan(firstBrightness, 140, "first page must be the marked LEFT page")
        XCTAssertGreaterThan(secondBrightness, 170, "second page must be the clean RIGHT page")
    }

    // MARK: - Helpers

    /// Maximum bow of one text line as a fraction of image height. Samples the
    /// darkest row per column across the full text span (10–90 % of the width,
    /// where the fixture's curved bars run), fits the chord between the span
    /// ends and returns the max deviation from it. The window must cover the
    /// whole span: the fixture curls as `sin(πx/W)`, which peaks mid-page, so a
    /// middle-only window would absorb most of the curl.
    private func maxLineBow(_ image: CGImage) -> CGFloat {
        let (w, h, pixels) = TestImageFactory.rgba(image)
        let x0 = Int(0.10 * Double(w)), x1 = Int(0.90 * Double(w))
        let y0 = Int(0.30 * Double(h)), y1 = Int(0.60 * Double(h))

        // Track ONE bar left to right: per column, the darkest row within a
        // small window around the previous column's bar. A plain per-column
        // argmin over the band jumps to the neighbouring bar (≈ one row stride
        // away) wherever the curl pushes a bar across the band edge. The
        // window clamps to the image, not the band: the curl moves the bar
        // ~20 px out of the band, and a band clamp would lose it there.
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

        // Chord through the means of the first and last 3 % of sampled columns.
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
