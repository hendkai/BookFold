//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// A coarse sampling grid as predicted by the UVDoc network.
///
/// Semantics match `torch.nn.functional.grid_sample(..., align_corners=True)`
/// applied to the upsampled grid from `utils.bilinear_unwarping`: for every
/// output pixel the grid yields the *source* location, in normalized
/// coordinates where -1 is the first and +1 the last source pixel center.
struct DewarpGrid: Sendable, Equatable {
    /// Grid height (45 for the 712 px network input).
    let rows: Int
    /// Grid width (31 for the 488 px network input).
    let cols: Int
    /// Row-major source x per cell, normalized to [-1, 1].
    let sourceX: [Float]
    /// Row-major source y per cell, normalized to [-1, 1].
    let sourceY: [Float]

    init(rows: Int, cols: Int, sourceX: [Float], sourceY: [Float]) {
        precondition(rows >= 2 && cols >= 2, "a dewarp grid needs at least 2x2 cells")
        precondition(sourceX.count == rows * cols && sourceY.count == rows * cols)
        self.rows = rows
        self.cols = cols
        self.sourceX = sourceX
        self.sourceY = sourceY
    }

    /// Grid that maps every output pixel to itself (no-op dewarp).
    static func identity(rows: Int, cols: Int) -> DewarpGrid {
        var xs = [Float](repeating: 0, count: rows * cols)
        var ys = [Float](repeating: 0, count: rows * cols)
        for r in 0..<rows {
            for c in 0..<cols {
                xs[r * cols + c] = Float(c) / Float(cols - 1) * 2 - 1
                ys[r * cols + c] = Float(r) / Float(rows - 1) * 2 - 1
            }
        }
        return DewarpGrid(rows: rows, cols: cols, sourceX: xs, sourceY: ys)
    }
}

/// Float32 resampling of an RGBA8 raster through a `DewarpGrid`.
///
/// Output pixel (x, y) takes its colour from the source at the position the
/// grid assigns to it, bilinearly. Source positions outside the image are
/// paper-white (255) — a dewarped page border must not turn black.
enum DewarpResampler {
    /// - Parameters:
    ///   - pixels: `width * height * 4` bytes, row-major, 4 bytes per pixel
    ///     (alpha ignored, written back as 255).
    ///   - grid: coarse grid; upsampled bilinearly (align_corners) to the
    ///     output size.
    /// - Returns: `width * height * 4` bytes in the same layout.
    static func resample(pixels: [UInt8], width: Int, height: Int, grid: DewarpGrid) -> [UInt8] {
        precondition(width >= 2 && height >= 2, "resample needs at least 2x2 pixels")
        precondition(pixels.count == width * height * 4, "pixel buffer size mismatch")

        var out = [UInt8](repeating: 255, count: width * height * 4)
        let gw = grid.cols
        let gh = grid.rows
        let wm1 = Float(width - 1)
        let hm1 = Float(height - 1)
        let cellScaleX = Float(gw - 1) / wm1
        let cellScaleY = Float(gh - 1) / hm1
        let srcW = width
        let srcH = height

        pixels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                grid.sourceX.withUnsafeBufferPointer { gx in
                    grid.sourceY.withUnsafeBufferPointer { gy in
                        for y in 0..<height {
                            let fy = Float(y) * cellScaleY
                            let cy0 = min(Int(fy), gh - 2)
                            let ty = fy - Float(cy0)
                            for x in 0..<width {
                                let fx = Float(x) * cellScaleX
                                let cx0 = min(Int(fx), gw - 2)
                                let tx = fx - Float(cx0)

                                let i00 = cy0 * gw + cx0
                                let i01 = i00 + 1
                                let i10 = i00 + gw
                                let i11 = i10 + 1

                                let nx = (gx[i00] * (1 - tx) + gx[i01] * tx) * (1 - ty)
                                    + (gx[i10] * (1 - tx) + gx[i11] * tx) * ty
                                let ny = (gy[i00] * (1 - tx) + gy[i01] * tx) * (1 - ty)
                                    + (gy[i10] * (1 - tx) + gy[i11] * tx) * ty

                                // Normalized [-1, 1] -> source pixel coordinates (align_corners).
                                let px = (nx + 1) * 0.5 * wm1
                                let py = (ny + 1) * 0.5 * hm1
                                if !(px >= 0 && py >= 0 && px <= wm1 && py <= hm1) { continue }

                                let sx0 = min(Int(px), srcW - 1)
                                let sy0 = min(Int(py), srcH - 1)
                                let sx1 = min(sx0 + 1, srcW - 1)
                                let sy1 = min(sy0 + 1, srcH - 1)
                                let fxp = px - Float(sx0)
                                let fyp = py - Float(sy0)

                                let o = (y * width + x) * 4
                                let p00 = (sy0 * srcW + sx0) * 4
                                let p01 = (sy0 * srcW + sx1) * 4
                                let p10 = (sy1 * srcW + sx0) * 4
                                let p11 = (sy1 * srcW + sx1) * 4
                                for ch in 0..<3 {
                                    let top = Float(src[p00 + ch]) * (1 - fxp) + Float(src[p01 + ch]) * fxp
                                    let bottom = Float(src[p10 + ch]) * (1 - fxp) + Float(src[p11 + ch]) * fxp
                                    let v = top * (1 - fyp) + bottom * fyp
                                    dst[o + ch] = UInt8(max(0, min(255, v.rounded())))
                                }
                                dst[o + 3] = 255
                            }
                        }
                    }
                }
            }
        }
        return out
    }
}
