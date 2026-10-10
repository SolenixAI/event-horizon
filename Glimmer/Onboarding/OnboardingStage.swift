//
//  OnboardingStage.swift
//
//  The first-launch stage: the whole window looks into a black hole's world.
//  One 3D camera flies through it: in from deep space on launch, around the
//  hole across setup, and down into the horizon on Ready. Each frame the camera
//  goes to the Metal ray tracer (the light) and to the overlay (the Mac, the
//  PC, the beam, the satellites), so both see the same world from the same
//  place. TimelineView gives the time, and VoiceOver ignores the stage.
//

import SwiftUI

struct OnboardingStage: View {
    let step: OnboardingStep
    let facts: OnboardingSceneFacts
    /// The chosen PC's name, for its node once it is found.
    let pcName: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The camera's path to the current stop, and when it set off.
    @State private var path: CameraPath
    @State private var launched = Date.now
    @State private var pcsLitAt = Date.distantPast
    @State private var pairedAt = Date.distantPast
    @State private var poweredAt = Date.distantPast

    init(step: OnboardingStep, facts: OnboardingSceneFacts, pcName: String = "Your PC") {
        self.step = step
        self.facts = facts
        self.pcName = pcName
        let stop = OnboardingScene.make(step: step, facts: facts).pose
        _path = State(initialValue: CameraPath(from: OnboardingScene.arrivalPose, to: stop,
                                               start: .now, kind: step == .ready ? .fall : .arrive))
    }

    var body: some View {
        let scene = OnboardingScene.make(step: step, facts: facts)
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
            // The light runs on its own display link; the overlay follows the same camera.
            SpaceFieldView(paused: reduceMotion) { now, size in fieldUniforms(at: now, size: size) }
            TimelineView(.animation(paused: reduceMotion)) { context in
                let now = context.date
                let camera = StageCamera(pose: livePose(at: now), size: size)
                let falling = path.kind == .fall ? path.progress(at: now, reduceMotion: reduceMotion) : 0
                ZStack {
                    StageDrawing(scene: scene, camera: camera, size: size, now: now, reduceMotion: reduceMotion,
                                 stepStart: path.start, pcsLitAt: pcsLitAt, pairedAt: pairedAt,
                                 poweredAt: poweredAt, launched: launched)
                        .opacity(1 - min(falling * 3, 1))
                    nodes(scene: scene, camera: camera)
                        .opacity(1 - min(falling * 3, 1))
                    // Through the horizon the window goes dark, then opens on calm space.
                    Color.black.opacity(pow(falling, 6) * (1 - path.emerged(at: now, reduceMotion: reduceMotion)))
                }
            }
            }
        }
        .ignoresSafeArea()
        .onChange(of: step) { _, next in
            let now = Date.now
            path = CameraPath(from: path.pose(at: now, reduceMotion: reduceMotion),
                              to: OnboardingScene.make(step: next, facts: facts).pose,
                              start: now, kind: next == .ready ? .fall : .glide)
        }
        .onChange(of: facts.foundPCs) { _, _ in pcsLitAt = .now }
        .onChange(of: facts.paired) { _, paired in if paired { pairedAt = .now } }
        .onChange(of: grantedCount) { _, _ in poweredAt = .now }
        .accessibilityHidden(true)
    }

    /// The camera now: its path, plus the slow drift that keeps the world deep.
    /// The drift fades out on the fall, so the dive runs true.
    private func livePose(at now: Date) -> CameraPose {
        var pose = path.pose(at: now, reduceMotion: reduceMotion)
        let drift = OnboardingMotion.drift(elapsed: now.timeIntervalSince(launched), reduceMotion: reduceMotion)
        let steady = path.kind == .fall ? 1 - path.progress(at: now, reduceMotion: reduceMotion) : 1
        pose.azimuth += drift.azimuth * steady
        pose.elevation += drift.elevation * steady
        return pose
    }

    /// The two ends of the link, named where they sit in the world: this Mac, and
    /// the PC once it is found. Nearer reads larger.
    @ViewBuilder
    private func nodes(scene: OnboardingScene, camera: StageCamera) -> some View {
        if scene.searching || scene.beam != .none, let mac = camera.project(StageWorld.mac) {
            StageNode(symbol: "laptopcomputer", label: "This Mac")
                .scaleEffect(nearness(mac.depth))
                .position(mac.point)
                .transition(.opacity)
        }
        if scene.pcStars > 0, let anchor = StageWorld.pcAnchors.first, let pc = camera.project(anchor) {
            StageNode(symbol: "desktopcomputer", label: pcName, live: scene.beam == .locked)
                .scaleEffect(nearness(pc.depth))
                .position(pc.point)
                .transition(.opacity)
        }
    }

    private func nearness(_ depth: Double) -> Double {
        min(max(24 / depth, 0.92), 1.2)
    }

    private var grantedCount: Int {
        facts.permissions.values.filter { $0 == .allowed }.count
    }

    /// The ray tracer's uniforms for a moment: the camera, the clock, and the
    /// disk's light, which swells in on launch and dims through the horizon.
    private func fieldUniforms(at now: Date, size: CGSize) -> FieldUniforms {
        let elapsed = now.timeIntervalSince(launched)
        let falling = path.kind == .fall ? path.progress(at: now, reduceMotion: reduceMotion) : 0
        let dawn = OnboardingMotion.firstLight(elapsed: elapsed, reduceMotion: reduceMotion)
        // Out the other side the hole is far behind: its disk a quiet ember.
        let ember = path.emerged(at: now, reduceMotion: reduceMotion) > 0 ? 0.7 : dawn * (1 - falling * 0.4)
        return FieldUniforms(camera: StageCamera(pose: livePose(at: now), size: size),
                             size: size,
                             time: OnboardingMotion.shaderTime(elapsed: elapsed, reduceMotion: reduceMotion),
                             light: ember)
    }
}

