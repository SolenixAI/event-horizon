//
//  SpaceBackdrop.swift
//
//  Home's surroundings: a deep-space field behind the PC on the desk. It is a
//  Core Animation layer tree, so the render server does the work: the sky, the
//  stars, the horizon light and the grain are static layers rasterised at the
//  window's backing scale, the orbit trace is a hairline, and three faint
//  neutral bodies follow the figure-eight from the logo on a path animation.
//  No frame runs on the main thread.
//
//  The horizon light is atmosphere, never a signal. Gold is for what you press
//  and blue is for what is live on the PC; the light stays far dimmer and less
//  saturated than either, and the bodies are neutral so they never read as
//  live. Dark is deep space. Light is the same composition at dawn.
//
//  The motion pauses under Reduce Motion, when the window is not key, when the
//  app is in the background and while a PC streams, and resumes without a
//  jump. The trace is anchored to the PC's bezel and sits beside it, so the
//  bodies never reach the status row or the readiness chip. VoiceOver ignores
//  the backdrop.
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

/// One appearance's backdrop colours. The horizon colours already carry their
/// low opacity: they are atmosphere, kept well under any signal.
struct SpacePalette: Equatable {
    let skyTop: SpaceRGB
    let skyBottom: SpaceRGB
    let horizonGold: SpaceRGB
    let horizonBlue: SpaceRGB
    let trace: SpaceRGB
    let body: SpaceRGB
    /// Night only: the field's stars. Dawn has none.
    let stars: SpaceRGB?

    /// Deep space: near-black, the logo's gold and blue low on the horizon.
    static let night = SpacePalette(
        skyTop: SpaceRGB(0.012, 0.016, 0.039),
        skyBottom: SpaceRGB(0.043, 0.055, 0.098),
        horizonGold: SpaceRGB(0.941, 0.541, 0.141, opacity: 0.16),
        horizonBlue: SpaceRGB(0.227, 0.627, 1.0, opacity: 0.12),
        trace: SpaceRGB(1, 1, 1, opacity: 0.08),
        body: SpaceRGB(0.92, 0.94, 1.0, opacity: 0.55),
        stars: SpaceRGB(1, 1, 1, opacity: 0.5))

    /// Dawn: the same composition, a pale sky and a soft gold horizon.
    static let dawn = SpacePalette(
        skyTop: SpaceRGB(0.894, 0.925, 0.969),
        skyBottom: SpaceRGB(0.965, 0.945, 0.910),
        horizonGold: SpaceRGB(0.788, 0.439, 0.059, opacity: 0.20),
        horizonBlue: SpaceRGB(0.227, 0.627, 1.0, opacity: 0.09),
        trace: SpaceRGB(0.106, 0.165, 0.267, opacity: 0.10),
        body: SpaceRGB(0.106, 0.165, 0.267, opacity: 0.35),
        stars: nil)
}

struct SpaceBackdrop: View {
    /// False while the motion must stand still (see the file header).
    var drifts: Bool = true
    /// The PC's bezel on Home, in this view's space. The trace is anchored to
    /// it: nothing is drawn until Home has laid the bezel out.
    var bezel: CGRect?
    @Environment(\.colorScheme) private var colorScheme

    /// One lap of the figure-eight. Slow on purpose.
    static let lapSeconds: Double = 240
    /// The trace is never wider than this share of the window.
    static let traceMaxWidthShare: CGFloat = 0.92

    var body: some View {
        SpaceLayers(palette: colorScheme == .dark ? .night : .dawn, bezel: bezel, drifts: drifts)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    /// Where the orbit trace sits, for a view of `size` and a PC bezel. The
    /// loop is as tall as the bezel and centred on it, so its arcs show only
    /// beside the PC, never under the status row or the shelf. Where the loop
    /// would be wider than the window allows, it is narrowed to that width and
    /// kept at the figure-eight's proportions, still inside the bezel's height.
    static func traceFrame(in size: CGSize, bezel: CGRect) -> CGRect {
        var width = bezel.height * FigureEightTrace.aspect
        var height = bezel.height
        let maxWidth = size.width * traceMaxWidthShare
        if width > maxWidth {
            width = maxWidth
            height = width / FigureEightTrace.aspect
        }
        return CGRect(x: (size.width - width) / 2, y: bezel.midY - height / 2,
                      width: width, height: height)
    }
}

// MARK: - Bridge

/// The Core Animation view, placed in SwiftUI.
private struct SpaceLayers: NSViewRepresentable {
    let palette: SpacePalette
    let bezel: CGRect?
    let drifts: Bool

    func makeNSView(context: Context) -> SpaceLayerView { SpaceLayerView() }

