//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import CoreML
import Foundation

/// Non-linear page dewarping on device: the UVDoc network (MIT, see
/// THIRD_PARTY_NOTICES.md) converted to Core ML predicts a sampling grid for
/// a page; the grid is applied in Float32 on the CPU.
///
/// Runs after perspective correction. Every failure (missing model, unexpected
/// tensor layout, prediction error) yields `nil`, and the caller keeps the
/// geometry-only page — dewarping is an enhancement, never a requirement.
final class UVDocDewarper: @unchecked Sendable {
    /// Network input size (width, height): the upstream demo resizes to 488 x 712.
    static let inputWidth = 488
    static let inputHeight = 712
    /// Compiled model name inside the app bundle (`UVDocGrid_fp16.mlpackage`).
    static let modelResourceName = "UVDocGrid_fp16"

    private let modelURL: URL?
    /// Guards the lazily loaded model; prediction is serialized as well.
    private let lock = NSLock()
    private var model: MLModel?
    private var loadAttempted = false
    /// Compute units of the currently loaded model. Switches to `.cpuOnly`
    /// once if the preferred units produce a degenerate grid.
    private(set) var computeUnits: MLComputeUnits

    /// Default compute units. The iOS Simulator has no MPSGraph engine: with
    /// `.all` / `.cpuAndGPU` Core ML silently returns an all-zero grid there
    /// ("MpsGraph backend validation on incompatible OS"), so the simulator
    /// runs on the CPU. Devices use every unit (ANE/GPU).
    static var defaultComputeUnits: MLComputeUnits {
        #if targetEnvironment(simulator)
        return .cpuOnly
        #else
        return .all
        #endif
    }

    /// - Parameters:
    ///   - modelURL: compiled `.mlmodelc` location. Defaults to the copy
    ///     bundled with the app; tests may pass another location.
    ///   - computeUnits: preferred compute units; an implausible grid triggers
    ///     one retry on `.cpuOnly`.
    init(
        modelURL: URL? = UVDocDewarper.bundledModelURL,
        computeUnits: MLComputeUnits = UVDocDewarper.defaultComputeUnits
    ) {
        self.modelURL = modelURL
        self.computeUnits = computeUnits
    }

    /// `UVDocGrid_fp16.mlmodelc` inside the bundle that contains this class.
    static var bundledModelURL: URL? {
        Bundle(for: UVDocDewarper.self).url(forResource: modelResourceName, withExtension: "mlmodelc")
    }

    /// Predicts the sampling grid for a page image (any size; resized to the
    /// network input internally). `nil` if the model is unavailable.
    /// The grid is plausibility-checked (`DewarpGrid.isPlausible`); a
    /// degenerate result is retried once on `.cpuOnly` and otherwise `nil`.
    func predictGrid(for page: CGImage) -> DewarpGrid? {
        lock.lock()
        defer { lock.unlock() }
        guard let input = Self.makeInputArray(from: page) else { return nil }
        guard let model = loadedModelLocked() else { return nil }

        if let grid = Self.predict(model, input: input), grid.isPlausible { return grid }
        guard computeUnits != .cpuOnly else { return nil }

        // The preferred backend produced garbage (or failed): switch to the
        // CPU for this and every later page.
        computeUnits = .cpuOnly
        self.model = nil
        loadAttempted = false
        guard let cpuModel = loadedModelLocked(),
              let grid = Self.predict(cpuModel, input: input),
              grid.isPlausible
        else { return nil }
        return grid
    }

    private static func predict(_ model: MLModel, input: MLMultiArray) -> DewarpGrid? {
        let provider = try? MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(multiArray: input),
        ])
        guard let provider,
              let output = try? model.prediction(from: provider),
              let grid2D = output.featureValue(for: "point_positions2D")?.multiArrayValue
        else { return nil }
        return readGrid(grid2D)
    }

    /// Full dewarp of a page. The result has the input's size; `nil` on any
    /// failure (caller falls back to the input).
    func dewarp(_ page: CGImage) -> CGImage? {
        guard let grid = predictGrid(for: page) else { return nil }
        let width = page.width, height = page.height
        guard width >= 2, height >= 2 else { return nil }

        guard let pixels = Self.rgbaPixels(of: page, width: width, height: height) else { return nil }
        let resampled = DewarpResampler.resample(pixels: pixels, width: width, height: height, grid: grid)

        guard let provider = CGDataProvider(data: Data(resampled) as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else { return nil }
        return image
    }

    // MARK: - Model

    /// Loads the model once. Must be called with `lock` held.
    private func loadedModelLocked() -> MLModel? {
        if let model { return model }
        if loadAttempted { return nil }
        loadAttempted = true
        guard let modelURL else { return nil }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        model = try? MLModel(contentsOf: modelURL, configuration: configuration)
        return model
    }

    // MARK: - Tensors

    /// `1 x 3 x 712 x 488` Float32 RGB in [0, 1], NCHW.
    private static func makeInputArray(from page: CGImage) -> MLMultiArray? {
        let w = inputWidth, h = inputHeight
        guard let rgbx = rgbxPixels(of: page, width: w, height: h, quality: .high) else { return nil }
        guard let array = try? MLMultiArray(
            shape: [1, 3, NSNumber(value: h), NSNumber(value: w)],
            dataType: .float32
        ) else { return nil }

        array.withUnsafeMutableBytes { buffer, strides in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: Float32.self) else { return }
            let planeStride = strides[1]
            let rowStride = strides[2]
            let colStride = strides[3]
            for y in 0..<h {
                for x in 0..<w {
                    let p = (y * w + x) * 4
                    for ch in 0..<3 {
                        let offset = ch * planeStride + y * rowStride + x * colStride
                        base[offset] = Float32(rgbx[p + ch]) / 255
                    }
                }
            }
        }
        return array
    }

    /// Reads the `1 x 2 x rows x cols` grid. Index 0 = source x, 1 = source y.
    private static func readGrid(_ array: MLMultiArray) -> DewarpGrid? {
        let shape = array.shape.map { $0.intValue }
        guard shape.count == 4, shape[0] == 1, shape[1] == 2 else { return nil }
        let rows = shape[2], cols = shape[3]
        guard rows >= 2, cols >= 2 else { return nil }

        var xs = [Float](repeating: 0, count: rows * cols)
        var ys = [Float](repeating: 0, count: rows * cols)
        for r in 0..<rows {
            for c in 0..<cols {
                let xIndex = [0, 0, r, c] as [NSNumber]
                let yIndex = [0, 1, r, c] as [NSNumber]
                xs[r * cols + c] = array[xIndex].floatValue
                ys[r * cols + c] = array[yIndex].floatValue
            }
        }
        guard xs.allSatisfy({ $0.isFinite }), ys.allSatisfy({ $0.isFinite }) else { return nil }
        return DewarpGrid(rows: rows, cols: cols, sourceX: xs, sourceY: ys)
    }

    // MARK: - Pixels

    /// RGBA8 (alpha = noneSkipLast, ignored) pixels of `image` drawn at `width x height`.
    private static func rgbxPixels(
        of image: CGImage,
        width: Int,
        height: Int,
        quality: CGInterpolationQuality = .high
    ) -> [UInt8]? {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = data.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.interpolationQuality = quality
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? data : nil
    }

    private static func rgbaPixels(of image: CGImage, width: Int, height: Int) -> [UInt8]? {
        rgbxPixels(of: image, width: width, height: height, quality: .none)
    }
}
