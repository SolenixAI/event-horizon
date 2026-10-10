//
//  OnboardingScene.swift
//
//  The first-launch stage as a value: the step and the live facts in, the scene
//  out. It holds no clock and no view. OnboardingMotion turns time into motion,
//  and OnboardingStage draws what this says.
//

import Foundation
import simd

/// What the stage shows: what macOS and the pairing have reported so far.
struct OnboardingSceneFacts: Equatable, Sendable {
    /// PCs found on the network. Find lights each one as a star.
    var foundPCs = 0
    /// The chosen PC has paired. Pair locks the beam.
    var paired = false
    /// The live state of each optional permission, as the rail reads it.
    var permissions: [OnboardingItem: OnboardingItemState] = [:]
}

/// Where the camera sits in the black hole's world, in Schwarzschild radii and
/// degrees. The camera orbits the hole: `azimuth` around it, `elevation` above
/// the disk, `distance` from it. `principal` is where the hole lands on screen
/// (a lens shift, 0...1 of the window), so the framing never depends on the window.
struct CameraPose: Equatable, Sendable {
    var azimuth: Double
    var elevation: Double
    var distance: Double
    var roll: Double
    /// Vertical field of view in degrees.
    var fov: Double
    var principalX: Double
    var principalY: Double

    /// Home's view of the world: where onboarding's dive comes out, far from the
    /// hole, which sits small in the upper right margin, clear of the PC.
    static let home = CameraPose(azimuth: 158, elevation: -10, distance: 230, roll: 2, fov: 46,
                                 principalX: 0.87, principalY: 0.2)

    /// A move between two poses. Distance travels in log space, so a dolly in
    /// feels even all the way to the horizon.
    static func mix(_ from: CameraPose, _ to: CameraPose, _ amount: Double) -> CameraPose {
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * amount }
        return CameraPose(azimuth: lerp(from.azimuth, to.azimuth),
                          elevation: lerp(from.elevation, to.elevation),
                          distance: exp(lerp(log(from.distance), log(to.distance))),
                          roll: lerp(from.roll, to.roll),
                          fov: lerp(from.fov, to.fov),
                          principalX: lerp(from.principalX, to.principalX),
                          principalY: lerp(from.principalY, to.principalY))
    }
}

enum BeamState: Equatable, Sendable {
    case none, forming, locked
}

/// One optional permission on the orbit. Granted powers on and joins the orbit;
/// anything else waits dark at the rim.
struct OnboardingSatellite: Equatable, Sendable {
    let item: OnboardingItem
    let powered: Bool
}

struct OnboardingScene: Equatable, Sendable {
    let pose: CameraPose
    /// 1 lights the black hole; 0 hands the stage to Home's deep space.
    let blackHoleLight: Double
    let pcStars: Int
    /// Sonar ripples from the PC while Find looks for PCs.
    let searching: Bool
    let beam: BeamState
    let satellites: [OnboardingSatellite]

    /// Enough stars to read as a field of PCs, not a count to audit.
    static let maxPCStars = 8

    /// The scene for a step. The same step and facts always give the same scene.
    static func make(step: OnboardingStep, facts: OnboardingSceneFacts) -> OnboardingScene {
        OnboardingScene(
            pose: pose(for: step),
            blackHoleLight: step == .ready ? 0 : 1,
            pcStars: step == .welcome ? 0 : min(facts.foundPCs, maxPCStars),
            searching: step == .findPC,
            beam: beam(for: step, paired: facts.paired),
            satellites: satellites(for: step, permissions: facts.permissions))
    }

    /// Each step is one camera stop. Setup orbits up and around the hole and
    /// pulls back, framing it right of the words; Ready dives into the horizon.
    private static func pose(for step: OnboardingStep) -> CameraPose {
        switch step {
        case .welcome: CameraPose(azimuth: 0, elevation: 6.5, distance: 24, roll: -7, fov: 42,
                                  principalX: 0.60, principalY: 0.40)
        case .findPC: CameraPose(azimuth: 16, elevation: 12, distance: 29, roll: -4, fov: 44,
                                 principalX: 0.70, principalY: 0.40)
        case .pair: CameraPose(azimuth: 26, elevation: 17, distance: 32, roll: -2, fov: 44,
                               principalX: 0.71, principalY: 0.42)
        case .controls: CameraPose(azimuth: 38, elevation: 25, distance: 37, roll: 0, fov: 46,
                                   principalX: 0.70, principalY: 0.44)
        case .ready: CameraPose(azimuth: 58, elevation: 7, distance: 0.7, roll: 4, fov: 58,
                                principalX: 0.5, principalY: 0.5)
        }
    }

    /// Past the horizon the camera comes out far away in calm space, the hole a
    /// small ember behind it, and drifts back as Home takes over.
    static let emergePose = CameraPose(azimuth: 150, elevation: -14, distance: 160, roll: 6, fov: 48,
                                       principalX: 0.8, principalY: 0.26)
    static let emergeRest = CameraPose.home

