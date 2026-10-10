//
//  StreamVolumeTests.swift
//
//  The stream's level: sixteen key steps, mute keeps the level, saved across relaunch.
//

import Foundation
import Testing
@testable import Glimmer

struct StreamVolumeTests {

    private func scratchSuite() throws -> String {
        let suite = "io.ugfugl.Glimmer.tests.stream-volume.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return suite
    }

    @Test func levelIsClampedToTheRange() {
        #expect(StreamVolume(level: 1.7).level == 1)
        #expect(StreamVolume(level: -0.3).level == 0)
        var volume = StreamVolume.full
        volume.setLevel(-0.3)
        #expect(volume.level == 0)
    }

    @Test func oneKeyStepIsASixteenthOfFullScale() {
        #expect(StreamVolume.step == 1.0 / 16.0)
        var volume = StreamVolume(level: 0.5)
        volume.stepUp()
        #expect(volume.level == 0.5625)
        volume.stepDown()
        volume.stepDown()
        #expect(volume.level == 0.4375)
    }

    @Test func sixteenPressesFromSilenceReachFullAndStop() {
        var volume = StreamVolume(level: 0)
        for _ in 0..<16 { volume.stepUp() }
        #expect(volume.level == 1)
        volume.stepUp()
        #expect(volume.level == 1)
    }

    @Test func stepsSnapToTheGrid() {
        var up = StreamVolume(level: 0.53)
        up.stepUp()
        #expect(up.level == 0.5625)
        var down = StreamVolume(level: 0.53)
        down.stepDown()
        #expect(down.level == 0.5)
    }

    @Test func muteSilencesButKeepsTheLevel() {
        var volume = StreamVolume(level: 0.4)
        volume.toggleMute()
        #expect(volume.isMuted)
        #expect(volume.gain == 0)
        #expect(volume.level == 0.4)
    }

    @Test func unmuteRestoresTheLastLevel() {
        var volume = StreamVolume(level: 0.4)
        volume.toggleMute()
        volume.toggleMute()
        #expect(!volume.isMuted)
        #expect(volume.gain == 0.4)
    }

    @Test func unmuteFromASilentLevelReturnsToTheLastAudibleLevel() {
        var volume = StreamVolume(level: 0.6)
        volume.setLevel(0)
        volume.toggleMute()
        volume.toggleMute()
        #expect(volume.level == 0.6)
        #expect(volume.gain == 0.6)
    }

    /// Dragging the slider above silence unmutes, as the Mac's own slider does.
    @Test func draggingAboveSilenceUnmutes() {
        var volume = StreamVolume(level: 0.4)
        volume.toggleMute()
        volume.setLevel(0.5)
        #expect(!volume.isMuted)
        #expect(volume.gain == 0.5)
    }

    @Test func draggingToSilenceKeepsTheMute() {
        var volume = StreamVolume(level: 0.4)
        volume.toggleMute()
        volume.setLevel(0)
        #expect(volume.isMuted)
        #expect(volume.gain == 0)
    }

    @Test func stepUpWhileMutedUnmutesLikeTheMacsKeys() {
        var volume = StreamVolume(level: 0.4)
        volume.toggleMute()
        volume.stepUp()
        #expect(!volume.isMuted)
        #expect(volume.level == 0.4375)
    }

    @Test func fullIsTheDefaultSoNothingChangesForExistingUsers() {
        #expect(StreamVolume.full.gain == 1)
        #expect(!StreamVolume.full.isMuted)
    }

    @Test func levelSurvivesARelaunch() throws {
        let suite = try scratchSuite()
        var volume = StreamVolume(level: 0.3125)
        volume.toggleMute()
        volume.save(to: try #require(UserDefaults(suiteName: suite)))
        let relaunched = StreamVolume.load(from: try #require(UserDefaults(suiteName: suite)))
        #expect(relaunched == volume)
        #expect(relaunched.gain == 0)
    }

    @Test func missingOrCorruptSavedLevelFallsBackToFull() throws {
        let suite = try scratchSuite()
        let defaults = try #require(UserDefaults(suiteName: suite))
        #expect(StreamVolume.load(from: defaults) == .full)
        defaults.set(Data("not json".utf8), forKey: StreamVolume.defaultsKey)
        #expect(StreamVolume.load(from: defaults) == .full)
    }

    @Test func outOfRangeSavedLevelIsClampedOnLoad() throws {
        let suite = try scratchSuite()
        let defaults = try #require(UserDefaults(suiteName: suite))
        let json = Data(#"{"level":3,"isMuted":false,"lastAudible":3}"#.utf8)
        defaults.set(json, forKey: StreamVolume.defaultsKey)
        #expect(StreamVolume.load(from: defaults).level == 1)
    }
}
