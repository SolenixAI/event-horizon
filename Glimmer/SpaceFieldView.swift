//
//  SpaceFieldView.swift
//
//  The app's one space: the black hole world that onboarding flies through and
//  Home sits in. Runs the ray tracer (SpaceField.metal) in its own Metal view,
//  off SwiftUI's render path: MTKView's display link drives it at the display's
//  rate, at full resolution. Each frame: a compute pass traces the photon paths
//  once into the lensing map; every pixel reads its path from it into an HDR
//  image; that image blooms at two scales, like light in a real lens; and a
//  compose pass tone maps it to the screen. (Tracing per pixel cost about 14 ms a frame at half resolution; a MetalFX
//  upscale added 7 ms more.) GPU time per frame goes to the log, so smoothness
//  is measured, not guessed.
//

import MetalKit
import MetalPerformanceShaders
import os
import SwiftUI

/// One frame's uniforms, laid out to match `FieldUniforms` in SpaceField.metal.
struct FieldUniforms {
    var cameraPosition: SIMD3<Float>
    var forward: SIMD3<Float>
    var right: SIMD3<Float>
    var up: SIMD3<Float>
    var size: SIMD2<Float>
    var principal: SIMD2<Float>
    var time: Float
    var focal: Float
    var light: Float
    var pixelsPerPoint: Float

    init(camera: StageCamera, size: CGSize, time: Double, light: Double) {
        func vector(_ value: SIMD3<Double>) -> SIMD3<Float> { SIMD3(Float(value.x), Float(value.y), Float(value.z)) }
        cameraPosition = vector(camera.position)
        forward = vector(camera.forward)
        right = vector(camera.right)
        up = vector(camera.up)
        self.size = SIMD2(Float(size.width), Float(size.height))
        principal = SIMD2(Float(camera.principal.x), Float(camera.principal.y))
        self.time = Float(time)
        focal = Float(camera.focal)
        self.light = Float(light)
        pixelsPerPoint = 1
    }
}

struct SpaceFieldView: NSViewRepresentable {
    /// Under Reduce Motion the field draws once per change instead of every frame.
    let paused: Bool
    /// Onboarding flies at the display's rate; Home's slow drift needs far fewer frames.
    var framesPerSecond = 120
    /// The uniforms for a moment, in a window of this size in points.
    let uniforms: (Date, CGSize) -> FieldUniforms

    func makeCoordinator() -> FieldRenderer? { FieldRenderer() }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        guard let renderer = context.coordinator else { return view }
        view.device = renderer.device
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = framesPerSecond
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.delegate = renderer
        configure(view, renderer)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        guard let renderer = context.coordinator else { return }
        configure(view, renderer)
        if paused { view.needsDisplay = true }
    }

    private func configure(_ view: MTKView, _ renderer: FieldRenderer) {
        renderer.uniforms = uniforms
        view.isPaused = paused
        view.enableSetNeedsDisplay = paused
    }
}

/// Owns the GPU work: the lensing pass, the field pass, and the frame timing.
final class FieldRenderer: NSObject, MTKViewDelegate {
    /// Matches lensRows and lensColumns in SpaceField.metal.
    static let lensRows = 2048
    static let lensColumns = 1024

