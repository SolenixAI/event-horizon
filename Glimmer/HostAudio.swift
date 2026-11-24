//
//  HostAudio.swift
//
//  Audio output device models for host PC sound sinks (virtual stream sink and physical speakers/headsets).
//

import Foundation

/// An audio output sink available on the host PC.
struct HostAudioDevice: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let isVirtual: Bool
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isVirtual = "is_virtual"
        case isDefault = "is_default"
    }

    init(
        id: String,
        name: String,
        isVirtual: Bool = false,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isVirtual = isVirtual
        self.isDefault = isDefault
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isVirtual = try container.decodeIfPresent(Bool.self, forKey: .isVirtual) ?? false
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }
}

/// The list of discovered host audio output devices and the currently active default sink ID.
struct AudioPayload: Codable, Equatable, Sendable {
    let activeId: String
    let devices: [HostAudioDevice]

    enum CodingKeys: String, CodingKey {
        case activeId = "active_id"
        case devices
    }
}

/// Request payload for selecting an audio output device on the host PC.
struct SelectAudioRequest: Codable, Equatable, Sendable {
    let id: String
}
