//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import XCTest

@testable import BookFold

final class StabilityTrackerTests: XCTestCase {
    private let pageA = Quad(
        topLeft: CGPoint(x: 0.1, y: 0.9),
        topRight: CGPoint(x: 0.9, y: 0.9),
        bottomRight: CGPoint(x: 0.9, y: 0.1),
        bottomLeft: CGPoint(x: 0.1, y: 0.1)
    )

    /// The same page, seen one book further away.
    private let pageAFar = Quad(
        topLeft: CGPoint(x: 0.2, y: 0.85),
        topRight: CGPoint(x: 0.8, y: 0.85),
        bottomRight: CGPoint(x: 0.8, y: 0.15),
        bottomLeft: CGPoint(x: 0.2, y: 0.15)
    )

    /// A completely different scene region (page turned).
    private let pageB = Quad(
        topLeft: CGPoint(x: 0.5, y: 0.95),
        topRight: CGPoint(x: 0.98, y: 0.95),
        bottomRight: CGPoint(x: 0.98, y: 0.5),
        bottomLeft: CGPoint(x: 0.5, y: 0.5)
    )

    private func jitter(_ q: Quad, by amount: CGFloat, seed: Int) -> Quad {
        var corners = q.corners
        for i in 0..<4 {
            let dx = CGFloat(((seed * 7 + i * 13) % 5) - 2) / 2 * amount
            let dy = CGFloat(((seed * 11 + i * 3) % 5) - 2) / 2 * amount
            corners[i] = CGPoint(x: corners[i].x + dx, y: corners[i].y + dy)
        }
        return Quad(topLeft: corners[0], topRight: corners[1], bottomRight: corners[2], bottomLeft: corners[3])
    }

    private func feed(
        _ tracker: inout StabilityTracker,
        quad: Quad?,
        from start: TimeInterval,
        to end: TimeInterval,
        fps: Double = 12
    ) -> StabilityTracker.Event? {
        var lastEvent: StabilityTracker.Event?
        var t = start
        while t <= end + 1e-9 {
            if let event = tracker.update(quad: quad, now: t) {
                lastEvent = event
            }
            t += 1 / fps
        }
        return lastEvent
    }

    func testFiresAfterStableDuration() {
        var tracker = StabilityTracker(stableDuration: 1.1, cornerTolerance: 0.03)
        let event = feed(&tracker, quad: pageA, from: 0, to: 1.5)
        guard case let .autoCapture(q) = event else {
            return XCTFail("expected autoCapture, got \(String(describing: event))")
        }
        XCTAssertTrue(q.isSimilar(to: pageA, tolerance: 0.05))
        XCTAssertEqual(tracker.phase, .captured)
    }

    func testJitterWithinToleranceDoesNotDelayFiring() {
        var tracker = StabilityTracker(stableDuration: 1.1, cornerTolerance: 0.03)
        var lastEvent: StabilityTracker.Event?
        var t: TimeInterval = 0
        var step = 0
        while t <= 1.5 {
            let quad = jitter(pageA, by: 0.01, seed: step)
            if let e = tracker.update(quad: quad, now: t) { lastEvent = e }
            t += 1 / 12
            step += 1
        }
        XCTAssertNotNil(lastEvent, "hand jitter within tolerance must not block auto-capture")
    }

    func testMovementResetsStabilityClock() {
        var tracker = StabilityTracker(stableDuration: 1.1, cornerTolerance: 0.03)
        // Hold 0.6 s, then the quad moves clearly, then hold 1.0 s more:
        // total elapsed 1.6 s but continuous hold only 1.0 s → no fire yet.
        XCTAssertNil(feed(&tracker, quad: pageA, from: 0, to: 0.6))
        tracker.update(quad: pageAFar, now: 0.7)
        XCTAssertNil(feed(&tracker, quad: pageAFar, from: 0.75, to: 1.75))
        XCTAssertEqual(tracker.phase, .tracking)
        // …but one more 0.4 s of stillness crosses the threshold.
        let event = feed(&tracker, quad: pageAFar, from: 1.8, to: 2.0)
        XCTAssertNotNil(event)
    }

    func testNoRefireWhileSceneStaysSame() {
        var tracker = StabilityTracker(stableDuration: 1.1, cornerTolerance: 0.03)
        XCTAssertNotNil(feed(&tracker, quad: pageA, from: 0, to: 1.5))
        // Same scene keeps reporting the same quad: exactly one shot.
        XCTAssertNil(feed(&tracker, quad: pageA, from: 1.6, to: 4.0))
        XCTAssertEqual(tracker.phase, .captured)
    }

    func testRearmAfterQuadLost() {
        var tracker = StabilityTracker(
            stableDuration: 1.1, cornerTolerance: 0.03,
            rearmChangeIoU: 0.55, rearmLostDuration: 0.35
        )
        XCTAssertNotNil(feed(&tracker, quad: pageA, from: 0, to: 1.5))

        // Page being turned: quad lost for 0.5 s.
        XCTAssertNil(feed(&tracker, quad: nil, from: 1.6, to: 2.1))
        XCTAssertEqual(tracker.phase, .searching)

        // New page settles → second shot.
        let second = feed(&tracker, quad: pageB, from: 2.2, to: 3.5)
        XCTAssertNotNil(second, "tracker must re-arm after the rectangle was lost")
    }

    func testRearmOnLargeChangeWithoutLoss() {
        var tracker = StabilityTracker(
            stableDuration: 1.1, cornerTolerance: 0.03,
            rearmChangeIoU: 0.55, rearmLostDuration: 0.35
        )
        XCTAssertNotNil(feed(&tracker, quad: pageA, from: 0, to: 1.5))

        // The user flips the page without the rectangle ever disappearing:
        // the frame is suddenly dominated by a different rectangle.
        tracker.update(quad: pageB, now: 1.6)
        XCTAssertEqual(tracker.phase, .tracking)

        let second = feed(&tracker, quad: pageB, from: 1.65, to: 3.0)
        XCTAssertNotNil(second, "clearly different rectangle must re-arm the tracker")
    }

    func testSmallChangeDoesNotRearmAfterCapture() {
        var tracker = StabilityTracker(
            stableDuration: 1.1, cornerTolerance: 0.03,
            rearmChangeIoU: 0.55, rearmLostDuration: 0.35
        )
        XCTAssertNotNil(feed(&tracker, quad: pageA, from: 0, to: 1.5))
        // Slight drift (IoU still high) must not count as a page turn.
        XCTAssertNil(feed(&tracker, quad: pageAFar, from: 1.6, to: 3.5))
        XCTAssertEqual(tracker.phase, .captured)
    }

    func testManualCaptureSuppressesImmediateAutoFire() {
        var tracker = StabilityTracker(stableDuration: 1.1, cornerTolerance: 0.03)
        tracker.update(quad: pageA, now: 0)
        tracker.markCaptured(quad: pageA, now: 0.2)
        XCTAssertNil(feed(&tracker, quad: pageA, from: 0.3, to: 2.0))
        XCTAssertEqual(tracker.phase, .captured)
    }

    func testTimeRemainingCountsDown() {
        var tracker = StabilityTracker(stableDuration: 1.0, cornerTolerance: 0.03)
        tracker.update(quad: pageA, now: 10)
        XCTAssertEqual(tracker.timeRemaining(now: 10), 1.0, accuracy: 1e-9)
        XCTAssertEqual(tracker.timeRemaining(now: 10.4), 0.6, accuracy: 1e-9)
        XCTAssertEqual(tracker.timeRemaining(now: 11.5), 0, accuracy: 1e-9)
    }
}
