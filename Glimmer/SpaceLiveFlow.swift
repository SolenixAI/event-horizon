//
//  SpaceLiveFlow.swift
//
//  The live connection, as Home's space shows it. Its numbers are the ones the
//  app already measures: the readiness ping behind the chip while the PC is
//  ready, and the stream's own stats while a PC streams. This file holds the
//  pure mapping from those numbers to the animation's parameters, the smoothing
//  that keeps them from jittering, and the sampler that reads them from the
//  model. No new network call is made.
//

import Foundation

/// The live connection's numbers, as the space reads them.
struct LiveFlowReading: Equatable {
    /// Round trip in ms: the chip's readiness ping while the PC is ready, or the
    /// stream's measured latency while it streams. nil means no live data.
    var rttMs: Double?
    /// The stream's measured bitrate in Mbps. nil when no stream is up.
    var bitrateMbps: Double?

    static let none = LiveFlowReading(rttMs: nil, bitrateMbps: nil)
}

/// Whether the live flow runs, holds still or is hidden.
enum SpaceFlow: Equatable {
    /// Reduce Motion: no flow is shown at all.
    case hidden
    /// The window is not key, or the stream fills the window: the flow freezes.
    case paused
    /// The flow samples the live numbers once a second and animates them.
    case running
}

/// Maps the live numbers to the animation's parameters. Every function is pure.
enum LiveFlowMapping {
    /// The particle slots. Density is the share of these that are shown.
    static let slotCount = 36
    /// The bitrate at which every slot shows.
    static let fullBitrateMbps = 80.0
    /// The shortest round trip: a crisp pulse at low latency.
    static let quickLapSeconds = 1.0
    /// The longest round trip: a stretched pulse at a spike.
    static let stretchedLapSeconds = 9.0
    /// Each millisecond of latency adds this many seconds to the round trip.
    static let secondsPerMs = 0.12
    /// The weight of a new sample in the smoothing (0 freezes, 1 follows raw).
    static let smoothingWeight = 0.35
    /// A pulse change under this share is not worth a new animation parameter.
    static let retimeTolerance = 0.02

    /// The pulse's round trip in seconds for a latency, or nil when there is
    /// no latency: the pulse is still.
    static func pulseLapSeconds(rttMs: Double?) -> Double? {
        guard let rttMs, rttMs.isFinite else { return nil }
        let raw = quickLapSeconds + secondsPerMs * max(0, rttMs)
        return min(max(raw, quickLapSeconds), stretchedLapSeconds)
    }

    /// The number of particle slots shown for a bitrate: none without one, all
    /// at `fullBitrateMbps`.
    static func activeSlots(bitrateMbps: Double?) -> Int {
        guard let bitrateMbps, bitrateMbps.isFinite, bitrateMbps > 0 else { return 0 }
        let share = min(bitrateMbps / fullBitrateMbps, 1)
        return Int((Double(slotCount) * share).rounded())
    }

    /// An exponential smoothing of a live value. A missing sample is no data,
    /// so it clears the value at once rather than holding a stale one.
    static func smooth(_ previous: Double?, _ sample: Double?) -> Double? {
        guard let sample, sample.isFinite else { return nil }
        guard let previous else { return sample }
        return previous + smoothingWeight * (sample - previous)
    }

    /// The phase of a particle slot on the round trip, in 0..<1. The radical
    /// inverse in base 2 spreads any leading run of slots evenly, so the shown
    /// particles stay spaced as the density changes.
    static func slotPhase(_ slot: Int) -> Double {
        var n = slot
        var weight = 0.5
        var phase = 0.0
        while n > 0 {
            if n & 1 == 1 { phase += weight }
            weight *= 0.5
            n >>= 1
        }
        return phase
    }
}

extension AppModel {
    /// The live connection as the space reads it. While a PC streams, the
    /// stream's own stats (the same the stats overlay reads). Otherwise the
    /// readiness ping the chip shows, and only while the chip says Ready.
    @MainActor
    func liveFlowReading() async -> LiveFlowReading {
        if isStreaming {
            guard let session = nativeSession, let details = await session.menuBarDetails() else {
                return .none
            }
            return LiveFlowReading(rttMs: details.snapshot.rttMs,
                                   bitrateMbps: details.snapshot.measuredBitrateMbps)
        }
        guard case .ready(let ms) = ChipPresentation(live: hostLiveStatus) else { return .none }
        return LiveFlowReading(rttMs: ms.map(Double.init), bitrateMbps: nil)
    }
}
