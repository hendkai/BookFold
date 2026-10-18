//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics

/// A page quadrilateral in *normalized Vision coordinates*:
/// origin bottom-left, x pointing right, y pointing up, components in `0...1`.
///
/// This is the coordinate space `VNDetectRectanglesRequest` reports, and it
/// maps 1:1 onto CoreImage's pixel space (`x * width`, `y * height`) without
/// any axis flips — the two conversions that exist (`pixelPoints` for CoreImage,
/// `layerPoints` for screen overlays) are the only places orientation is
/// touched, and both are unit-tested.
struct Quad: Hashable, Sendable {
    /// Corners in canonical order: top-left, top-right, bottom-right, bottom-left.
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    /// Canonicalizes four raw, unordered corner points into a `Quad`.
    ///
    /// Sorts the points counter-clockwise around the centroid (y-up space,
    /// starting at the bottom-most point), which yields the cyclic order
    /// `[bottom-left, bottom-right, top-right, top-left]`. Returns `nil` for
    /// non-convex or degenerate input — the caller then falls back
    /// (e.g. whole-frame quad for manual import).
    static func normalized(_ points: [CGPoint]) -> Quad? {
        guard points.count == 4 else { return nil }

        let centroid = points.reduce(CGPoint.zero) { acc, p in
            CGPoint(x: acc.x + p.x / 4, y: acc.y + p.y / 4)
        }

        // Reject degenerate clouds: every corner must sit clearly away from
        // the centroid, and the polygon must be convex with real area.
        for p in points where hypot(p.x - centroid.x, p.y - centroid.y) < 0.02 { return nil }
        guard abs(signedArea(points)) > 0.001 else { return nil }
        guard isConvex(points) else { return nil }

        let sorted = points.sorted { a, b in
            let aa = atan2(a.y - centroid.y, a.x - centroid.x)
            let ab = atan2(b.y - centroid.y, b.x - centroid.x)
            if aa == ab { return a.x < b.x }
            return aa < ab
        }

        // Sorted CCW starting at the most-negative angle; rotate so the array
        // begins at the bottom-most (then left-most) corner → [BL, BR, TR, TL].
        var start = 0
        for (i, p) in sorted.enumerated() {
            let best = sorted[start]
            if p.y < best.y || (p.y == best.y && p.x < best.x) { start = i }
        }
        let rotated = Array(sorted[start...] + sorted[..<start])

        guard rotated.count == 4 else { return nil }
        let bl = rotated[0], br = rotated[1], tr = rotated[2], tl = rotated[3]
        return Quad(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl)
    }

    /// The four corners in canonical order TL, TR, BR, BL.
    var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    var center: CGPoint {
        CGPoint(
            x: corners.map(\.x).reduce(0, +) / 4,
            y: corners.map(\.y).reduce(0, +) / 4
        )
    }

    /// Absolute shoelace area in normalized units (max 1.0).
    var area: CGFloat { abs(Quad.signedArea(corners)) }

    /// Average edge-length aspect (width / height) of the quad, in *image*
    /// orientation — perspective foreshortening means this is an estimate.
    var edgeAspect: CGFloat {
        let width = 0.5 * (hypot2(topLeft, topRight) + hypot2(bottomLeft, bottomRight))
        let height = 0.5 * (hypot2(topLeft, bottomLeft) + hypot2(topRight, bottomRight))
        guard height > 0 else { return 0 }
        return width / height
    }

    /// True when all four corners of `self` and `other` are within
    /// `tolerance` (normalized units) of each other.
    func isSimilar(to other: Quad, tolerance: CGFloat) -> Bool {
        let a = corners
        let b = other.corners
        for i in 0..<4 where hypot2(a[i], b[i]) > tolerance { return false }
        return true
    }

    /// Intersection-over-union of the two quads' bounding boxes.
    /// An approximation (boxes, not polygons) — used only to detect *large*
    /// changes like a page being turned, where it is accurate enough.
    func boundingBoxIoU(with other: Quad) -> CGFloat {
        func box(_ q: Quad) -> CGRect {
            let xs = q.corners.map(\.x), ys = q.corners.map(\.y)
            return CGRect(
                x: xs.min()!, y: ys.min()!,
                width: xs.max()! - xs.min()!,
                height: ys.max()! - ys.min()!
            )
        }
        let i = box(self).intersection(box(other))
        guard !i.isNull, i.width > 0, i.height > 0 else { return 0 }
        let inter = i.width * i.height
        let union = area + other.area - inter
        guard union > 0 else { return 0 }
        return inter / union
    }

    /// Splits the quad into left/right halves by interpolating the top and
    /// bottom edges at `ratio` (0.5 = geometric middle). Used for two-page
    /// spreads of open books.
    func split(at ratio: CGFloat = 0.5) -> (left: Quad, right: Quad) {
        let topMid = CGPoint(
            x: topLeft.x + (topRight.x - topLeft.x) * ratio,
            y: topLeft.y + (topRight.y - topLeft.y) * ratio
        )
        let bottomMid = CGPoint(
            x: bottomLeft.x + (bottomRight.x - bottomLeft.x) * ratio,
            y: bottomLeft.y + (bottomRight.y - bottomLeft.y) * ratio
        )
        let left = Quad(topLeft: topLeft, topRight: topMid, bottomRight: bottomMid, bottomLeft: bottomLeft)
        let right = Quad(topLeft: topMid, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomMid)
        return (left, right)
    }

    /// Pixel coordinates in a CoreImage-compatible space (origin bottom-left),
    /// same canonical corner order — feed straight into
    /// `CIPerspectiveCorrection`'s `inputTopLeft…inputBottomRight`.
    func pixelPoints(in size: CGSize) -> [CGPoint] {
        corners.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
    }

    /// Layer/view coordinates (origin top-left, y down) for drawing the live
    /// edge overlay. `size` must match the aspect-fit preview area.
    func layerPoints(in size: CGSize) -> [CGPoint] {
        corners.map { CGPoint(x: $0.x * size.width, y: (1 - $0.y) * size.height) }
    }

    /// A quad covering the whole frame — fallback when no rectangle is found
    /// (e.g. photo import without clear page edges).
    static let fullFrame = Quad(
        topLeft: CGPoint(x: 0, y: 1),
        topRight: CGPoint(x: 1, y: 1),
        bottomRight: CGPoint(x: 1, y: 0),
        bottomLeft: CGPoint(x: 0, y: 0)
    )

    // MARK: - Private helpers

    private static func signedArea(_ pts: [CGPoint]) -> CGFloat {
        var sum: CGFloat = 0
        for i in 0..<pts.count {
            let a = pts[i]
            let b = pts[(i + 1) % pts.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    private static func isConvex(_ pts: [CGPoint]) -> Bool {
        var sign: Int?
        for i in 0..<pts.count {
            let a = pts[i]
            let b = pts[(i + 1) % pts.count]
            let c = pts[(i + 2) % pts.count]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            let s = cross > 0 ? 1 : (cross < 0 ? -1 : 0)
            if s != 0 {
                if let existing = sign, existing != s { return false }
                sign = s
            }
        }
        return sign != nil
    }

    private func hypot2(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
