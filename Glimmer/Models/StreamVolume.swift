//
//  StreamVolume.swift
//
//  The stream's own gain, separate from the Mac's volume: sixteen steps, mute keeps the level.
//

import Foundation

struct StreamVolume: Codable, Equatable {
    /// One press of a volume key: sixteen steps from silence to full.
    static let step = 1.0 / 16.0
    static let defaultsKey = "streamVolume"
    static let full = StreamVolume()

    private(set) var level: Double
    private(set) var isMuted: Bool
    /// The last level above zero. An unmute returns to it when the level is silent.
    private(set) var lastAudible: Double

    init(level: Double = 1, isMuted: Bool = false, lastAudible: Double? = nil) {
        let clamped = min(1, max(0, level))
        self.level = clamped
        self.isMuted = isMuted
        self.lastAudible = clamped > 0 ? clamped : min(1, max(0, lastAudible ?? 1))
    }

    init(from decoder: Decoder) throws {
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        self.init(level: try saved.decode(Double.self, forKey: .level),
                  isMuted: try saved.decode(Bool.self, forKey: .isMuted),
                  lastAudible: try saved.decode(Double.self, forKey: .lastAudible))
    }

    /// The gain the engine plays at: silence while muted, the level otherwise.
    var gain: Double { isMuted ? 0 : level }

    /// Sets the level. Anything above silence unmutes, as the Mac's own slider does.
    mutating func setLevel(_ value: Double) {
        let level = min(1, max(0, value))
        self = StreamVolume(level: level, isMuted: isMuted && level == 0, lastAudible: lastAudible)
    }

    /// One key press up: unmutes, as the Mac's keys do, then rises one step.
    mutating func stepUp() {
        let next = min(1, ((level / Self.step).rounded(.down) + 1) * Self.step)
        self = StreamVolume(level: next, isMuted: false, lastAudible: lastAudible)
    }

    /// One key press down: falls one step, and stays muted if it was.
    mutating func stepDown() {
        let next = max(0, ((level / Self.step).rounded(.up) - 1) * Self.step)
        self = StreamVolume(level: next, isMuted: isMuted, lastAudible: lastAudible)
    }

    /// A volume key: up and down step the level, mute toggles the mute.
    mutating func apply(_ key: VolumeKey) {
        switch key {
        case .up: stepUp()
        case .down: stepDown()
        case .mute: toggleMute()
        }
    }

    /// Mutes or unmutes. An unmute from a silent level returns to the last audible one.
    mutating func toggleMute() {
        let unmuting = isMuted
        let restored = unmuting && level == 0 ? lastAudible : level
        self = StreamVolume(level: restored, isMuted: !isMuted, lastAudible: lastAudible)
    }

    // MARK: Saved across launches

    static func load(from defaults: UserDefaults) -> StreamVolume {
        guard let data = defaults.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode(StreamVolume.self, from: data) else { return .full }
        return saved
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private enum CodingKeys: String, CodingKey { case level, isMuted, lastAudible }
}
