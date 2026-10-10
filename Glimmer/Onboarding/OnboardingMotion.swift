//
//  OnboardingMotion.swift
//
//  Time as numbers: how far the camera has travelled, when the sonar ripples,
//  how a found PC ignites, the lock beat and the title's reveal. Reduce Motion
//  snaps or stops each one, so the still stage is the same composition.
//

import Foundation

enum OnboardingMotion {
    static let travelSeconds = 1.6
    static let arrivalSeconds = 4.6
    static let fallSeconds = 2.6
    static let firstLightSeconds = 3.2
    static let sonarCycleSeconds = 1.8
    static let igniteSeconds = 0.6
    static let lockAttackSeconds = 0.15
    static let lockSeconds = 1.5

    /// Camera travel from one stop to the next: 0 at the start, 1 at the stop.
    /// A slow start and a long settle, like a camera on a crane.
    static func travel(elapsed: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? 1 : easeInOut(elapsed / travelSeconds)
    }

    /// The launch fly-in from deep space to the first stop: fast at first, then a
    /// long, soft landing, like a ship braking into orbit.
    static func arrive(elapsed: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 1 }
        let progress = min(max(elapsed / arrivalSeconds, 0), 1)
        return 1 - pow(1 - progress, 4)
    }

    /// The camera never sits dead still: a slow drift in azimuth and elevation,
    /// in degrees, so the scene keeps its depth. Reduce Motion holds it at zero.
    static func drift(elapsed: Double, reduceMotion: Bool) -> (azimuth: Double, elevation: Double) {
        guard !reduceMotion else { return (0, 0) }
        return (2.4 * sin(elapsed * 0.11), 0.9 * sin(elapsed * 0.07 + 1.3))
    }

    /// Ready's fall into the horizon: it gathers speed and is fastest at the end.
    static func fall(elapsed: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 1 }
        let progress = min(max(elapsed / fallSeconds, 0), 1)
        return pow(progress, 2.2)
    }

    /// After the fall, a beat of dark, then the camera comes out into calm deep
    /// space: 0 until then, rising to 1. Reduce Motion goes straight there.
    static let emergeHoldSeconds = 0.5
    static let emergeSeconds = 3.4
    static func emerge(sinceFall elapsed: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 1 }
        let progress = min(max((elapsed - fallSeconds - emergeHoldSeconds) / emergeSeconds, 0), 1)
        return 1 - pow(1 - progress, 3)
    }

    /// The black hole's light coming up when the window first opens.
    static func firstLight(elapsed: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? 1 : easeOut(elapsed / firstLightSeconds)
    }

    /// The sonar ring's place in its cycle, or nil while Reduce Motion stops it.
    static func sonarPhase(elapsed: Double, reduceMotion: Bool) -> Double? {
        guard !reduceMotion else { return nil }
        let seconds = max(elapsed, 0)
        return seconds.truncatingRemainder(dividingBy: sonarCycleSeconds) / sonarCycleSeconds
    }

    /// A found PC's star rising to full light.
    static func ignite(elapsed: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? 1 : easeOut(elapsed / igniteSeconds)
    }

    /// The beam's lock: a quick brightening, then a settle. Reduce Motion shows no flash.
    static func lockBeat(sinceLock: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion, sinceLock >= 0, sinceLock < lockSeconds else { return 0 }
        if sinceLock < lockAttackSeconds { return sinceLock / lockAttackSeconds }
        return 1 - (sinceLock - lockAttackSeconds) / (lockSeconds - lockAttackSeconds)
    }

    /// The shader's clock. Frozen under Reduce Motion, so the field holds still.
    static func shaderTime(elapsed: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : max(elapsed, 0)
    }

    /// Cubic ease-out over 0...1, clamped.
    private static func easeOut(_ x: Double) -> Double {
        let progress = min(max(x, 0), 1)
        return 1 - pow(1 - progress, 3)
    }

    /// Quintic ease-in-out over 0...1, clamped: symmetric, half-way at the middle.
    private static func easeInOut(_ x: Double) -> Double {
        let progress = min(max(x, 0), 1)
        return progress < 0.5 ? 16 * pow(progress, 5) : 1 - pow(-2 * progress + 2, 5) / 2
    }
}
