//
//  SpaceBackdrop.swift
//
//  Home's surroundings: a deep-space field behind the PC on the desk. It is a
//  Core Animation layer tree, so the render server does the work: the sky, the
//  stars, the horizon light and the grain are static layers rasterised at the
//  window's backing scale. Over them, the live connection flows as faint blue
//  particles on an undrawn round trip between the Mac's horizon and the PC's
//  bezel. Density follows the bitrate; the pulse's round trip follows the
//  latency. Those numbers are sampled once a second, and the animation takes
//  them only when they change. No frame runs on the main thread.
//
//  The live flow is a live mark: the logo's blue at full strength, as the chip
//  and the Running label show it. Only the horizon light is atmosphere, kept
//  under the horizon bar. Gold is for what you press and blue is for what is
//  live on the PC. Dark is deep space. Light is the same composition at dawn.
//
//  The flow freezes while the window is not key and while the stream fills the
//  window, and it is hidden under Reduce Motion. The flow stays beside the PC,
//  in the margin left of the bezel, so it never crosses the status row, the chip
//  or the shelf. VoiceOver ignores the backdrop.
//

import AppKit
import QuartzCore
import SwiftUI

/// A colour as sRGB with its opacity: the palette's one currency, so the
/// signal and atmosphere values can be compared as numbers.
struct SpaceRGB: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    init(_ red: Double, _ green: Double, _ blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(opacity))
    }

    func faded(_ factor: Double) -> SpaceRGB { SpaceRGB(red, green, blue, opacity: opacity * factor) }
}

/// One appearance's backdrop colours. The horizon and live colours already carry
/// their low opacity: they are atmosphere, kept well under any signal.
struct SpacePalette: Equatable {
    let skyTop: SpaceRGB
    let skyBottom: SpaceRGB
    let horizonGold: SpaceRGB
    let horizonBlue: SpaceRGB
    /// The live flow's particles and pulse: the logo's blue at atmosphere strength.
    let live: SpaceRGB
    /// Night only: the field's stars. Dawn has none.
    let stars: SpaceRGB?

    /// Deep space: near-black, the logo's gold and blue low on the horizon.
    static let night = SpacePalette(
        skyTop: SpaceRGB(0.012, 0.016, 0.039),
        skyBottom: SpaceRGB(0.043, 0.055, 0.098),
        horizonGold: SpaceRGB(0.941, 0.541, 0.141, opacity: 0.16),
        horizonBlue: SpaceRGB(0.227, 0.627, 1.0, opacity: 0.12),
        live: SpaceRGB(0.227, 0.627, 1.0),
        stars: SpaceRGB(1, 1, 1, opacity: 0.5))

    /// Dawn: the same composition, a pale sky and a soft gold horizon.
    static let dawn = SpacePalette(
        skyTop: SpaceRGB(0.894, 0.925, 0.969),
        skyBottom: SpaceRGB(0.965, 0.945, 0.910),
        horizonGold: SpaceRGB(0.788, 0.439, 0.059, opacity: 0.20),
        horizonBlue: SpaceRGB(0.227, 0.627, 1.0, opacity: 0.09),
        live: SpaceRGB(0.227, 0.627, 1.0),
        stars: nil)
}

