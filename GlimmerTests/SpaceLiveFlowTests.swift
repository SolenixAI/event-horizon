//
//  SpaceLiveFlowTests.swift
//
//  The live connection drawn in Home's space: the mapping from latency and
//  bitrate to the pulse's round trip and the particle count, the smoothing that
//  keeps it from jittering, and the undrawn round-trip path that the particles
//  travel between the Mac's horizon and the PC's bezel.
//

import CoreGraphics
import Testing
@testable import Glimmer

struct SpaceLiveFlowTests {

    // MARK: Pulse round trip follows latency

    @Test func noLatencyMeansNoPulse() {
        #expect(LiveFlowMapping.pulseLapSeconds(rttMs: nil) == nil)
        #expect(LiveFlowMapping.pulseLapSeconds(rttMs: .nan) == nil)
    }

    @Test func lowLatencyGivesAQuickPulse() {
        let quick = LiveFlowMapping.pulseLapSeconds(rttMs: 0.5)!
        #expect(quick <= 1.1)
        #expect(quick >= LiveFlowMapping.quickLapSeconds)
    }

    @Test func pulseSlowsAsLatencyRises() {
        let samples: [Double] = [0, 1, 5, 13, 30, 50, 70, 200]
        let laps = samples.map { LiveFlowMapping.pulseLapSeconds(rttMs: $0)! }
        #expect(zip(laps, laps.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(laps[3] > laps[1])
    }

    @Test func spikeStretchesThePulseButStaysBounded() {
        #expect(LiveFlowMapping.pulseLapSeconds(rttMs: 10_000) == LiveFlowMapping.stretchedLapSeconds)
        #expect(LiveFlowMapping.pulseLapSeconds(rttMs: -5) == LiveFlowMapping.quickLapSeconds)
    }

    // MARK: Particle density follows bitrate

    @Test func noBitrateMeansNoParticles() {
        #expect(LiveFlowMapping.activeSlots(bitrateMbps: nil) == 0)
        #expect(LiveFlowMapping.activeSlots(bitrateMbps: 0) == 0)
        #expect(LiveFlowMapping.activeSlots(bitrateMbps: .nan) == 0)
    }

    @Test func densityGrowsWithBitrateAndCaps() {
        let full = LiveFlowMapping.slotCount
        #expect(LiveFlowMapping.activeSlots(bitrateMbps: LiveFlowMapping.fullBitrateMbps) == full)
        #expect(LiveFlowMapping.activeSlots(bitrateMbps: LiveFlowMapping.fullBitrateMbps * 10) == full)
        let counts = [5.0, 20, 40, 60, 80].map { LiveFlowMapping.activeSlots(bitrateMbps: $0) }
        #expect(zip(counts, counts.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(counts[2] == full / 2)
    }

    // MARK: Smoothing

    @Test func smoothingStartsAtTheFirstSampleAndEases() {
        #expect(LiveFlowMapping.smooth(nil, 10) == 10)
        #expect(abs(LiveFlowMapping.smooth(10, 20)! - 13.5) < 1e-9)
        #expect(LiveFlowMapping.smooth(10, nil) == nil)
    }

    // MARK: Particle slots are evenly spread for any count

    @Test func slotPhasesStartAtZeroAndSpreadEvenly() {
        #expect(LiveFlowMapping.slotPhase(0) == 0)
        #expect(LiveFlowMapping.slotPhase(1) == 0.5)
        for count in [2, 3, 4, 8, 16, 24, 36] {
            let phases = (0..<count).map { LiveFlowMapping.slotPhase($0) }.sorted()
            var largestGap = 1 - phases.last! + phases.first!
            for (a, b) in zip(phases, phases.dropFirst()) { largestGap = max(largestGap, b - a) }
            #expect(largestGap <= 2.5 / Double(count))
        }
    }

    // MARK: Undrawn round-trip path

    private let size = CGSize(width: 1040, height: 780)
    private let bezel = CGRect(x: 99, y: 150, width: 842, height: 520)

    @Test func pathStartsAtTheMacHorizonAndTurnsAtThePCBezel() {
        let points = SpaceFlowPath.points(size: size, bezel: bezel)
        let mac = points.first!, pc = points[points.count / 2]
        #expect(abs(mac.y - size.height) < 0.001)
        #expect(mac.x < bezel.minX)
        #expect(abs(pc.x - (bezel.minX - SpaceFlowPath.bezelGap)) < 0.001)
        #expect(abs(pc.y - bezel.midY) < 0.001)
    }

    /// The round trip: out to the PC and back by the same curve, so the lap is
    /// symmetric and closes on the Mac's horizon.
    @Test func pathIsAClosedRoundTrip() {
        let points = SpaceFlowPath.points(size: size, bezel: bezel)
        #expect(points.count % 2 == 1)
        #expect(points.first == points.last)
        for i in 0..<points.count {
            let mirror = points[points.count - 1 - i]
            #expect(abs(points[i].x - mirror.x) < 0.001 && abs(points[i].y - mirror.y) < 0.001)
        }
    }

    /// The status row, the chip and the shelf sit within the bezel's columns.
    /// The round trip never enters them: it stays in the margin beside the PC.
    /// Checks each dot's full extent, not only the path's centres: a dot
    /// reaches `dotRadius` past its centre, so its edge must keep a clear gap
    /// from the bezel.
    @Test func dotsKeepAClearGapFromTheBezel() {
        let points = SpaceFlowPath.points(size: size, bezel: bezel)
        let clear: CGFloat = 8
        for p in points {
            #expect(p.x + SpaceFlowPath.dotRadius <= bezel.minX - clear)
            #expect(p.x - SpaceFlowPath.dotRadius >= 0)
            #expect(p.y >= bezel.midY - 0.001 && p.y <= size.height + 0.001)
        }
    }

    /// The particle drawn on the path is no wider than the radius the path allows for.
    @Test func particleFitsTheRadiusThePathAllows() {
        #expect(SpaceLayerView.particleSide / 2 <= SpaceFlowPath.dotRadius)
        #expect(SpaceLayerView.pulseSide / 2 <= SpaceFlowPath.dotRadius)
    }
}