    func updateNSView(_ view: SpaceLayerView, context: Context) {
        view.configure(palette: palette, bezel: bezel, drifts: drifts)
    }
}

// MARK: - Layer tree

/// The backdrop's layers. Everything but the bodies is static; the bodies
/// and the trace live in `motion`, whose clock pauses them together.
final class SpaceLayerView: NSView {
    private let field = CAGradientLayer()
    private let stars = CALayer()
    private let horizonGold = CAGradientLayer()
    private let horizonBlue = CAGradientLayer()
    private let grain = CALayer()
    private let motion = CALayer()
    private let trace = CAShapeLayer()
    private var bodies: [CALayer] = []

    private var palette: SpacePalette = .dawn
    private var bezel: CGRect?
    private var drifting = false
    private var lastKey: BuildKey?

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
        for sub in [field, stars, horizonGold, horizonBlue, grain] {
            root.addSublayer(sub)
        }
        field.type = .axial
        horizonGold.type = .radial
        horizonBlue.type = .radial
        root.addSublayer(motion)
        motion.addSublayer(trace)
        trace.fillColor = nil
        trace.lineCap = .round
        trace.lineJoin = .round
        for _ in 0..<3 {
            let body = CALayer()
            motion.addSublayer(body)
            bodies.append(body)
        }
    }

    required init?(coder: NSCoder) { return nil }

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

    func configure(palette: SpacePalette, bezel: CGRect?, drifts: Bool) {
        self.palette = palette
        self.bezel = bezel
        rebuild()
        setDrifting(drifts)
    }

    // MARK: Build

    /// Lays out and paints the static layers, and places the trace and bodies
    /// when the PC's bezel is known. Runs only when something it depends on
    /// changes, never per frame.
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
        for layer in [field, stars, horizonGold, horizonBlue, grain, motion] {
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

        placeTraceAndBodies(size: size, scale: scale)
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

    /// The trace and the bodies. Their path is the figure-eight inside the
    /// bezel's span, flipped to this layer's unflipped space.
    private func placeTraceAndBodies(size: CGSize, scale: CGFloat) {
        guard let bezel else {
            trace.path = nil
            bodies.forEach { $0.isHidden = true }
            return
        }
        let frame = SpaceBackdrop.traceFrame(in: size, bezel: bezel)
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
        guard let path = FigureEightTrace.path(in: frame).copy(using: &flip) else { return }

        trace.frame = motion.bounds
        trace.contentsScale = scale
        trace.path = path
        // A hairline one device pixel wide, whatever the scale.
        trace.lineWidth = 1 / scale
        trace.strokeColor = palette.trace.cgColor

        let glow = SpaceImages.bodyGlow(palette: palette, scale: scale)
        let side: CGFloat = 16
        for (k, body) in bodies.enumerated() {
            body.isHidden = false
            body.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            body.contentsScale = scale
            body.contents = glow
            body.removeAllAnimations()

            let offset = CGFloat(k) / 3
            let start = FigureEightTrace.point(at: offset, in: frame)
            body.position = CGPoint(x: start.x, y: size.height - start.y)

            let drift = CAKeyframeAnimation(keyPath: "position")
            drift.path = path
            drift.calculationMode = .paced
            drift.duration = SpaceBackdrop.lapSeconds
            drift.repeatCount = .infinity
            drift.timeOffset = SpaceBackdrop.lapSeconds * Double(offset)
            body.add(drift, forKey: "orbit")
        }
    }

    // MARK: Motion

    /// Starts or pauses the bodies on the render server. Pausing freezes the
    /// clock of `motion` (its animations and its trace), and resuming continues
    /// from the same point without a jump.
    private func setDrifting(_ on: Bool) {
        guard on != drifting else { return }
        drifting = on
        if on {
            let pausedAt = motion.timeOffset
            motion.speed = 1
            motion.timeOffset = 0
            motion.beginTime = 0
            let sincePause = motion.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
            motion.beginTime = sincePause
        } else {
            let now = motion.convertTime(CACurrentMediaTime(), from: nil)
            motion.speed = 0
            motion.timeOffset = now
        }
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

    /// A soft glow with a small core: one body on the trace.
    static func bodyGlow(palette: SpacePalette, scale: CGFloat) -> CGImage? {
        let side: CGFloat = 16
        guard let context = bitmap(width: side, height: side, scale: scale) else { return nil }
        let center = CGPoint(x: side / 2, y: side / 2)
        let colors = [palette.body.faded(0.6).cgColor, palette.body.faded(0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors,
                                     locations: [0, 1]) {
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: side / 2, options: [])
        }
        context.setFillColor(palette.body.cgColor)
        context.fillEllipse(in: CGRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3))
        return context.makeImage()
    }

    /// A tiling dither: a 128-pixel tile of faint light and dark specks.
    static func grainColor(scale: CGFloat) -> CGColor? {
        let tile: CGFloat = 128
        // One speck per device pixel, so the dither is as fine as the screen.
        let pixels = Int((tile * scale).rounded())
        guard let dither = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                     bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
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
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        return context
    }
}
