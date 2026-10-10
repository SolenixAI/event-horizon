//
//  OnboardingStageDrawing.swift
//
//  What lives in the black hole's world besides its light: the search rings
//  that spread from the Mac, the beam that bends over the hole to the chosen
//  PC, the found PCs, and the permission satellites on their tilted orbit. Each
//  is a 3D shape projected through the stage camera, so it moves with real
//  perspective and the hole's shadow hides what passes behind it. Live marks
//  are blue, and an ungranted satellite is a dim dot, never gold.
//

import SwiftUI
import simd

struct StageDrawing: View {
    let scene: OnboardingScene
    let camera: StageCamera
    let size: CGSize
    let now: Date
    let reduceMotion: Bool
    let stepStart: Date
    let pcsLitAt: Date
    let pairedAt: Date
    let poweredAt: Date
    let launched: Date

    var body: some View {
        Canvas { context, _ in
            drawSonar(&context)
            drawOrbit(&context)
            drawBeam(&context)
            drawPCStars(&context)
            drawSatellites(&context)
        }
    }

    /// While Find searches, wavefronts leave the Mac: spheres in the world that
    /// grow with distance, seen as rings that shrink with the Mac's depth.
    private func drawSonar(_ context: inout GraphicsContext) {
        guard scene.searching, let mac = camera.project(StageWorld.mac),
              let phase = OnboardingMotion.sonarPhase(elapsed: now.timeIntervalSince(stepStart),
                                                      reduceMotion: reduceMotion) else { return }
        for offset in [0.0, 0.5] {
            let cycle = (phase + offset).truncatingRemainder(dividingBy: 1)
            let radius = camera.focal * (0.3 + 3.2 * cycle) / mac.depth
            context.stroke(dot(mac.point, radius), with: .color(Color.horizonBlue.opacity(0.6 * pow(1 - cycle, 1.8))),
                           lineWidth: 1.2)
        }
    }

    /// The beam: light from the Mac bends over the gravity well to the chosen PC.
    /// It draws itself out while pairing waits, locks with one flash on Allow,
    /// then carries a pulse back and forth, the link alive.
    private func drawBeam(_ context: inout GraphicsContext) {
        guard scene.beam != .none, let pc = StageWorld.pcAnchors.first else { return }
        let curve = (0...96).map { index -> SIMD3<Double> in
            let along = Double(index) / 96
            let rest = 1 - along
            return rest * rest * StageWorld.mac + 2 * rest * along * StageWorld.beamBend + along * along * pc
        }
        let points = curve.compactMap { camera.project($0)?.point }
        guard points.count > 1 else { return }
        var arc = Path()
        arc.addLines(points)
        let locked = scene.beam == .locked
        let formed = locked ? 1 : OnboardingMotion.travel(elapsed: now.timeIntervalSince(stepStart),
                                                          reduceMotion: reduceMotion)
        let drawn = arc.trimmedPath(from: 0, to: formed)
        let flash = OnboardingMotion.lockBeat(sinceLock: now.timeIntervalSince(pairedAt), reduceMotion: reduceMotion)
        let gradient = Gradient(colors: [.white.opacity(0.9), Color.horizonBlue])

        var glow = context
        glow.addFilter(.blur(radius: 9 + 10 * flash))
        glow.stroke(drawn, with: .color(Color.horizonBlue.opacity((locked ? 0.6 : 0.34) + 0.4 * flash)),
                    style: StrokeStyle(lineWidth: 5 + 8 * flash, lineCap: .round))
        context.stroke(drawn, with: .linearGradient(gradient, startPoint: points[0], endPoint: points[points.count - 1]),
                       style: StrokeStyle(lineWidth: locked ? 1.8 : 1.2, lineCap: .round,
                                          dash: locked ? [] : [2, 7]))

        // While it waits, a bright head searches along the arc; once locked, a pulse travels the link.
        guard !reduceMotion else { return }
        let head: Double = locked ? 0.5 + 0.5 * sin(now.timeIntervalSince(launched) * 1.4) : formed
        let spot = points[min(Int(head * Double(points.count - 1)), points.count - 1)]
        var bloom = context
        bloom.addFilter(.blur(radius: 8))
        bloom.fill(dot(spot, 10), with: .color(Color.horizonBlue.opacity(0.8)))
        context.fill(dot(spot, 2.6), with: .color(.white))
    }