/// The camera's travel from one stop to the next: the launch fly-in, a glide
/// between setup stops, or the fall that gathers speed into the horizon.
struct CameraPath: Equatable {
    enum Kind: Equatable { case arrive, glide, fall }

    let from: CameraPose
    let to: CameraPose
    let start: Date
    let kind: Kind

    func progress(at now: Date, reduceMotion: Bool) -> Double {
        let elapsed = now.timeIntervalSince(start)
        switch kind {
        case .arrive: return OnboardingMotion.arrive(elapsed: elapsed, reduceMotion: reduceMotion)
        case .glide: return OnboardingMotion.travel(elapsed: elapsed, reduceMotion: reduceMotion)
        case .fall: return OnboardingMotion.fall(elapsed: elapsed, reduceMotion: reduceMotion)
        }
    }

    /// How far the camera has come out the other side; only a fall has one.
    func emerged(at now: Date, reduceMotion: Bool) -> Double {
        kind == .fall ? OnboardingMotion.emerge(sinceFall: now.timeIntervalSince(start), reduceMotion: reduceMotion) : 0
    }

    func pose(at now: Date, reduceMotion: Bool) -> CameraPose {
        let out = emerged(at: now, reduceMotion: reduceMotion)
        guard out <= 0 else { return CameraPose.mix(OnboardingScene.emergePose, OnboardingScene.emergeRest, out) }
        return CameraPose.mix(from, to, progress(at: now, reduceMotion: reduceMotion))
    }
}

/// One end of the link, as a light in space: a bright core with a halo on the
/// node's place in the world, and a glass tag beside it naming the device.
/// Blue once the link is live.
private struct StageNode: View {
    let symbol: String
    let label: String
    var live = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.horizonBlue.opacity(live ? 0.6 : 0.3))
                .frame(width: 36, height: 36)
                .blur(radius: 10)
            Circle()
                .fill(live ? Color.horizonBlue : .white)
                .frame(width: 7, height: 7)
                .shadow(color: live ? Color.horizonBlue : .white, radius: 5)
        }
        .frame(width: 18, height: 18)
        // The tag hangs off the light without moving it off its point.
        .overlay(alignment: .leading) {
            Label(label, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .glassEffect(.regular.tint(live ? Color.horizonBlue.opacity(0.22) : .clear), in: .capsule)
                .offset(x: 26)
        }
        .animation(.smooth(duration: 0.5), value: live)
    }
}
