//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import CoreImage

/// Everything needed to run `CIPerspectiveCorrection` for one quad,
/// precomputed as pure math so it is unit-testable without a CIContext.
struct PerspectiveCorrectionPlan: Equatable, Sendable {
    /// Corner points in *source pixel* coordinates, CoreImage convention
    /// (origin bottom-left), canonical order TL, TR, BR, BL.
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint
    /// Output size in pixels; the long edge is capped at the target and never
    /// upscaled.
    var outputSize: CGSize

    var points: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }
}

/// Maps a detected quad onto `CIPerspectiveCorrection` parameters and renders
/// the corrected page.
///
/// Coordinate chain (unit-tested end to end): Vision reports normalized
/// bottom-left-origin points → `Quad.pixelPoints` multiplies by the *pixel*
/// size of the actual captured image (photo or buffer) → CoreImage consumes
/// them unchanged, because CI uses the same bottom-left origin.
enum PerspectiveCorrector {
    /// Builds the correction plan for `quad` observed in an image of
    /// `sourceSize` pixels. Output long edge is `targetLongEdge`, capped so
    /// we never upscale beyond the quad's native pixel resolution.
    static func plan(
        quad: Quad,
        sourceSize: CGSize,
        targetLongEdge: CGFloat = ScanPipelineDefaults.targetLongEdge
    ) -> PerspectiveCorrectionPlan {
        let p = quad.pixelPoints(in: sourceSize)
        let width = 0.5 * (hypot(p[0].x - p[1].x, p[0].y - p[1].y) + hypot(p[3].x - p[2].x, p[3].y - p[2].y))
        let height = 0.5 * (hypot(p[0].x - p[3].x, p[0].y - p[3].y) + hypot(p[1].x - p[2].x, p[1].y - p[2].y))

        let longest = max(width, height, 1)
        let scale = min(1, targetLongEdge / longest)

        return PerspectiveCorrectionPlan(
            topLeft: p[0],
            topRight: p[1],
            bottomRight: p[2],
            bottomLeft: p[3],
            outputSize: CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
        )
    }

    /// Renders the perspective-corrected page for `plan`.
    ///
    /// The corrected image is cropped to the plan's extent and downscaled
    /// with Lanczos resampling to the plan's output size.
    static func correctedImage(
        source: CGImage,
        plan: PerspectiveCorrectionPlan,
        context: CIContext
    ) -> CGImage? {
        let input = CIImage(cgImage: source)
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: plan.topLeft), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: plan.topRight), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: plan.bottomRight), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: plan.bottomLeft), forKey: "inputBottomLeft")

        guard let corrected = filter.outputImage else { return nil }

        // The filter emits the corrected rect anchored at the extent origin;
        // crop to the plan's aspect at native resolution first …
        let extent = corrected.extent
        let cropW = min(plan.outputSize.width, extent.width).rounded(.up)
        let cropH = min(plan.outputSize.height, extent.height).rounded(.up)
        let cropped = corrected.cropped(
            to: CGRect(x: extent.minX, y: extent.minY, width: cropW, height: cropH)
        )

        // … then downscale to the plan size with a high-quality resample.
        var output = cropped
        let sx = cropW > 0 ? plan.outputSize.width / cropW : 1
        let sy = cropH > 0 ? plan.outputSize.height / cropH : 1
        let s = min(sx, sy)
        if s < 0.999, let scaleFilter = CIFilter(name: "CILanczosScaleTransform") {
            scaleFilter.setValue(output, forKey: kCIInputImageKey)
            scaleFilter.setValue(s, forKey: kCIInputScaleKey)
            scaleFilter.setValue(1.0, forKey: kCIInputAspectRatioKey)
            if let scaled = scaleFilter.outputImage {
                output = scaled.cropped(to: CGRect(origin: .zero, size: plan.outputSize))
            }
        }

        return context.createCGImage(output, from: CGRect(origin: .zero, size: plan.outputSize))
    }
}

/// Shared defaults for the scan pipeline.
enum ScanPipelineDefaults {
    /// Long-edge resolution of corrected pages (JPEG-friendly, plenty for
    /// later OCR; full-res photos are downscaled, never upscaled).
    static let targetLongEdge: CGFloat = 2400
}