    /// Each found PC is a star. The newest one rises to full light; the rest stay lit.
    private func drawPCStars(_ context: inout GraphicsContext) {
        // The chosen PC's light is its node; the others are stars.
        let count = scene.pcStars
        for index in 0..<count where index > 0 {
            guard let seen = camera.project(StageWorld.pcAnchors[index]),
                  !camera.isHidden(StageWorld.pcAnchors[index]) else { continue }
            let lit = index == count - 1
                ? OnboardingMotion.ignite(elapsed: now.timeIntervalSince(pcsLitAt), reduceMotion: reduceMotion)
                : 1
            drawLive(&context, at: seen.point, brightness: lit, scale: nearness(seen.depth))
        }
    }

    /// The orbit the satellites ride: a tilted ring around the hole, brighter on
    /// the near side, and gone where it passes behind the shadow.
    private func drawOrbit(_ context: inout GraphicsContext) {
        guard !scene.satellites.isEmpty else { return }
        let ring = (0...120).map { orbitPoint(Double($0) / 120 * 2 * .pi) }
        stroke3D(&context, ring, color: .white, opacity: 0.16, width: 1)
    }

    /// Granted permissions power on and ride the orbit; the rest wait dark on it.
    private func drawSatellites(_ context: inout GraphicsContext) {
        let satellites = scene.satellites
        guard !satellites.isEmpty else { return }
        let spin = reduceMotion ? 0 : now.timeIntervalSince(launched) * 0.09
        for (index, satellite) in satellites.enumerated() {
            let place = orbitPoint(2 * .pi * Double(index) / Double(satellites.count) + spin)
            guard let seen = camera.project(place), !camera.isHidden(place) else { continue }
            if satellite.powered {
                let lit = OnboardingMotion.ignite(elapsed: now.timeIntervalSince(poweredAt), reduceMotion: reduceMotion)
                drawLive(&context, at: seen.point, brightness: lit, scale: nearness(seen.depth))
            } else {
                context.fill(dot(seen.point, 2.6 * nearness(seen.depth)), with: .color(.white.opacity(0.32)))
            }
        }
    }

    /// A point on the satellites' orbit: a circle in the disk plane, tipped about the x axis.
    private func orbitPoint(_ angle: Double) -> SIMD3<Double> {
        let tilt = StageWorld.orbitTilt * .pi / 180
        let flat = SIMD3(cos(angle), 0, sin(angle)) * StageWorld.orbitRadius
        return SIMD3(flat.x, flat.z * sin(tilt), flat.z * cos(tilt))
    }

    /// Strokes a 3D polyline segment by segment: nearer is brighter and thicker,
    /// and any part the shadow hides is skipped.
    private func stroke3D(_ context: inout GraphicsContext, _ points: [SIMD3<Double>],
                          color: Color, opacity: Double, width: Double) {
        let seen = points.map { point in camera.isHidden(point) ? nil : camera.project(point) }
        for index in 1..<seen.count {
            guard let a = seen[index - 1], let b = seen[index] else { continue }
            let near = nearness((a.depth + b.depth) / 2)
            var segment = Path()
            segment.move(to: a.point)
            segment.addLine(to: b.point)
            context.stroke(segment, with: .color(color.opacity(opacity * min(near, 1.2))),
                           style: StrokeStyle(lineWidth: width * near, lineCap: .round))
        }
    }

    /// A live mark: blue core with a soft halo, scaled by its brightness and nearness.
    private func drawLive(_ context: inout GraphicsContext, at center: CGPoint, brightness: Double, scale: Double) {
        var halo = context
        halo.addFilter(.blur(radius: 9 * scale))
        halo.fill(dot(center, 15 * brightness * scale), with: .color(Color.horizonBlue.opacity(0.6 * brightness)))
        context.fill(dot(center, 3.6 * brightness * scale), with: .color(Color.horizonBlue.opacity(brightness)))
    }

    /// How much larger a thing reads for being near the camera.
    private func nearness(_ depth: Double) -> Double {
        min(max(26 / depth, 0.55), 1.6)
    }

    private func dot(_ center: CGPoint, _ radius: Double) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}
