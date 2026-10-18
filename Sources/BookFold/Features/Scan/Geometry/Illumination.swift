//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import CoreImage
import CoreGraphics
import Foundation

/// Tuning knobs for the "clean book page" look.
struct IlluminationSettings: Sendable {
    /// Slight contrast lift — makes text crisp without clipping.
    var contrast: CGFloat = 1.06
    /// Mild desaturation — paper should read as near-neutral.
    var saturation: CGFloat = 0.85
    /// Small brightness lift to open shadows near the spine.
    var brightness: CGFloat = 0.02
    /// Upper bound for per-channel white-balance gain (never darken, never
    /// amplify a dark scene absurdly).
    var maxGain: CGFloat = 1.6
}

/// Illumination normalization for book pages: border-based white balance +
/// gentle contrast/saturation shaping. Deterministic, all knobs pure math.
enum Illumination {
    /// The CIContext the normalization chain must run in.
    ///
    /// White balance is a per-channel gain computed from *encoded* (gamma)
    /// border values. A color-managed working space (CoreImage's default,
    /// linear sRGB) applies the gain in linear light instead, which leaves a
    /// residual color cast — a solid warm test image came out (153, 141, 127).
    /// Disabling the working color space keeps gains and filter math in the
    /// same domain, so the chain neutralizes casts as designed.
    static func makeContext() -> CIContext {
        CIContext(options: [
            .workingColorSpace: NSNull(),
            .cacheIntermediates: false,
        ])
    }

    /// Per-channel white-balance gains derived from an average color that is
    /// assumed to be *near-paper* (the page border).
    ///
    /// Gray-world style: the brightest channel defines the target, all
    /// channels are brightened towards it, gains are clamped to `[1, maxGain]`
    /// — we only ever neutralize a color cast, never darken the page.
    static func whiteBalanceGains(
        average: (r: CGFloat, g: CGFloat, b: CGFloat),
        maxGain: CGFloat = 1.6
    ) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let maxChannel = max(average.r, average.g, average.b)
        guard maxChannel > 0.01 else { return (1, 1, 1) }
        func gain(_ c: CGFloat) -> CGFloat {
            guard c > 0.01 else { return maxGain }
            return min(maxGain, max(1, maxChannel / c))
        }
        return (gain(average.r), gain(average.g), gain(average.b))
    }

    /// Average color of the four thin border strips of the corrected page
    /// (paper margin — a robust illuminant estimate even when the page has a
    /// strong color cast). Renders four 1×1 `CIAreaAverage` results.
    static func borderAverage(
        of image: CIImage,
        context: CIContext
    ) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        let extent = image.extent
        guard extent.width > 20, extent.height > 20 else { return nil }

        let thickness = min(extent.width, extent.height) * 0.06
        let inset = min(extent.width, extent.height) * 0.02
        let strips = [
            CGRect(x: extent.minX + inset, y: extent.maxY - thickness - inset, width: extent.width - 2 * inset, height: thickness), // top
            CGRect(x: extent.minX + inset, y: extent.minY + inset, width: extent.width - 2 * inset, height: thickness),             // bottom
            CGRect(x: extent.minX + inset, y: extent.minY + inset, width: thickness, height: extent.height - 2 * inset),            // left
            CGRect(x: extent.maxX - thickness - inset, y: extent.minY + inset, width: thickness, height: extent.height - 2 * inset),// right
        ]

        var acc: (r: CGFloat, g: CGFloat, b: CGFloat) = (0, 0, 0)
        var count: CGFloat = 0
        for rect in strips {
            guard let averageFilter = CIFilter(name: "CIAreaAverage") else { continue }
            averageFilter.setValue(image, forKey: kCIInputImageKey)
            averageFilter.setValue(CIVector(cgRect: rect), forKey: kCIInputExtentKey)
            guard let output = averageFilter.outputImage else { continue }

            var pixel = [UInt8](repeating: 0, count: 4)
            context.render(
                output,
                toBitmap: &pixel,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            acc.r += CGFloat(pixel[0]) / 255
            acc.g += CGFloat(pixel[1]) / 255
            acc.b += CGFloat(pixel[2]) / 255
            count += 1
        }
        guard count > 0 else { return nil }
        return (acc.r / count, acc.g / count, acc.b / count)
    }

    /// Full normalization chain: white balance → contrast → saturation →
    /// brightness. Pure CoreImage filter graph, no randomness.
    static func normalized(
        image: CIImage,
        settings: IlluminationSettings = IlluminationSettings(),
        context: CIContext
    ) -> CIImage {
        var working = image

        // White balance via per-channel scaling (CIColorMatrix).
        if let border = borderAverage(of: image, context: context) {
            let gains = whiteBalanceGains(average: border, maxGain: settings.maxGain)
            if let matrix = CIFilter(name: "CIColorMatrix") {
                matrix.setValue(working, forKey: kCIInputImageKey)
                matrix.setValue(CIVector(x: gains.r, y: 0, z: 0, w: 0), forKey: "inputRVector")
                matrix.setValue(CIVector(x: 0, y: gains.g, z: 0, w: 0), forKey: "inputGVector")
                matrix.setValue(CIVector(x: 0, y: 0, z: gains.b, w: 0), forKey: "inputBVector")
                matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
                working = matrix.outputImage ?? working
            }
        }

        if let controls = CIFilter(name: "CIColorControls") {
            controls.setValue(working, forKey: kCIInputImageKey)
            controls.setValue(settings.contrast, forKey: kCIInputContrastKey)
            controls.setValue(settings.saturation, forKey: kCIInputSaturationKey)
            controls.setValue(settings.brightness, forKey: kCIInputBrightnessKey)
            working = controls.outputImage ?? working
        }

        return working.cropped(to: image.extent)
    }
}
