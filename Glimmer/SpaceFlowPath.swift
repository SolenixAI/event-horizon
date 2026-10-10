//
//  SpaceFlowPath.swift
//
//  The undrawn path the live flow travels: a round trip from the Mac's side of
//  the bottom horizon to the PC's bezel and back. It is never stroked. Its
//  shape is felt through the particles' motion. Only geometry lives here; the
//  backdrop decides where the bezel sits.
//
//  The curve stays in the margin beside the PC, left of the bezel's leading
//  edge. The status row, the readiness chip and the game shelf all sit inside
//  the bezel's columns, so the round trip never crosses their text.
//

import CoreGraphics

enum SpaceFlowPath {
    /// How far the PC end of the round trip stops short of the bezel's edge,
    /// measured from the path to the bezel's edge (a dot's centre sits here).
    static let bezelGap: CGFloat = 14
    /// The radius of the largest dot drawn on the path (a particle's glow).
    static let dotRadius: CGFloat = 4
    /// Samples on the way out, so the whole round trip has 2n + 1 points.
    static let halfSamples = 48

    /// The round trip in top-down window coordinates (y grows downwards, as in
    /// the view's flipped space). It starts at the Mac's horizon, turns at the
    /// PC's bezel, and comes back by the same curve. The first and last points
    /// are the Mac; the middle point is the PC.
    static func points(size: CGSize, bezel: CGRect) -> [CGPoint] {
        let mac = CGPoint(x: bezel.minX * 0.5, y: size.height)
        let pc = CGPoint(x: bezel.minX - bezelGap, y: bezel.midY)
        // One cubic: it leaves the horizon up the margin and arrives at the PC
        // from below. Every control point stays left of the PC, so the curve does.
        let c1 = CGPoint(x: mac.x * 0.25, y: size.height - (size.height - pc.y) * 0.5)
        let c2 = CGPoint(x: pc.x * 0.35, y: pc.y + (size.height - pc.y) * 0.2)
        let out = (0...halfSamples).map { i -> CGPoint in
            let progress = CGFloat(i) / CGFloat(halfSamples)
            let remaining = 1 - progress
            let w0 = remaining * remaining * remaining, w1 = 3 * remaining * remaining * progress
            let w2 = 3 * remaining * progress * progress, w3 = progress * progress * progress
            return CGPoint(x: w0 * mac.x + w1 * c1.x + w2 * c2.x + w3 * pc.x,
                           y: w0 * mac.y + w1 * c1.y + w2 * c2.y + w3 * pc.y)
        }
        // The way back retraces the curve, so the lap is a symmetric round trip.
        return out + out.prefix(halfSamples).reversed()
    }

    /// The round trip as a path for a keyframe animation: unflipped, as the
    /// layer's space is (origin at the bottom left).
    static func path(size: CGSize, bezel: CGRect) -> CGPath {
        let path = CGMutablePath()
        for (i, point) in points(size: size, bezel: bezel).enumerated() {
            let flipped = CGPoint(x: point.x, y: size.height - point.y)
            if i == 0 { path.move(to: flipped) } else { path.addLine(to: flipped) }
        }
        return path
    }
}
