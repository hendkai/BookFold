//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import CoreImage
import UIKit

@testable import BookFold

/// Deterministic synthetic "book page" images for pipeline tests.
///
/// All rendering uses a bottom-left origin (CoreGraphics default), matching
/// the Vision/CoreImage conventions used by the app — no coordinate flips
/// anywhere in the helpers.
enum TestImageFactory {
    /// Same context the pipeline uses (unmanaged working space) so the
    /// synthetic photos and the pipeline agree on pixel values.
    static let context = Illumination.makeContext()

    // MARK: Content rendering

    /// A white page with black "text" bars and a thin black border.
    ///
    /// `curvature` bends only the *content* lines by
    /// `curvature * sin(π·x/width)` pixels — the page border stays a perfect
    /// rectangle, mimicking a book where the photographer aligns the page
    /// edges but the inner curl survives (dewarp is a later pipeline stage).
    static func pageContent(
        width: Int,
        height: Int,
        curvature: CGFloat = 0,
        markerAtCenter: Bool = false
    ) -> CGImage {
        let W = CGFloat(width), H = CGFloat(height)

        let cgContext = makeBitmapContext(width: width, height: height)
        cgContext.setFillColor(gray: 1, alpha: 1)
        cgContext.fill(CGRect(x: 0, y: 0, width: W, height: H))

        // Thin black border (the detectable page edge).
        cgContext.setFillColor(gray: 0, alpha: 1)
        let b: CGFloat = 6
        cgContext.fill(CGRect(x: 0, y: 0, width: W, height: b))
        cgContext.fill(CGRect(x: 0, y: H - b, width: W, height: b))
        cgContext.fill(CGRect(x: 0, y: 0, width: b, height: H))
        cgContext.fill(CGRect(x: W - b, y: 0, width: b, height: H))

        // Text bars.
        cgContext.setFillColor(gray: 0.1, alpha: 1)
        let inset: CGFloat = 60
        let barHeight: CGFloat = max(4, H / 90)
        let rowStride = max(12, H / 26)
        var y = inset
        while y < H - inset - barHeight {
            // One bar per row; with curvature, draw it as 1px slices.
            if curvature > 0 {
                var x = inset
                while x < W - inset {
                    let dy = curvature * sin(.pi * x / W)
                    cgContext.fill(CGRect(x: x, y: y + dy, width: 1.5, height: barHeight))
                    x += 1
                }
            } else {
                let length = (W - 2 * inset) * (0.82 + 0.12 * sin(y * 0.37))
                cgContext.fill(CGRect(x: inset, y: y, width: length, height: barHeight))
            }
            y += rowStride
        }

        // Optional dark marker square in the center (used to tell halves of
        // a spread apart).
        if markerAtCenter {
            let s: CGFloat = min(W, H) * 0.18
            cgContext.fill(CGRect(x: W / 2 - s / 2, y: H / 2 - s / 2, width: s, height: s))
        }

        return cgContext.makeImage()!
    }

    /// A two-page spread: white pages separated by a dark spine gap. The left
    /// page carries a dark center marker, the right page stays clean.
    static func spreadContent(width: Int, height: Int) -> CGImage {
        let W = CGFloat(width), H = CGFloat(height)
        let cgContext = makeBitmapContext(width: width, height: height)
        cgContext.setFillColor(gray: 1, alpha: 1)
        cgContext.fill(CGRect(x: 0, y: 0, width: W, height: H))

        // Spine gap.
        cgContext.setFillColor(gray: 0.15, alpha: 1)
        cgContext.fill(CGRect(x: W / 2 - W * 0.012, y: 0, width: W * 0.024, height: H))

        // Text bars on both pages.
        cgContext.setFillColor(gray: 0.1, alpha: 1)
        for page in [CGRect(x: 0, y: 0, width: W / 2 - W * 0.03, height: H),
                     CGRect(x: W / 2 + W * 0.03, y: 0, width: W / 2 - W * 0.03, height: H)] {
            let inset: CGFloat = 50
            let barHeight: CGFloat = max(4, H / 90)
            let rowStride = max(12, H / 26)
            var y = inset
            while y < page.height - inset - barHeight {
                let length = (page.width - 2 * inset) * 0.8
                cgContext.fill(CGRect(x: page.minX + inset, y: y, width: length, height: barHeight))
                y += rowStride
            }
        }

        // Dark marker on the left page center.
        cgContext.setFillColor(gray: 0, alpha: 1)
        let s: CGFloat = min(W, H) * 0.16
        cgContext.fill(CGRect(x: W * 0.25 - s / 2, y: H / 2 - s / 2, width: s, height: s))

        return cgContext.makeImage()!
    }

    /// A solid-color image (illumination fixtures).
    static func solid(width: Int, height: Int, r: CGFloat, g: CGFloat, b: CGFloat) -> CGImage {
        let cgContext = makeBitmapContext(width: width, height: height)
        cgContext.setFillColor(red: r, green: g, blue: b, alpha: 1)
        cgContext.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        return cgContext.makeImage()!
    }

    // MARK: "Photographing"

    /// Projects `page` onto a dark canvas so its corners land exactly on
    /// `quad` (normalized, bottom-left origin) — a synthetic photo with known
    /// ground truth.
    static func photographed(page: CGImage, canvasSize: CGSize, quad: Quad) -> CGImage {
        let canvas = CIImage(color: CIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)).cropped(
            to: CGRect(origin: .zero, size: canvasSize)
        )

        let px = quad.pixelPoints(in: canvasSize)
        guard let warp = CIFilter(name: "CIPerspectiveTransform") else {
            fatalError("CIPerspectiveTransform unavailable")
        }
        warp.setValue(CIImage(cgImage: page), forKey: kCIInputImageKey)
        warp.setValue(CIVector(cgPoint: px[0]), forKey: "inputTopLeft")
        warp.setValue(CIVector(cgPoint: px[1]), forKey: "inputTopRight")
        warp.setValue(CIVector(cgPoint: px[2]), forKey: "inputBottomRight")
        warp.setValue(CIVector(cgPoint: px[3]), forKey: "inputBottomLeft")

        let warped = warp.outputImage!.composited(over: canvas)
            .cropped(to: CGRect(origin: .zero, size: canvasSize))
        return context.createCGImage(warped, from: CGRect(origin: .zero, size: canvasSize))!
    }

    // MARK: Pixel access

    /// RGBA8 bytes of an image (premultiplied).
    static func rgba(_ image: CGImage) -> (width: Int, height: Int, pixels: [UInt8]) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let cgContext = CGContext(
            data: &data,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        cgContext.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (w, h, data)
    }

    /// Mean brightness (0…255) of a fractional rect of the image.
    static func meanBrightness(_ image: CGImage, in region: CGRect) -> CGFloat {
        let (w, h, pixels) = rgba(image)
        let x0 = max(0, Int(region.minX * CGFloat(w)))
        let x1 = min(w, Int(region.maxX * CGFloat(w)))
        let y0 = max(0, Int(region.minY * CGFloat(h)))
        let y1 = min(h, Int(region.maxY * CGFloat(h)))
        guard x1 > x0, y1 > y0 else { return 0 }

        var sum: CGFloat = 0
        var count: CGFloat = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = (y * w + x) * 4
                sum += (CGFloat(pixels[i]) + CGFloat(pixels[i + 1]) + CGFloat(pixels[i + 2])) / 3
                count += 1
            }
        }
        return sum / count
    }

    // MARK: Private

    private static func makeBitmapContext(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }
}
