//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation
import CoreGraphics
import Foundation
import UIKit

/// Owns the `AVCaptureSession`: live rectangle detection on video frames,
/// stability-driven auto-capture, manual photo capture, torch control.
///
/// Concurrency contract (Swift 6, `@unchecked Sendable` is deliberate and
/// confined): all mutable state is touched *only* on `sessionQueue`; UI
/// callbacks hop to the main actor. The published `session` is configured
/// once before `startRunning` and is safe to attach to a preview layer.
final class CameraController: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    // Events surfaced to the view model (main actor).
    var onQuadUpdate: (@MainActor (Quad?) -> Void)?
    var onStability: (@MainActor (StabilityTracker.Phase, TimeInterval) -> Void)?
    var onAutoCapture: (@MainActor (Quad) -> Void)?
    var onPhoto: (@MainActor (CGImage?) -> Void)?
    var onPermissionDenied: (@MainActor () -> Void)?

    private let sessionQueue = DispatchQueue(label: "bookfold.camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let detector = DocumentDetector()
    private var tracker = StabilityTracker()
    private var isConfigured = false
    private var lastDetectionAt: TimeInterval = 0

    /// Detection throttle: ~12 analyses per second is plenty for a stability
    /// timer measured in seconds, and keeps the thermal budget low.
    private let detectionInterval: TimeInterval = 1.0 / 12.0

    static var isCameraAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    // MARK: - Lifecycle

    /// Requests camera access (first call shows the system prompt), then
    /// configures and starts the session. Safe to call repeatedly.
    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { [self] in
                self.configureAndStart()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [self] granted in
                if granted {
                    sessionQueue.async { self.configureAndStart() }
                } else {
                    Task { @MainActor in onPermissionDenied?() }
                }
            }
        default:
            Task { @MainActor in onPermissionDenied?() }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    // MARK: - Controls

    /// Manual capture: fires the shutter regardless of stability.
    func capturePhoto(quad: Quad?) {
        sessionQueue.async { [self] in
            if let quad {
                tracker.markCaptured(quad: quad, now: CACurrentMediaTime())
            }
            guard session.isRunning else { return }
            let settings: AVCapturePhotoSettings
            if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Auto-capture shot triggered by the stability tracker.
    private func captureAutoPhoto() {
        sessionQueue.async { [self] in
            guard session.isRunning else { return }
            let settings: AVCapturePhotoSettings
            if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Best-effort torch toggle; the UI keeps the authoritative on/off state.
    func setTorch(_ on: Bool) {
        sessionQueue.async { [self] in
            guard let device = session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first?.device
            else { return }
            do {
                try device.lockForConfiguration()
                if device.hasTorch, device.isTorchModeSupported(on ? .on : .off) {
                    device.torchMode = on ? .on : .off
                }
                device.unlockForConfiguration()
            } catch {
                // Torch is best-effort; ignore configuration races.
            }
        }
    }

    // MARK: - Configuration (sessionQueue only)

    private func configureAndStart() {
        if !isConfigured {
            configureSession()
            isConfigured = true
        }
        guard session.inputs.contains(where: { $0 is AVCaptureDeviceInput }) else { return }
        if !session.isRunning {
            session.startRunning()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }
        session.addInput(input)

        // Live detection frames.
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        guard session.canAddOutput(videoOutput) else { return }
        session.addOutput(videoOutput)

        // Full-resolution stills.
        guard session.canAddOutput(photoOutput) else { return }
        session.addOutput(photoOutput)

        // Deliver both streams upright in portrait, so normalized Vision
        // coordinates line up with what the preview shows.
        for connection in [videoOutput.connection(with: .video), photoOutput.connection(with: .video)] {
            if let connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }
}

// MARK: - Frame analysis (sessionQueue)

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let now = CACurrentMediaTime()
        guard now - lastDetectionAt >= detectionInterval else { return }
        lastDetectionAt = now

        let quad = detector.bestQuad(in: pixelBuffer)
        let event = tracker.update(quad: quad, now: now)

        let phase = tracker.phase
        let remaining = tracker.timeRemaining(now: now)

        Task { @MainActor in
            onQuadUpdate?(quad)
            onStability?(phase, remaining)
        }

        if case let .autoCapture(stableQuad) = event {
            Task { @MainActor in onAutoCapture?(stableQuad) }
            captureAutoPhoto()
        }
    }
}

// MARK: - Photo delivery

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        var image: CGImage?
        if error == nil, let data = photo.fileDataRepresentation() {
            image = UIImage(data: data)?.cgImage
        }
        Task { @MainActor in onPhoto?(image) }
    }
}
