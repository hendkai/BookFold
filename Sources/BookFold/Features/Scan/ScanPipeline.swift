//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import CoreImage

/// What the scanner is looking at.
enum ScanMode: String, CaseIterable, Sendable, Identifiable {
    /// One page per shot — flat sheets, single pages.
    case singlePage
    /// An open book: one shot yields two consecutive pages.
    case spread

    var id: String { rawValue }
}

/// Geometry-only scan pipeline v1: perspective correction + illumination
/// normalization (+ spread splitting). Page curvature survives by design —
/// non-linear dewarping is a separate, later stage.
///
/// `CIContext` is documented thread-safe and all other members are immutable,
/// hence `@unchecked Sendable`: the pipeline may be called from the camera
/// queue or the main actor.
final class ScanPipeline: @unchecked Sendable {
    let context: CIContext
    var targetLongEdge: CGFloat
    var illumination: IlluminationSettings

    init(
        targetLongEdge: CGFloat = ScanPipelineDefaults.targetLongEdge,
        illumination: IlluminationSettings = IlluminationSettings(),
        context: CIContext = Illumination.makeContext()
    ) {
        self.targetLongEdge = targetLongEdge
        self.illumination = illumination
        self.context = context
    }

    /// Processes one capture into 1 (single page) or 2 (spread → reading
    /// order) corrected page images.
    func processPages(source: CGImage, quad: Quad, mode: ScanMode) -> [CGImage] {
        switch mode {
        case .singlePage:
            return [source].compactMap { page(source: $0, quad: quad) }
        case .spread:
            let halves = SpreadSplitter.orderedHalves(of: quad)
            return halves.compactMap { half in
                page(source: source, quad: half.quad)
            }
        }
    }

    /// Single quad → corrected, illumination-normalized page.
    func page(source: CGImage, quad: Quad) -> CGImage? {
        let size = CGSize(width: source.width, height: source.height)
        let plan = PerspectiveCorrector.plan(
            quad: quad,
            sourceSize: size,
            targetLongEdge: targetLongEdge
        )
        guard let corrected = PerspectiveCorrector.correctedImage(
            source: source,
            plan: plan,
            context: context
        ) else { return nil }

        // Illumination normalization on the corrected page.
        let ci = CIImage(cgImage: corrected)
        let normalized = Illumination.normalized(
            image: ci,
            settings: illumination,
            context: context
        )
        let outExtent = CGRect(origin: .zero, size: plan.outputSize)
        return context.createCGImage(normalized, from: outExtent) ?? corrected
    }
}
