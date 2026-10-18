//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics

/// One half of a detected two-page spread.
struct SplitHalf: Hashable, Sendable {
    enum Side: String, Sendable {
        /// Constructed from the quad's left corners — the image-left half for
        /// an upright scene. In reading order of an open book this is the
        /// *earlier* page (verso).
        case left
        case right
    }

    let quad: Quad
    let side: Side
}

/// Two-page spread handling: split the detected rectangle at the middle and
/// order the halves in reading order (image-left first — for an upright
/// open book, the left page is the earlier one).
///
/// Splitting happens in *quad space* **before** perspective correction:
/// each half is then corrected independently from the full-resolution
/// source, so both pages get their own clean rectangle, a straight spine
/// edge, and symmetric margins. (Splitting the already-corrected image
/// would inherit one perspective fit for two different page planes.)
enum SpreadSplitter {
    /// The two half-quads, ordered in reading order: image-left first.
    /// `Side` reflects which corners the half was *constructed from* — for an
    /// upright scene that matches image position; a mirrored scene (book
    /// photographed 180°-rotated) yields `[.right, .left]`, which downstream
    /// stages can use as a rotation hint.
    static func orderedHalves(of quad: Quad, ratio: CGFloat = 0.5) -> [SplitHalf] {
        let halves = quad.split(at: ratio)
        let left = SplitHalf(quad: halves.left, side: .left)
        let right = SplitHalf(quad: halves.right, side: .right)
        return halves.left.center.x <= halves.right.center.x ? [left, right] : [right, left]
    }

    /// Ordered reading-order halves in CoreImage pixel coordinates.
    static func orderedPixelQuads(of quad: Quad, sourceSize: CGSize, ratio: CGFloat = 0.5) -> [Quad] {
        orderedHalves(of: quad, ratio: ratio).map(\.quad).map { sub in
            let pts = sub.pixelPoints(in: sourceSize)
            return Quad(
                topLeft: pts[0], topRight: pts[1],
                bottomRight: pts[2], bottomLeft: pts[3]
            )
        }
    }
}