struct SpaceBackdrop: View {
    /// How the live flow runs: hidden, frozen or running (see SpaceFlow).
    var flow: SpaceFlow = .running
    /// The PC's bezel on Home, in this view's space. The flow is anchored to it:
    /// nothing is drawn until Home has laid the bezel out.
    var bezel: CGRect?
    /// Reads the live numbers on the main actor. Called once a second while the
    /// flow runs.
    var sample: @MainActor () async -> LiveFlowReading = { LiveFlowReading.none }
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let night = colorScheme == .dark
        ZStack {
            // At night Home sits in the same ray-traced space onboarding flies through.
            if night { HomeSpaceField(flow: flow) }
            SpaceLayers(palette: night ? .night : .dawn, skyShown: !night, bezel: bezel, flow: flow, sample: sample)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

// MARK: - Bridge

/// The Core Animation view, placed in SwiftUI.
private struct SpaceLayers: NSViewRepresentable {
    let palette: SpacePalette
    /// The static sky, stars and horizon light; off when the ray-traced field is behind.
    let skyShown: Bool
    let bezel: CGRect?
    let flow: SpaceFlow
    let sample: @MainActor () async -> LiveFlowReading

    func makeNSView(context: Context) -> SpaceLayerView { SpaceLayerView() }

    func updateNSView(_ view: SpaceLayerView, context: Context) {
        view.configure(palette: palette, skyShown: skyShown, bezel: bezel, flow: flow, sample: sample)
    }
}

// MARK: - Layer tree

/// The backdrop's layers. Everything but the live flow is static. The flow is
/// a container whose clock freezes with its state, holding one pulse and a fixed
/// set of particle slots, each with its own phase on the round trip.
final class SpaceLayerView: NSView {
    /// One particle's round trip, out and back. Slow, so the flow reads as data.
    static let particleLapSeconds: Double = 18
    /// The pulse animation's own cycle. Its speed sets the round trip.
    static let pulseCycleSeconds: Double = LiveFlowMapping.stretchedLapSeconds
    static let particleSide: CGFloat = SpaceFlowPath.dotRadius * 2
    static let pulseSide: CGFloat = SpaceFlowPath.dotRadius * 1.5
    /// How long a particle takes to fade in or out when the density changes.
    static let fadeSeconds: Double = 0.6
    private static let flowKey = "flow"
    private static let pulseKey = "pulse"

    private let field = CAGradientLayer()
    private let stars = CALayer()
    private let horizonGold = CAGradientLayer()
    private let horizonBlue = CAGradientLayer()
    private let grain = CALayer()
    private let flowLayer = CALayer()
    private let pulse = CALayer()
    private let particles: [CALayer] = (0..<LiveFlowMapping.slotCount).map { _ in CALayer() }

    private var palette: SpacePalette = .dawn
    private var bezel: CGRect?
    /// Starts hidden: nothing moves until the first configure says how.
    private var flow: SpaceFlow = .hidden
    private var sample: (@MainActor () async -> LiveFlowReading)?
    private var lastKey: BuildKey?
    private var ticker: Timer?
    private var sampling = false
    private var smoothedRtt: Double?
    private var smoothedMbps: Double?
    /// The round trip the pulse is timed to, and how many particle slots show.
    private var appliedLap: Double?
    private var appliedSlots = 0
    private var particlesAnimating = false
    private var pulseAnimating = false
    private var flowPath: CGPath?

    private struct BuildKey: Equatable {
        let size: CGSize
        let scale: CGFloat
        let palette: SpacePalette
        let bezel: CGRect?
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        guard let root = layer else { return }
        root.masksToBounds = true
        for sub in [field, stars, horizonGold, horizonBlue, grain, flowLayer] {
            root.addSublayer(sub)
        }
        field.type = .axial
        horizonGold.type = .radial
        horizonBlue.type = .radial
        flowLayer.isHidden = true
        for particle in particles { flowLayer.addSublayer(particle) }
        flowLayer.addSublayer(pulse)
        zeroFlowDots()
    }

    /// Every dot at zero opacity and off: a dot with no animation sits at the
    /// layer's origin, so none may show until the numbers call for it.
    private func zeroFlowDots() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for particle in particles { particle.opacity = 0 }
        pulse.isHidden = true
        CATransaction.commit()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        rebuild()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        rebuild()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        rebuild()
    }

    func configure(palette: SpacePalette, skyShown: Bool = true, bezel: CGRect?, flow: SpaceFlow,
                   sample: @escaping @MainActor () async -> LiveFlowReading) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for sky in [field, stars, horizonGold, horizonBlue, grain] { sky.isHidden = !skyShown }
        CATransaction.commit()
        self.palette = palette
        self.bezel = bezel
        self.sample = sample
        rebuild()
        setFlow(flow)
    }

    // MARK: Build

