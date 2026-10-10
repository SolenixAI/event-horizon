//
//  StreamVolumePresentationTests.swift
//
//  What the stream volume looks and sounds like: the speaker glyph, the lit segments, the announcement.
//

import Testing
@testable import Glimmer

struct StreamVolumePresentationTests {

    @Test func levelPicksTheSpeakerGlyph() {
        #expect(StreamVolume(level: 0.1).symbol == "speaker.wave.1")
        #expect(StreamVolume(level: 0.5).symbol == "speaker.wave.2")
        #expect(StreamVolume(level: 1).symbol == "speaker.wave.3")
    }

    @Test func mutedAndSilentShowTheSlashedSpeaker() {
        var muted = StreamVolume(level: 0.5)
        muted.toggleMute()
        #expect(muted.symbol == "speaker.slash")
        #expect(StreamVolume(level: 0).symbol == "speaker.slash")
    }

    @Test func litSegmentsFollowTheLevelInSixteenths() {
        #expect(StreamVolume(level: 0.5).litSegments == 8)
        #expect(StreamVolume(level: 1).litSegments == 16)
        #expect(StreamVolume(level: 0).litSegments == 0)
    }

    @Test func mutedLightsNoSegments() {
        var muted = StreamVolume(level: 0.5)
        muted.toggleMute()
        #expect(muted.litSegments == 0)
    }

    @Test func announcementNamesTheLevelOrTheMute() {
        #expect(StreamVolume(level: 0.6).announcement == "Stream volume 60 percent")
        var muted = StreamVolume(level: 0.6)
        muted.toggleMute()
        #expect(muted.announcement == "Stream muted")
    }
}
