//
//  StreamVolumePresentation.swift
//
//  How the stream volume reads on screen and to VoiceOver: one glyph, the lit segments, one announcement.
//

import Foundation

extension StreamVolume {
    /// One segment per key step, like the Mac's own volume bar.
    static let segmentCount = 16

    /// The speaker glyph for the level, and a slashed one while muted or silent.
    var symbol: String {
        if gain == 0 { return "speaker.slash" }
        switch gain {
        case ..<0.34: return "speaker.wave.1"
        case ..<0.67: return "speaker.wave.2"
        default: return "speaker.wave.3"
        }
    }

    /// How many segments light up: none while muted.
    var litSegments: Int { Int((gain / Self.step).rounded()) }

    /// What a control's value says: a percentage, or "Muted".
    var spokenLevel: String {
        if isMuted { return "Muted" }
        return "\(percent) percent"
    }

    /// What VoiceOver announces when the level or the mute changes.
    var announcement: String {
        isMuted ? "Stream muted" : "Stream volume \(percent) percent"
    }

    private var percent: Int { Int((level * 100).rounded()) }
}