    /// Where the camera starts on launch: far out in space, before it flies in.
    static let arrivalPose = CameraPose(azimuth: -42, elevation: 26, distance: 96, roll: -18, fov: 38,
                                        principalX: 0.58, principalY: 0.42)

    private static func beam(for step: OnboardingStep, paired: Bool) -> BeamState {
        switch step {
        case .welcome, .findPC: .none
        case .pair: paired ? .locked : .forming
        case .controls, .ready: paired ? .locked : .none
        }
    }

    /// The optional items the rail offers, in order. Open at login is never on the stage.
    private static let orbitItems: [OnboardingItem] = [.notifications, .controllerButtons, .volumeKeys, .wifiHelper]

    private static func satellites(for step: OnboardingStep,
                                   permissions: [OnboardingItem: OnboardingItemState]) -> [OnboardingSatellite] {
        guard step.rawValue >= OnboardingStep.controls.rawValue else { return [] }
        return orbitItems.compactMap { item in
            guard let state = permissions[item], state != .notInThisBuild else { return nil }
            return OnboardingSatellite(item: item, powered: state == .allowed)
        }
    }
}

/// Where things sit in the black hole's world, in Schwarzschild radii. The disk
/// lies in the y = 0 plane; y is up.
enum StageWorld {
    static let hole = SIMD3<Double>(0, 0, 0)
    /// The Mac, in front of the hole and below the disk, where the search starts.
    static let mac = SIMD3<Double>(5.9, -1.5, 13.5)
    /// Where the found PCs gather, beyond the hole. The first is the PC the person picks.
    static let pcAnchors: [SIMD3<Double>] = [
        SIMD3(-13.5, 4.8, -4.3), SIMD3(-16.5, 7.4, -9.0), SIMD3(-19.0, 3.2, -1.5),
        SIMD3(-11.0, 8.6, -12.0), SIMD3(-21.5, 6.0, -6.5), SIMD3(-14.5, 1.6, -11.5),
        SIMD3(-18.0, 9.8, -3.0), SIMD3(-23.0, 2.4, -10.5)
    ]
    /// The beam bends through this point: toward the hole, as gravity bends light,
    /// but wide of the shadow.
    static let beamBend = SIMD3<Double>(-2.3, 1.0, 2.8)
    /// The shadow's radius as the camera sees it: the critical impact parameter, 3√3/2.
    static let shadowRadius = 3 * 3.0.squareRoot() / 2
    /// The satellites' orbit: its radius and its tilt off the disk, in degrees.
    static let orbitRadius = 15.0
    static let orbitTilt = 18.0
}

/// One camera for the whole stage: the shader traces rays through it and the
/// overlay projects points through it, so a node sits exactly where the light is.
struct StageCamera: Equatable, Sendable {
    let position: SIMD3<Double>
    let forward: SIMD3<Double>
    let right: SIMD3<Double>
    let up: SIMD3<Double>
    /// Focal length in points.
    let focal: Double
    /// Where the camera's axis meets the screen, in points.
    let principal: CGPoint

    init(pose: CameraPose, size: CGSize) {
        let azimuth = pose.azimuth * .pi / 180
        let elevation = pose.elevation * .pi / 180
        let position = pose.distance * SIMD3(cos(elevation) * sin(azimuth), sin(elevation),
                                             cos(elevation) * cos(azimuth))
        let forward = simd_normalize(-position)
        let level = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
        let lifted = simd_cross(level, forward)
        let roll = pose.roll * .pi / 180
        self.position = position
        self.forward = forward
        right = level * cos(roll) + lifted * sin(roll)
        up = lifted * cos(roll) - level * sin(roll)
        focal = size.height / 2 / tan(pose.fov * .pi / 360)
        principal = CGPoint(x: size.width * pose.principalX, y: size.height * pose.principalY)
    }

    /// A world point on screen, with its depth; nil when it is behind the camera.
    func project(_ point: SIMD3<Double>) -> (point: CGPoint, depth: Double)? {
        let offset = point - position
        let depth = simd_dot(offset, forward)
        guard depth > 0.1 else { return nil }
        return (CGPoint(x: principal.x + focal * simd_dot(offset, right) / depth,
                        y: principal.y - focal * simd_dot(offset, up) / depth), depth)
    }

    /// The shadow's radius on screen, in points.
    var shadowRadius: Double {
        focal * StageWorld.shadowRadius / simd_length(position)
    }

    /// True when the hole's shadow hides this point: it is behind the hole and inside the shadow.
    func isHidden(_ point: SIMD3<Double>) -> Bool {
        guard let seen = project(point), let hole = project(StageWorld.hole) else { return true }
        let apart = hypot(seen.point.x - hole.point.x, seen.point.y - hole.point.y)
        return seen.depth > hole.depth && apart < shadowRadius
    }
}