    /// Lays out and paints the static layers, and places the live flow when the
    /// PC's bezel is known. Runs only when something it depends on changes,
    /// never per frame.
    private func rebuild() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = window?.backingScaleFactor ?? 2
        let key = BuildKey(size: size, scale: scale, palette: palette, bezel: bezel)
        guard key != lastKey else { return }
        lastKey = key

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let whole = CGRect(origin: .zero, size: size)
        for layer in [field, stars, horizonGold, horizonBlue, grain, flowLayer] {
            layer.frame = whole
            layer.contentsScale = scale
        }

        // Sky: bottom to top, in the layer's unflipped space.
        field.colors = [palette.skyBottom.cgColor, palette.skyTop.cgColor]
        field.startPoint = CGPoint(x: 0.5, y: 0)
        field.endPoint = CGPoint(x: 0.5, y: 1)

        // Stars, painted at the backing scale so each one is crisp.
        stars.contents = SpaceImages.starfield(palette: palette, size: size, scale: scale)

        // Horizon light: elliptical radial glows standing on the bottom edge.
        placeHorizon(horizonGold, color: palette.horizonGold, x: size.width * 0.40,
                     radius: size.width * 0.62, squash: 0.30, size: size)
        placeHorizon(horizonBlue, color: palette.horizonBlue, x: size.width * 0.66,
                     radius: size.width * 0.55, squash: 0.30, size: size)

        // Grain: a fine dither that breaks up gradient banding.
        grain.backgroundColor = SpaceImages.grainColor(scale: scale)

