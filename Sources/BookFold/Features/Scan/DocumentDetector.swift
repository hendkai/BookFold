//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import CoreVideo
import Vision

/// Thin, testable wrapper around `VNDetectRectanglesRequest`.
///
/// All policy (which rectangle counts as "the page") lives in the pure
/// `selectBest` function; the Vision plumbing just turns observations into
/// `Quad`s. Runs fully on-device — no network, ever.
struct DocumentDetector: Sendable {
    var minimumConfidence: Float = 0.6
    var minimumAspectRatio: CGFloat = 0.2
    var maximumAspectRatio: CGFloat = 2.0
    var minimumSize: CGFloat = 0.15

    /// Picks the best rectangle from ranked Vision observations: the largest
    /// by area that passes the aspect sanity check. Larger = closer to the
    /// camera = almost always the page the user intends to scan.
    static func selectBest(
        candidates: [(quad: Quad, confidence: Float)],
        minimumAspectRatio: CGFloat = 0.2,
        maximumAspectRatio: CGFloat = 2.0,
        minimumSize: CGFloat = 0.15
    ) -> Quad? {
        candidates
            .filter { $0.confidence >= 0.5 }
            .filter {
                $0.quad.edgeAspect >= minimumAspectRatio
                    && $0.quad.edgeAspect <= maximumAspectRatio
                    && $0.quad.area >= minimumSize * minimumSize * 0.5
            }
            .max { $0.quad.area < $1.quad.area }?
            .quad
    }

    /// Best page quad in a still image (photo import path).
    func bestQuad(in image: CGImage) -> Quad? {
        let request = makeRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return Self.selectBest(
            candidates: observations(from: request),
            minimumAspectRatio: minimumAspectRatio,
            maximumAspectRatio: maximumAspectRatio,
            minimumSize: minimumSize
        )
    }

    /// Best page quad in a live camera frame (auto-capture path).
    func bestQuad(in pixelBuffer: CVPixelBuffer) -> Quad? {
        let request = makeRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return Self.selectBest(
            candidates: observations(from: request),
            minimumAspectRatio: minimumAspectRatio,
            maximumAspectRatio: maximumAspectRatio,
            minimumSize: minimumSize
        )
    }

    // MARK: - Private

    private func makeRequest() -> VNDetectRectanglesRequest {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 5
        request.minimumConfidence = minimumConfidence
        request.minimumAspectRatio = Float(minimumAspectRatio)
        request.maximumAspectRatio = Float(maximumAspectRatio)
        request.minimumSize = Float(minimumSize)
        request.quadratureTolerance = 25
        return request
    }

    private func observations(from request: VNDetectRectanglesRequest) -> [(quad: Quad, confidence: Float)] {
        request.results?.map { obs in
            let q = Quad(
                topLeft: obs.topLeft,
                topRight: obs.topRight,
                bottomRight: obs.bottomRight,
                bottomLeft: obs.bottomLeft
            )
            return (q, obs.confidence)
        } ?? []
    }
}
