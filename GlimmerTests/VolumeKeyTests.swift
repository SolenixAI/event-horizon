//
//  VolumeKeyTests.swift
//
//  The Mac's volume keys: decoding a system-defined key event, and applying a key to the stream's level.
//

import Testing
@testable import Glimmer

struct VolumeKeyTests {

    /// The data1 word a system-defined media key carries: key type, state (0xA down, 0xB up), repeat bit.
    private func data1(type: Int, down: Bool, repeating: Bool = false) -> Int {
        (type << 16) | ((down ? 0xA : 0xB) << 8) | (repeating ? 1 : 0)
    }

    @Test func keyDownDecodesToTheMatchingVolumeKey() {
        #expect(VolumeKey.decode(subtype: 8, data1: data1(type: 0, down: true)) == .up)
        #expect(VolumeKey.decode(subtype: 8, data1: data1(type: 1, down: true)) == .down)
        #expect(VolumeKey.decode(subtype: 8, data1: data1(type: 7, down: true)) == .mute)
    }

    @Test func keyUpIsNotAKeyPress() {
        #expect(VolumeKey.decode(subtype: 8, data1: data1(type: 0, down: false)) == nil)
    }

    @Test func aRepeatedKeyDownStillCounts() {
        #expect(VolumeKey.decode(subtype: 8, data1: data1(type: 0, down: true, repeating: true)) == .up)
    }

    @Test func otherMediaKeysAndOtherEventsAreIgnored() {
        #expect(VolumeKey.decode(subtype: 8, data1: data1(type: 2, down: true)) == nil)
        #expect(VolumeKey.decode(subtype: 7, data1: data1(type: 0, down: true)) == nil)
    }

    @Test func aVolumeKeyStepsTheStreamLevel() {
        var volume = StreamVolume(level: 0.5)
        volume.apply(.up)
        #expect(volume.level == 0.5625)
        volume.apply(.down)
        volume.apply(.down)
        #expect(volume.level == 0.4375)
    }

    @Test func theMuteKeyTogglesTheStreamMute() {
        var volume = StreamVolume(level: 0.4)
        volume.apply(.mute)
        #expect(volume.isMuted)
        volume.apply(.mute)
        #expect(!volume.isMuted)
        #expect(volume.level == 0.4)
    }
}
