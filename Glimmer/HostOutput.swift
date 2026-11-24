//
//  HostOutput.swift
//
//  Output device models for host displays (virtual screen and physical monitors/TVs).
//

import Foundation

/// A display resolution and refresh rate supported by an output.
struct DisplayMode: Codable, Equatable, Sendable, Hashable {
    let width: Int
    let height: Int
    let refresh: Double

    init(width: Int, height: Int, refresh: Double) {
        self.width = width
        self.height = height
        self.refresh = refresh
    }

    /// Formats resolution into standard shorthand ("1080p", "1440p", "4K", etc.) or "W×H".
    var resolutionLabel: String {
        switch (width, height) {
        case (7680, 4320): return "8K"
        case (5120, 2880): return "5K"
        case (3840, 2160): return "4K"
        case (2560, 1440): return "1440p"
        case (1920, 1080): return "1080p"
        case (1280, 720): return "720p"
        default: return "\(width)×\(height)"
        }
    }

    /// User-facing label, e.g. "1440p @ 120Hz" or "2560×1600 @ 60Hz".
    var label: String {
        "\(resolutionLabel) @ \(Int(refresh.rounded()))Hz"
    }
}

/// A physical or virtual display connected to the host PC.
struct HostOutput: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let connector: String
    let connected: Bool
    let enabled: Bool
    let isVirtual: Bool
    let hdrSupported: Bool
    let currentMode: DisplayMode?
    let modes: [DisplayMode]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case connector
        case connected
        case enabled
        case isVirtual = "is_virtual"
        case hdrSupported = "hdr_supported"
        case currentMode = "current_mode"
        case modes
    }

    init(
        id: String,
        name: String,
        connector: String,
        connected: Bool = true,
        enabled: Bool = false,
        isVirtual: Bool = false,
        hdrSupported: Bool = false,
        currentMode: DisplayMode? = nil,
        modes: [DisplayMode] = []
    ) {
        self.id = id
        self.name = name
        self.connector = connector
        self.connected = connected
        self.enabled = enabled
        self.isVirtual = isVirtual
        self.hdrSupported = hdrSupported
        self.currentMode = currentMode
        self.modes = modes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        connector = try container.decode(String.self, forKey: .connector)
        connected = try container.decodeIfPresent(Bool.self, forKey: .connected) ?? true
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        isVirtual = try container.decodeIfPresent(Bool.self, forKey: .isVirtual) ?? false
        hdrSupported = try container.decodeIfPresent(Bool.self, forKey: .hdrSupported) ?? false
        currentMode = try container.decodeIfPresent(DisplayMode.self, forKey: .currentMode)
        modes = try container.decodeIfPresent([DisplayMode].self, forKey: .modes) ?? []
    }
}

/// The list of discovered host outputs and the currently active output ID.
struct OutputsPayload: Codable, Equatable, Sendable {
    let activeId: String
    let outputs: [HostOutput]

    enum CodingKeys: String, CodingKey {
        case activeId = "active_id"
        case outputs
    }

    init(activeId: String, outputs: [HostOutput]) {
        self.activeId = activeId
        self.outputs = outputs
    }
}

/// Request payload for selecting an output device and optional mode.
struct SelectOutputRequest: Codable, Equatable, Sendable {
    let id: String
    let mode: DisplayMode?

    enum CodingKeys: String, CodingKey {
        case id
        case mode
    }

    init(id: String, mode: DisplayMode? = nil) {
        self.id = id
        self.mode = mode
    }
}