        placeFlow(size: size, scale: scale)
        CATransaction.commit()
    }

    private func placeHorizon(_ layer: CAGradientLayer, color: SpaceRGB, x: CGFloat,
                              radius: CGFloat, squash: CGFloat, size: CGSize) {
        layer.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2 * squash)
        layer.position = CGPoint(x: x, y: 0)
        layer.colors = [color.cgColor, color.faded(0.45).cgColor, color.faded(0).cgColor]
        layer.locations = [0, 0.4, 1]
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 1)
    }

    /// The round trip's path and the particle and pulse images. The animations
    /// are re-timed on the new path, keeping each one's state.
    private func placeFlow(size: CGSize, scale: CGFloat) {
        guard let bezel else {
            flowPath = nil
            removeParticleAnimations()
            stopPulse()
            zeroFlowDots()
            return
        }
        flowPath = SpaceFlowPath.path(size: size, bezel: bezel)
        let particleImage = SpaceImages.flowDot(palette: palette, scale: scale, side: Self.particleSide, crisp: false)
        let pulseImage = SpaceImages.flowDot(palette: palette, scale: scale, side: Self.pulseSide, crisp: true)
        for particle in particles {
            particle.bounds = CGRect(x: 0, y: 0, width: Self.particleSide, height: Self.particleSide)
            particle.contentsScale = scale
            particle.contents = particleImage
        }
        pulse.bounds = CGRect(x: 0, y: 0, width: Self.pulseSide, height: Self.pulseSide)
        pulse.contentsScale = scale
        pulse.contents = pulseImage

        removeParticleAnimations()
        stopPulse()
        restoreAnimations()
    }

    // MARK: Flow state

    /// Moves the flow between hidden, frozen and running. Its clock freezes and
    /// resumes without a jump, and sampling runs only while the flow runs.
    private func setFlow(_ state: SpaceFlow) {
        guard state != flow else { return }
        let previous = flow
        flow = state
        switch state {
        case .hidden:
            stopTicker()
            removeParticleAnimations()
            stopPulse()
            zeroFlowDots()
            flowLayer.isHidden = true
        case .paused:
            if previous == .hidden {
                flowLayer.isHidden = false
                restoreAnimations()
            }
            stopTicker()
            freezeFlow()
        case .running:
            if previous == .hidden {
                flowLayer.isHidden = false
                restoreAnimations()
            }
            thawFlow()
            startTicker()
        }
    }

    /// Pauses the flow's clock where it stands.
    private func freezeFlow() {
        let now = flowLayer.convertTime(CACurrentMediaTime(), from: nil)
        flowLayer.speed = 0
        flowLayer.timeOffset = now
    }

    /// Resumes the flow's clock from the point where it froze.
    private func thawFlow() {
        let pausedAt = flowLayer.timeOffset
        flowLayer.speed = 1
        flowLayer.timeOffset = 0
        flowLayer.beginTime = 0
        let sincePause = flowLayer.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
        flowLayer.beginTime = sincePause
    }

    /// Puts back the animations that the current numbers call for.
    private func restoreAnimations() {
        guard flow != .hidden, let flowPath else { return }
        if appliedSlots > 0, !particlesAnimating { startParticles(flowPath) }
        if let lap = appliedLap {
            if !pulseAnimating { startPulse(flowPath) }
            retimePulse(lap)
        }
    }

    // MARK: Sampling

    private func startTicker() {
        guard ticker == nil else { return }
        sampleNow()
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleNow() }
        }
        timer.tolerance = 0.2
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    /// Reads the live numbers once; a read still in flight is not doubled.
    private func sampleNow() {
        guard !sampling, let sample else { return }
        sampling = true
        Task { @MainActor [weak self] in
            let reading = await sample()
            guard let self else { return }
            self.sampling = false
            self.apply(reading)
        }
    }

    /// Smooths the numbers and sets the pulse and the density from them.
    private func apply(_ reading: LiveFlowReading) {
        guard flow == .running else { return }
        smoothedRtt = LiveFlowMapping.smooth(smoothedRtt, reading.rttMs)
        smoothedMbps = LiveFlowMapping.smooth(smoothedMbps, reading.bitrateMbps)
        setPulse(LiveFlowMapping.pulseLapSeconds(rttMs: smoothedRtt))
        setSlots(LiveFlowMapping.activeSlots(bitrateMbps: smoothedMbps))
    }

    // MARK: Pulse

    /// Times the pulse to a round trip. Still without a latency.
    private func setPulse(_ lap: Double?) {
        guard let lap else {
            appliedLap = nil
            stopPulse()
            return
        }
        if let applied = appliedLap, abs(lap - applied) <= applied * LiveFlowMapping.retimeTolerance { return }
        appliedLap = lap
        guard let flowPath, flow != .hidden else { return }
        if !pulseAnimating { startPulse(flowPath) }
        retimePulse(lap)
    }

    private func startPulse(_ path: CGPath) {
        let animation = CAKeyframeAnimation(keyPath: "position")
        animation.path = path
        animation.calculationMode = .paced
        animation.duration = Self.pulseCycleSeconds
        animation.repeatCount = .infinity
        pulse.add(animation, forKey: Self.pulseKey)
        pulse.isHidden = false
        pulseAnimating = true
    }

    /// Sets the pulse's speed so one cycle takes `lap` seconds, keeping the
    /// pulse where it is: no jump when the latency changes.
    private func retimePulse(_ lap: Double) {
        let parentNow = flowLayer.convertTime(CACurrentMediaTime(), from: nil)
        let local = pulse.convertTime(CACurrentMediaTime(), from: nil)
        pulse.speed = Float(Self.pulseCycleSeconds / lap)
        pulse.timeOffset = local
        pulse.beginTime = parentNow
    }

    /// Removes the pulse's animation and hides it: nothing moves while still.
    private func stopPulse() {
        pulse.removeAnimation(forKey: Self.pulseKey)
        pulse.isHidden = true
        pulseAnimating = false
    }

    // MARK: Particles

    /// Shows `count` of the particle slots. Each slot keeps its phase, so
    /// showing or hiding one never moves the others.
    private func setSlots(_ count: Int) {
        let count = min(max(count, 0), LiveFlowMapping.slotCount)
        guard count != appliedSlots else { return }
        appliedSlots = count
        if count > 0, !particlesAnimating, let flowPath, flow != .hidden {
            startParticles(flowPath)
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.fadeSeconds)
        if count == 0 {
            // Once the last particle has faded, its animations go too: still means no work.
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, self.appliedSlots == 0 else { return }
                self.removeParticleAnimations()
            }
        }
        for (slot, particle) in particles.enumerated() {
            particle.opacity = slot < count ? 1 : 0
        }
        CATransaction.commit()
    }

    /// Starts every slot on the round trip, each at its own phase.
    private func startParticles(_ path: CGPath) {
        for (slot, particle) in particles.enumerated() {
            let animation = CAKeyframeAnimation(keyPath: "position")
            animation.path = path
            animation.calculationMode = .paced
            animation.duration = Self.particleLapSeconds
            animation.repeatCount = .infinity
            animation.timeOffset = Self.particleLapSeconds * LiveFlowMapping.slotPhase(slot)
            particle.add(animation, forKey: Self.flowKey)
        }
        particlesAnimating = true
    }

    private func removeParticleAnimations() {
        for particle in particles { particle.removeAnimation(forKey: Self.flowKey) }
        particlesAnimating = false
    }
}

