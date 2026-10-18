//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation
import CoreGraphics
import Foundation
import Observation
import SwiftData
import UIKit

/// Glues camera, pipeline and session together and drives the scan UI.
@MainActor
@Observable
final class ScanViewModel {
    enum CameraState: Equatable {
        case running
        case needsPermission
        case unavailable
    }

    // UI state
    private(set) var cameraState: CameraState = .running
    private(set) var quad: Quad?
    private(set) var phase: StabilityTracker.Phase = .searching
    private(set) var stableRemaining: TimeInterval = 0
    private(set) var lastCaptureThumbnails: [CGImage] = []
    private(set) var pageCount: Int = 0
    private(set) var torchOn = false
    private(set) var statusHint: String?
    private(set) var isProcessing = false

    var mode: ScanMode = .spread {
        didSet { if oldValue != mode { statusHint = nil } }
    }

    let session = ScanSession()

    private let camera = CameraController()
    private let pipeline = ScanPipeline(dewarper: UVDocDewarper())
    private let stillDetector = DocumentDetector()

    /// Quad (normalized, upright-portrait space) that belongs to the photo
    /// currently in flight — set by auto-capture, reused when the photo lands.
    private var pendingQuad: Quad?

    private(set) var autoCaptureEnabled = true

    /// The capture session, for the preview layer.
    var cameraSessionForPreview: AVCaptureSession { camera.session }

    // MARK: - Lifecycle

    func start() {
        if CameraController.isCameraAvailable {
            wireCamera()
            camera.start()
        } else {
            cameraState = .unavailable
        }
    }

    func stop() {
        camera.stop()
    }

    private func wireCamera() {
        camera.onQuadUpdate = { [weak self] q in self?.quad = q }
        camera.onStability = { [weak self] phase, remaining in
            self?.phase = phase
            self?.stableRemaining = remaining
        }
        camera.onPermissionDenied = { [weak self] in
            self?.cameraState = .needsPermission
        }
        camera.onAutoCapture = { [weak self] stableQuad in
            guard let self, self.autoCaptureEnabled else { return }
            self.pendingQuad = stableQuad
            self.isProcessing = true
        }
        camera.onPhoto = { [weak self] image in
            guard let self, let image else {
                self?.isProcessing = false
                return
            }
            // Pair the full-res photo with the quad that triggered it.
            let quad = self.pendingQuad ?? self.quad ?? .fullFrame
            self.pendingQuad = nil
            self.process(image: image, quad: quad)
        }
    }

    // MARK: - Actions

    func toggleAutoCapture() {
        autoCaptureEnabled.toggle()
    }

    func toggleTorch() {
        torchOn.toggle()
        camera.setTorch(torchOn)
    }

    /// Manual shutter.
    func captureNow() {
        guard !isProcessing else { return }
        isProcessing = true
        pendingQuad = quad
        camera.capturePhoto(quad: quad)
    }

    func undoLastPage() {
        if session.removeLast() != nil {
            pageCount = session.pages.count
            lastCaptureThumbnails = session.pages.suffix(3).map(\.image)
        }
    }

    /// Finish the session: persist as a new book. Returns the saved book.
    func finish(modelContext: ModelContext) throws -> Book? {
        guard !session.isEmpty else { return nil }
        return try session.save(modelContext: modelContext)
    }

    // MARK: - Photo import (Simulator / photos without camera)

    func importPhoto(data: Data) {
        guard !isProcessing, let oriented = UIImage.orientedImage(from: data)?.cgImage else {
            statusHint = "Could not read that image."
            return
        }
        isProcessing = true
        statusHint = nil

        let quad = stillDetector.bestQuad(in: oriented)
        if quad == nil { statusHint = "No page edges found — used the whole frame." }

        // Vision work is synchronous; keep it off the main thread.
        let pipeline = self.pipeline
        let mode = self.mode
        let useQuad = quad ?? .fullFrame
        Task.detached(priority: .userInitiated) { [weak self] in
            let pages = pipeline.processPages(source: oriented, quad: useQuad, mode: mode)
            await MainActor.run { [weak self] in
                self?.register(pages: pages)
            }
        }
    }

    // MARK: - Processing

    private func process(image: CGImage, quad: Quad) {
        let pipeline = self.pipeline
        let mode = self.mode
        Task.detached(priority: .userInitiated) { [weak self] in
            let pages = pipeline.processPages(source: image, quad: quad, mode: mode)
            await MainActor.run { [weak self] in
                self?.register(pages: pages)
            }
        }
    }

    private func register(pages: [CGImage]) {
        isProcessing = false
        guard !pages.isEmpty else {
            statusHint = "Capture failed — try again."
            return
        }
        session.add(pages)
        pageCount = session.pages.count
        lastCaptureThumbnails = session.pages.suffix(3).map(\.image)
    }
}

private extension UIImage {
    /// Decodes JPEG/HEIC data and bakes the EXIF orientation in, so downstream
    /// geometry works on an upright, `.up`-oriented bitmap.
    static func orientedImage(from data: Data) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
