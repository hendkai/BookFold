//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// The scanner: live camera with edge overlay and auto-capture, plus a photo
/// import path that keeps the whole pipeline testable in the Simulator
/// (where no camera exists).
struct ScanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = ScanViewModel()
    @State private var importedItem: PhotosPickerItem?
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch viewModel.cameraState {
                case .running:
                    cameraLayer
                case .needsPermission:
                    permissionView
                case .unavailable:
                    simulatorImportView
                }
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { saveAndDismiss() }
                        .foregroundStyle(.white)
                        .disabled(viewModel.pageCount == 0)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .alert("Could not save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Camera

    private var cameraLayer: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreviewView(session: viewModel.cameraSessionForPreview)
                EdgeOverlay(quad: viewModel.quad, phase: viewModel.phase)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) { statusBanner }
        .overlay(alignment: .bottom) { controls }
    }

    private var statusBanner: some View {
        VStack(spacing: 6) {
            Text(statusText)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            if let hint = viewModel.statusHint {
                Text(hint)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .padding(.top, 12)
        .animation(.easeInOut(duration: 0.15), value: viewModel.phase)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            if !viewModel.lastCaptureThumbnails.isEmpty {
                thumbnailStrip
            }

            Picker("Mode", selection: Binding(
                get: { viewModel.mode },
                set: { viewModel.mode = $0 }
            )) {
                Text("Page").tag(ScanMode.singlePage)
                Text("Spread").tag(ScanMode.spread)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            HStack(spacing: 36) {
                // Torch
                Button {
                    viewModel.toggleTorch()
                } label: {
                    Image(systemName: viewModel.torchOn ? "lightbulb.fill" : "lightbulb")
                        .font(.title3)
                        .foregroundStyle(viewModel.torchOn ? .yellow : .white)
                }
                .accessibilityLabel("Toggle torch")

                // Shutter
                Button {
                    viewModel.captureNow()
                } label: {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 74, height: 74)
                        Circle()
                            .fill(viewModel.isProcessing ? .gray : .white)
                            .frame(width: 60, height: 60)
                    }
                }
                .disabled(viewModel.isProcessing)
                .accessibilityLabel("Capture page")

                // Undo
                Button {
                    viewModel.undoLastPage()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                .disabled(viewModel.pageCount == 0)
                .accessibilityLabel("Undo last page")
            }

            HStack(spacing: 20) {
                PhotosPicker(selection: $importedItem, matching: .images) {
                    Label("Import photo", systemImage: "photo.on.rectangle")
                        .font(.footnote)
                }
                .foregroundStyle(.white)

                Button {
                    viewModel.toggleAutoCapture()
                } label: {
                    Label(
                        viewModel.autoCaptureEnabled ? "Auto: on" : "Auto: off",
                        systemImage: viewModel.autoCaptureEnabled ? "timer" : "timer.circle.dotted"
                    )
                    .font(.footnote)
                }
                .foregroundStyle(.white)

                Text("\(viewModel.pageCount) pages")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(.ultraThinMaterial)
        .onChange(of: importedItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    viewModel.importPhoto(data: data)
                }
                importedItem = nil
            }
        }
    }

    private var thumbnailStrip: some View {
        HStack(spacing: 8) {
            ForEach(0..<viewModel.lastCaptureThumbnails.count, id: \.self) { i in
                Image(uiImage: UIImage(cgImage: viewModel.lastCaptureThumbnails[i]))
                    .resizable()
                    .scaledToFit()
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.4)))
            }
        }
    }

    private var statusText: String {
        if viewModel.isProcessing { return "Processing…" }
        switch viewModel.phase {
        case .searching:
            return "Looking for a page…"
        case .tracking:
            let seconds = Int(viewModel.stableRemaining.rounded(.up))
            return seconds > 0 ? "Hold still — capturing in \(seconds)s" : "Hold still…"
        case .captured:
            return "Captured — turn the page"
        }
    }

    // MARK: - Fallbacks

    private var permissionView: some View {
        ContentUnavailableView {
            Label("Camera access denied", systemImage: "video.slash")
        } description: {
            Text("BookFold scans never leave your device. Enable camera access in Settings to scan books.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// Simulator-friendly path: the same pipeline, fed from the photo library.
    private var simulatorImportView: some View {
        VStack(spacing: 18) {
            ContentUnavailableView {
                Label("No camera on this device", systemImage: "camera.metering.unknown")
            } description: {
                Text("Import photos instead — they run through the exact same edge-detection and perspective pipeline as live capture.")
            }
            PhotosPicker(selection: $importedItem, matching: .images) {
                Label("Import a page photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.borderedProminent)

            Picker("Mode", selection: Binding(
                get: { viewModel.mode },
                set: { viewModel.mode = $0 }
            )) {
                Text("Page").tag(ScanMode.singlePage)
                Text("Spread").tag(ScanMode.spread)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            if let hint = viewModel.statusHint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }

            if !viewModel.lastCaptureThumbnails.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(0..<viewModel.lastCaptureThumbnails.count, id: \.self) { i in
                            Image(uiImage: UIImage(cgImage: viewModel.lastCaptureThumbnails[i]))
                                .resizable()
                                .scaledToFit()
                                .frame(height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(maxHeight: 100)

                Button("Undo last page") { viewModel.undoLastPage() }
            }

            Text("\(viewModel.pageCount) pages captured")
                .font(.headline.monospacedDigit())
        }
        .padding(24)
    }

    // MARK: - Saving

    private func saveAndDismiss() {
        do {
            _ = try viewModel.finish(modelContext: modelContext)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Edge overlay

/// Draws the detected page rectangle over the preview, tinted by stability
/// phase: yellow while tracking, green once the shot fired.
struct EdgeOverlay: View {
    let quad: Quad?
    let phase: StabilityTracker.Phase

    var body: some View {
        Canvas { context, size in
            guard let quad else { return }
            let points = quad.layerPoints(in: size)
            guard points.count == 4 else { return }

            var path = Path()
            path.move(to: points[0])
            path.addLine(to: points[1])
            path.addLine(to: points[2])
            path.addLine(to: points[3])
            path.closeSubpath()

            let color: Color = switch phase {
            case .searching: .orange
            case .tracking: .yellow
            case .captured: .green
            }

            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            for p in points {
                let dot = CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)
                context.fill(Path(ellipseIn: dot), with: .color(color))
            }
        }
        .animation(.easeInOut(duration: 0.12), value: quad)
    }
}

#Preview {
    ScanView()
        .modelContainer(for: [Book.self, Page.self], inMemory: true)
}