// MARK: - Painted images

/// The images the layers hold, painted once per size, scale and palette.
private enum SpaceImages {

    /// A fixed scatter of stars: a few bright ones with a soft halo, a middle
    /// tier, and many faint ones, which reads as depth rather than noise.
    static func starfield(palette: SpacePalette, size: CGSize, scale: CGFloat) -> CGImage? {
        guard let star = palette.stars,
              let context = bitmap(width: size.width, height: size.height, scale: scale) else { return nil }
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(seed >> 11) / CGFloat(1 << 53)
        }
        for _ in 0..<260 {
            let x = next() * size.width
            let y = next() * size.height
            let roll = next()
            let radius: CGFloat
            let alpha: CGFloat
            if roll < 0.62 {
                radius = 0.3 + 0.25 * next()
                alpha = 0.10 + 0.20 * next()
            } else if roll < 0.93 {
                radius = 0.55 + 0.35 * next()
                alpha = 0.30 + 0.30 * next()
            } else {
                radius = 0.9 + 0.5 * next()
                alpha = 0.70 + 0.30 * next()
                context.setFillColor(SpaceRGB(star.red, star.green, star.blue, opacity: alpha * 0.14 * star.opacity).cgColor)
                context.fillEllipse(in: CGRect(x: x - radius * 3, y: y - radius * 3,
                                               width: radius * 6, height: radius * 6))
            }
            context.setFillColor(SpaceRGB(star.red, star.green, star.blue, opacity: alpha * star.opacity).cgColor)
            context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
        return context.makeImage()
    }

    /// One dot of the live blue. A particle is a soft glow. The pulse is the same
    /// glow with a crisp core, so a quick round trip reads as a sharp flash.
    static func flowDot(palette: SpacePalette, scale: CGFloat, side: CGFloat, crisp: Bool) -> CGImage? {
        guard let context = bitmap(width: side, height: side, scale: scale) else { return nil }
        let center = CGPoint(x: side / 2, y: side / 2)
        let live = palette.live
        // Full-strength live blue at the core, feathering to nothing at the edge.
        let colors = [live.cgColor, live.faded(0.6).cgColor, live.faded(0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors,
                                     locations: [0, 0.35, 1]) {
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: side / 2, options: [])
        }
        if crisp {
            context.setFillColor(live.cgColor)
            context.fillEllipse(in: CGRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3))
        }
        return context.makeImage()
    }

    /// A tiling dither: a 128-pixel tile of faint light and dark specks.
    static func grainColor(scale: CGFloat) -> CGColor? {
        let tile: CGFloat = 128
        // One speck per device pixel, so the dither is as fine as the screen.
        let pixels = Int((tile * scale).rounded())
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let dither = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                     bytesPerRow: 0, space: space,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var seed: UInt64 = 0xD1B5_4A32_D192_ED03
        for y in 0..<pixels {
            for x in 0..<pixels {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let light = (seed >> 33) & 1 == 0
                dither.setFillColor(light ? CGColor(gray: 1, alpha: 0.025) : CGColor(gray: 0, alpha: 0.025))
                dither.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        guard let tileImage = dither.makeImage() else { return nil }
        let pattern = NSImage(cgImage: tileImage, size: NSSize(width: tile, height: tile))
        return NSColor(patternImage: pattern).cgColor
    }

    /// A transparent RGBA bitmap at `scale`, drawn in points.
    private static func bitmap(width: CGFloat, height: CGFloat, scale: CGFloat) -> CGContext? {
        let w = Int((width * scale).rounded(.up)), h = Int((height * scale).rounded(.up))
        guard w > 0, h > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        return context
    }
}
