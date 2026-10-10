//
//  SpaceBackdrop.swift
//
//  Home's surroundings: a deep-space field behind the PC on the desk. The
//  field, the horizon light and the orbit trace are static. Only three faint
//  bodies move, once every few minutes, along the figure-eight from the logo.
//
//  The horizon light is atmosphere, never a signal. Gold is for what you press
//  and blue is for what is live on the PC; the light stays far dimmer and less
//  saturated than either, and the bodies are neutral so they never read as
//  live. Dark is deep space. Light is the same composition at dawn.
//
//  The drift stops under Reduce Motion, when the window is not key, when the
//  app is in the background and while a PC streams, so no per-frame work runs
//  beside the stream. VoiceOver ignores the backdrop.
//

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

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity) }

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
    /// False while the drift must stand still (see the file header).
    var drifts: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    /// Four frames a second: each body moves a few points per frame, so the
    /// drift reads as smooth and costs almost nothing.
    static let frameInterval = 0.25
    /// One lap of the figure-eight. Slow on purpose.
    static let lapSeconds: Double = 240
    /// The loop's share of the window's width, and where its middle sits.
    static let traceWidthShare: CGFloat = 0.92
    static let traceCenterY: CGFloat = 0.45

    var body: some View {
        let palette: SpacePalette = colorScheme == .dark ? .night : .dawn
        ZStack {
            SpaceField(palette: palette)
            TimelineView(.animation(minimumInterval: Self.frameInterval, paused: !drifts)) { context in
                SpaceBodies(palette: palette, seconds: context.date.timeIntervalSinceReferenceDate)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// Where the orbit trace sits in a view of `size`. Shared by the static
    /// field and the moving bodies, so they always agree.
    static func traceFrame(in size: CGSize) -> CGRect {
        FigureEightTrace.frame(in: size, widthShare: traceWidthShare, centerY: traceCenterY)
    }
}

// MARK: - Static field

/// The sky, the stars, the horizon light and the trace. Drawn once per size
/// and appearance; it is not part of the timeline, so it never redraws per
/// frame.
private struct SpaceField: View {
    let palette: SpacePalette

    var body: some View {
        Canvas { context, size in
            let sky = Gradient(colors: [palette.skyTop.color, palette.skyBottom.color])
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(sky, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

            if let star = palette.stars {
                drawStars(in: &context, size: size, color: star)
            }

            // Horizon light: gold on the left, blue on the right, standing on
            // the bottom edge like the rim of a planet's air.
            horizonGlow(context, x: size.width * 0.40, y: size.height,
                        radius: size.width * 0.62, squash: 0.30, color: palette.horizonGold)
            horizonGlow(context, x: size.width * 0.66, y: size.height,
                        radius: size.width * 0.55, squash: 0.30, color: palette.horizonBlue)

            let frame = SpaceBackdrop.traceFrame(in: size)
            context.stroke(Path(FigureEightTrace.path(in: frame)), with: .color(palette.trace.color), lineWidth: 1)
        }
    }

    private func horizonGlow(_ context: GraphicsContext, x: CGFloat, y: CGFloat,
                             radius: CGFloat, squash: CGFloat, color: SpaceRGB) {
        var layer = context
        layer.translateBy(x: x, y: y)
        layer.scaleBy(x: 1, y: squash)
        let fade = Gradient(stops: [
            .init(color: color.color, location: 0),
            .init(color: color.faded(0.45).color, location: 0.4),
            .init(color: color.faded(0).color, location: 1),
        ])
        layer.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
                   with: .radialGradient(fade, center: .zero, startRadius: 0, endRadius: radius))
    }

    /// A fixed scatter of stars: the same field on every draw.
    private func drawStars(in context: inout GraphicsContext, size: CGSize, color: SpaceRGB) {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(1 << 53)
        }
        for _ in 0..<140 {
            let x = next() * size.width
            let y = next() * size.height
            let r = 0.4 + 0.7 * next() * next()
            let alpha = 0.15 + 0.85 * next()
            let dot = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: dot), with: .color(color.faded(alpha).color))
        }
    }
}

// MARK: - Moving bodies

/// Three faint bodies on the trace, a third of a lap apart, as in the
/// three-body figure-eight. They are neutral light, never a signal colour.
private struct SpaceBodies: View {
    let palette: SpacePalette
    let seconds: Double

    var body: some View {
        Canvas { context, size in
            let frame = SpaceBackdrop.traceFrame(in: size)
            let lap = seconds / SpaceBackdrop.lapSeconds
            for k in 0..<3 {
                let center = FigureEightTrace.point(at: CGFloat(lap + Double(k) / 3), in: frame)
                let glow: CGFloat = 8
                let halo = CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)
                let fade = Gradient(stops: [
                    .init(color: palette.body.faded(0.6).color, location: 0),
                    .init(color: palette.body.faded(0).color, location: 1),
                ])
                context.fill(Path(ellipseIn: halo),
                             with: .radialGradient(fade, center: center, startRadius: 0, endRadius: glow))
                let core: CGFloat = 1.5
                context.fill(Path(ellipseIn: CGRect(x: center.x - core, y: center.y - core,
                                                    width: core * 2, height: core * 2)),
                             with: .color(palette.body.color))
            }
        }
    }
}
