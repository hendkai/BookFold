//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import Foundation

/// Drives auto-capture: a rectangle must stay *still* for `stableDuration`
/// before a shot fires, and the tracker then re-arms only when the scene
/// changes — the page being turned (rectangle lost for a moment, or replaced
/// by a clearly different one) counts as "changed", jitter does not.
///
/// Pure value type over an injected clock, fully unit-tested; the camera
/// controller feeds it `update(quad:now:)` once per detection frame.
struct StabilityTracker: Sendable {
    /// How long the quad must hold still before auto-capture fires.
    var stableDuration: TimeInterval = 1.1
    /// Max corner movement (normalized units) that still counts as "still".
    var cornerTolerance: CGFloat = 0.03
    /// A new quad whose bounding-box IoU with the captured one is below this
    /// is treated as "page turned" and re-arms the tracker.
    var rearmChangeIoU: CGFloat = 0.55
    /// How long the quad may be lost before we go back to searching.
    var rearmLostDuration: TimeInterval = 0.35

    init(
        stableDuration: TimeInterval = 1.1,
        cornerTolerance: CGFloat = 0.03,
        rearmChangeIoU: CGFloat = 0.55,
        rearmLostDuration: TimeInterval = 0.35
    ) {
        self.stableDuration = stableDuration
        self.cornerTolerance = cornerTolerance
        self.rearmChangeIoU = rearmChangeIoU
        self.rearmLostDuration = rearmLostDuration
    }

    enum Phase: Equatable, Sendable {
        /// No plausible rectangle in frame.
        case searching
        /// Tracking a rectangle, waiting for it to settle.
        case tracking
        /// A capture fired; waiting for the scene to change (page turn).
        case captured
    }

    enum Event: Equatable, Sendable {
        /// The quad was stable for `stableDuration` — capture now.
        case autoCapture(Quad)
    }

    private(set) var phase: Phase = .searching
    /// The quad currently being tracked (nil while searching).
    private(set) var reference: Quad?
    private var stableSince: TimeInterval = 0
    private var lastQuadSeenAt: TimeInterval = 0
    private var capturedQuad: Quad?

    /// Seconds until auto-capture fires (0 when not applicable) — for UI hints.
    func timeRemaining(now: TimeInterval) -> TimeInterval {
        guard phase == .tracking, let ref = reference else { return 0 }
        return max(0, stableDuration - (now - stableSince))
    }

    /// Feed one detection frame. Returns `.autoCapture` exactly once per
    /// stability period.
    mutating func update(quad: Quad?, now: TimeInterval) -> Event? {
        if let quad {
            lastQuadSeenAt = now
            switch phase {
            case .searching:
                reference = quad
                stableSince = now
                phase = .tracking

            case .tracking:
                if let ref = reference, quad.isSimilar(to: ref, tolerance: cornerTolerance) {
                    if now - stableSince >= stableDuration {
                        phase = .captured
                        capturedQuad = ref
                        return .autoCapture(ref)
                    }
                    // Still holding — keep the original reference & timestamp.
                } else {
                    // Moved or a different rectangle: restart the stability clock.
                    reference = quad
                    stableSince = now
                }

            case .captured:
                if let captured = capturedQuad,
                   quad.boundingBoxIoU(with: captured) < rearmChangeIoU {
                    // Scene changed (page turned without losing the rectangle).
                    reference = quad
                    stableSince = now
                    phase = .tracking
                }
            }
        } else {
            // No rectangle in this frame.
            if now - lastQuadSeenAt > rearmLostDuration, phase != .searching {
                phase = .searching
                reference = nil
                capturedQuad = nil
            }
        }
        return nil
    }

    /// Call after a *manual* capture so auto-capture doesn't immediately
    /// double-fire on the same stable scene.
    mutating func markCaptured(quad: Quad, now: TimeInterval) {
        reference = quad
        stableSince = now
        capturedQuad = quad
        phase = .captured
        lastQuadSeenAt = now
    }

    mutating func reset() {
        self = StabilityTracker(
            stableDuration: stableDuration,
            cornerTolerance: cornerTolerance,
            rearmChangeIoU: rearmChangeIoU,
            rearmLostDuration: rearmLostDuration
        )
    }
}