    let device: MTLDevice
    var uniforms: ((Date, CGSize) -> FieldUniforms)?
    private let queue: MTLCommandQueue
    private let lensing: MTLComputePipelineState
    private let pipeline: MTLRenderPipelineState
    private let compose: MTLRenderPipelineState
    /// The HDR field and its two blurred copies, sized to the drawable.
    private var hdr: MTLTexture?
    private var nearDown: MTLTexture?
    private var near: MTLTexture?
    private var wideDown: MTLTexture?
    private var wide: MTLTexture?
    private let downscale: MPSImageBilinearScale
    private let blur: MPSImageGaussianBlur
    private let radii: MTLTexture
    private let ends: MTLTexture
    /// Baked once: the nebulae as a cube map, and the disk's turbulence.
    private let sky: MTLTexture
    private let pattern: MTLTexture
    private let timing = FrameTiming()

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let trace = library.makeFunction(name: "traceLensing"),
              let lensing = try? device.makeComputePipelineState(function: trace) else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "fieldVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "fieldFragment")
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        let composing = MTLRenderPipelineDescriptor()
        composing.vertexFunction = library.makeFunction(name: "fieldVertex")
        composing.fragmentFunction = library.makeFunction(name: "composeFragment")
        composing.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
              let compose = try? device.makeRenderPipelineState(descriptor: composing),
              let radii = Self.texture(device, .r32Float, Self.lensColumns, Self.lensRows),
              let ends = Self.texture(device, .rgba32Float, Self.lensRows, 1),
              let sky = Self.cube(device, size: 512),
              let pattern = Self.texture(device, .rg16Float, 2048, 1024, mipmapped: true),
              Self.bake(device, queue, library, sky: sky, pattern: pattern) else { return nil }
        self.device = device
        self.queue = queue
        self.lensing = lensing
        self.pipeline = pipeline
        self.compose = compose
        downscale = MPSImageBilinearScale(device: device)
        blur = MPSImageGaussianBlur(device: device, sigma: 7)
        self.radii = radii
        self.ends = ends
        self.sky = sky
        self.pattern = pattern
    }

    private static func cube(_ device: MTLDevice, size: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .rgba16Float, size: size, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    /// Runs the two bake kernels once and waits; it takes a few milliseconds.
    private static func bake(_ device: MTLDevice, _ queue: MTLCommandQueue, _ library: MTLLibrary,
                             sky: MTLTexture, pattern: MTLTexture) -> Bool {
        guard let skyKernel = library.makeFunction(name: "bakeSky"),
              let diskKernel = library.makeFunction(name: "bakeDisk"),
              let skyState = try? device.makeComputePipelineState(function: skyKernel),
              let diskState = try? device.makeComputePipelineState(function: diskKernel),
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeComputeCommandEncoder() else { return false }
        let group = MTLSize(width: 8, height: 8, depth: 1)
        encoder.setComputePipelineState(skyState)
        encoder.setTexture(sky, index: 0)
        encoder.dispatchThreads(MTLSize(width: sky.width, height: sky.height, depth: 6), threadsPerThreadgroup: group)
        encoder.setComputePipelineState(diskState)
        encoder.setTexture(pattern, index: 0)
        encoder.dispatchThreads(MTLSize(width: pattern.width, height: pattern.height, depth: 1), threadsPerThreadgroup: group)
        encoder.endEncoding()
        // Mipmaps keep the disk's finest wisps from shimmering where they shrink below a pixel.
        guard let mips = buffer.makeBlitCommandEncoder() else { return false }
        mips.generateMipmaps(for: pattern)
        mips.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        return buffer.status == .completed
    }

    private static func texture(_ device: MTLDevice, _ format: MTLPixelFormat, _ width: Int, _ height: Int,
                                mipmapped: Bool = false, target: Bool = false) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width,
                                                                  height: height, mipmapped: mipmapped)
        descriptor.usage = target ? [.shaderRead, .shaderWrite, .renderTarget] : [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let points = view.bounds.size
        guard points.width > 0, points.height > 0, let uniforms,
              let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let buffer = queue.makeCommandBuffer() else { return }
        let width = drawable.texture.width
        let height = drawable.texture.height
        if hdr?.width != width || hdr?.height != height { resize(width: width, height: height) }
        guard let hdr, let nearDown, let near, let wideDown, let wide else { return }
        var frame = uniforms(.now, points)
        frame.pixelsPerPoint = Float(Double(width) / points.width)

        guard let compute = buffer.makeComputeCommandEncoder() else { return }
        compute.setComputePipelineState(lensing)
        compute.setTexture(radii, index: 0)
        compute.setTexture(ends, index: 1)
        compute.setBytes(&frame, length: MemoryLayout<FieldUniforms>.stride, index: 0)
        compute.dispatchThreads(MTLSize(width: Self.lensRows, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
        compute.endEncoding()

        let fieldPass = MTLRenderPassDescriptor()
        fieldPass.colorAttachments[0].texture = hdr
        fieldPass.colorAttachments[0].loadAction = .dontCare
        fieldPass.colorAttachments[0].storeAction = .store
        guard let field = buffer.makeRenderCommandEncoder(descriptor: fieldPass) else { return }
        field.setRenderPipelineState(pipeline)
        field.setFragmentBytes(&frame, length: MemoryLayout<FieldUniforms>.stride, index: 0)
        field.setFragmentTexture(radii, index: 0)
        field.setFragmentTexture(ends, index: 1)
        field.setFragmentTexture(sky, index: 2)
        field.setFragmentTexture(pattern, index: 3)
        field.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        field.endEncoding()

        // Bloom: a quarter-size blur for the glow, a sixteenth-size one for the haze.
        downscale.encode(commandBuffer: buffer, sourceTexture: hdr, destinationTexture: nearDown)
        blur.encode(commandBuffer: buffer, sourceTexture: nearDown, destinationTexture: near)
        downscale.encode(commandBuffer: buffer, sourceTexture: near, destinationTexture: wideDown)
        blur.encode(commandBuffer: buffer, sourceTexture: wideDown, destinationTexture: wide)

        pass.colorAttachments[0].loadAction = .dontCare
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(compose)
        encoder.setFragmentBytes(&frame, length: MemoryLayout<FieldUniforms>.stride, index: 0)
        encoder.setFragmentTexture(hdr, index: 0)
        encoder.setFragmentTexture(near, index: 1)
        encoder.setFragmentTexture(wide, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        let timing = timing
        buffer.addCompletedHandler { done in timing.record(gpuSeconds: done.gpuEndTime - done.gpuStartTime) }
        buffer.present(drawable)
        buffer.commit()
    }

    /// Fits the HDR image and the bloom chain to the drawable.
    private func resize(width: Int, height: Int) {
        hdr = Self.texture(device, .rgba16Float, width, height, target: true)
        nearDown = Self.texture(device, .rgba16Float, max(width / 4, 1), max(height / 4, 1))
        near = Self.texture(device, .rgba16Float, max(width / 4, 1), max(height / 4, 1))
        wideDown = Self.texture(device, .rgba16Float, max(width / 16, 1), max(height / 16, 1))
        wide = Self.texture(device, .rgba16Float, max(width / 16, 1), max(height / 16, 1))
    }
}

/// GPU time per frame, logged every few seconds so smoothness has a number.
final class FrameTiming: @unchecked Sendable {
    private let lock = NSLock()
    private var frames = 0
    private var total = 0.0
    private var worst = 0.0
    private var since = Date.now
    private let log = Logger(subsystem: "dev.solenix.eventhorizon", category: "space-field")

    func record(gpuSeconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        frames += 1
        total += gpuSeconds
        worst = max(worst, gpuSeconds)
        let elapsed = Date.now.timeIntervalSince(since)
        guard elapsed >= 3 else { return }
        let fps = Double(frames) / elapsed
        let average = total / Double(frames) * 1000
        let peak = worst * 1000
        log.info("""
            field fps \(fps, format: .fixed(precision: 1), privacy: .public) \
            gpu avg \(average, format: .fixed(precision: 2), privacy: .public) ms \
            max \(peak, format: .fixed(precision: 2), privacy: .public) ms
            """)
        frames = 0
        total = 0
        worst = 0
        since = .now
    }
}

/// Home's sky at night: the world from where onboarding's dive comes out, the
/// hole a small ember in the margin. It drifts slowly at 30 frames a second,
/// holds still when the live flow is frozen, and freezes its clock under Reduce Motion.
struct HomeSpaceField: View {
    let flow: SpaceFlow
    @State private var appeared = Date.now

    var body: some View {
        SpaceFieldView(paused: flow != .running, framesPerSecond: 30) { now, size in
            let still = flow == .hidden
            let elapsed = now.timeIntervalSince(appeared)
            let drift = OnboardingMotion.drift(elapsed: elapsed, reduceMotion: still)
            var pose = CameraPose.home
            pose.azimuth += drift.azimuth
            pose.elevation += drift.elevation
            return FieldUniforms(camera: StageCamera(pose: pose, size: size), size: size,
                                 time: OnboardingMotion.shaderTime(elapsed: elapsed, reduceMotion: still), light: 0.7)
        }
    }
}
