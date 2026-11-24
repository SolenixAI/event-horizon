//
//  AppModel+Outputs.swift
//
//  Host output discovery, output selection, and display mode persistence.
//

import Foundation

/// Status of host companion output queries for diagnostic UI and fallback handling.
enum CompanionOutputStatus: Equatable, Sendable {
    case idle
    case loading
    case ready(outputs: [HostOutput])
    case companionUpdateRequired(hostName: String)
    case unauthorized(hostName: String)
    case unreachable(hostName: String)
}

extension AppModel {

    // MARK: - Defaults Keys

    static func outputDefaultsKey(for hostID: String) -> String {
        "hostOutput.\(hostID).activeId"
    }

    static func modeDefaultsKey(for hostID: String) -> String {
        "hostOutput.\(hostID).selectedMode"
    }

    // MARK: - Persistence Helpers

    func loadPersistedOutputId(for hostID: String) -> String? {
        UserDefaults.standard.string(forKey: Self.outputDefaultsKey(for: hostID))
    }

    func savePersistedOutputId(_ outputId: String, for hostID: String) {
        UserDefaults.standard.set(outputId, forKey: Self.outputDefaultsKey(for: hostID))
    }

    func loadPersistedMode(for hostID: String) -> DisplayMode? {
        guard let data = UserDefaults.standard.data(forKey: Self.modeDefaultsKey(for: hostID)) else { return nil }
        return try? JSONDecoder().decode(DisplayMode.self, from: data)
    }

    func savePersistedMode(_ mode: DisplayMode?, for hostID: String) {
        let key = Self.modeDefaultsKey(for: hostID)
        guard let mode else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(mode) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Query Accessors

    /// Whether the host companion requires an update to support display outputs.
    func isCompanionUpdateRequired(for host: Host) -> Bool {
        if case .companionUpdateRequired = companionOutputStatus[host.id] {
            return true
        }
        return false
    }

    /// Discovered outputs for this host, falling back to a default virtual display if none discovered yet.
    func outputs(for host: Host) -> [HostOutput] {
        let list = hostOutputs[host.id] ?? []
        return list.isEmpty ? [HostOutput.defaultVirtual] : list
    }

    /// Currently active output for this host.
    func activeOutput(for host: Host) -> HostOutput? {
        let available = outputs(for: host)
        let targetId = activeHostOutputId[host.id] ?? loadPersistedOutputId(for: host.id) ?? "virtual"
        return available.first(where: { $0.id == targetId })
            ?? available.first(where: { $0.isVirtual })
            ?? available.first
    }

    /// Currently selected display mode for this host.
    func activeMode(for host: Host) -> DisplayMode? {
        selectedHostMode[host.id]
            ?? loadPersistedMode(for: host.id)
            ?? activeOutput(for: host)?.currentMode
            ?? activeOutput(for: host)?.modes.first
    }

    // MARK: - Network Operations

    /// Refreshes the list of display outputs and current active output from the host companion.
    func refreshOutputs(for host: Host) async {
        guard let token = CompanionTokens.token(forHost: host.id),
              let address = host.manualAddress ?? host.localAddress
        else {
            companionOutputStatus[host.id] = .unreachable(hostName: host.name)
            fallbackActiveOutputAndMode(for: host)
            return
        }

        companionOutputStatus[host.id] = .loading

        let companion = CompanionClient(
            address: address,
            pinned: CompanionTokens.fingerprint(forHost: host.id)
        )

        let result = await companion.outputsResult(token: token)
        switch result {
        case .success(let payload):
            companionOutputStatus[host.id] = .ready(outputs: payload.outputs)
            hostOutputs[host.id] = payload.outputs
            activeHostOutputId[host.id] = payload.activeId
            savePersistedOutputId(payload.activeId, for: host.id)
            reconcileSelectedMode(for: host, payload: payload)

        case .unsupportedApi:
            companionOutputStatus[host.id] = .companionUpdateRequired(hostName: host.name)
            fallbackActiveOutputAndMode(for: host)

        case .unauthorized:
            companionOutputStatus[host.id] = .unauthorized(hostName: host.name)
            fallbackActiveOutputAndMode(for: host)

        case .unreachable:
            companionOutputStatus[host.id] = .unreachable(hostName: host.name)
            fallbackActiveOutputAndMode(for: host)
        }
    }

    private func fallbackActiveOutputAndMode(for host: Host) {
        if activeHostOutputId[host.id] == nil {
            activeHostOutputId[host.id] = loadPersistedOutputId(for: host.id) ?? "virtual"
        }
        if selectedHostMode[host.id] == nil {
            selectedHostMode[host.id] = loadPersistedMode(for: host.id)
        }
    }

    private func reconcileSelectedMode(for host: Host, payload: OutputsPayload) {
        let active = payload.outputs.first(where: { $0.id == payload.activeId })
        if let savedMode = loadPersistedMode(for: host.id),
           let active,
           active.modes.isEmpty || active.modes.contains(where: {
               $0.width == savedMode.width && $0.height == savedMode.height
           }) {
            selectedHostMode[host.id] = savedMode
        } else if let active, let current = active.currentMode {
            selectedHostMode[host.id] = current
            savePersistedMode(current, for: host.id)
        } else if let first = active?.modes.first {
            selectedHostMode[host.id] = first
            savePersistedMode(first, for: host.id)
        }
    }

    /// Disconnects the active stream session if currently streaming.
    func disconnect() async {
        guard isStreaming else { return }
        stopStreamFromMenu(source: "Output Switch")
        for _ in 0..<100 where isStreaming {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Selects an active display output on the host PC and optionally applies a display mode.
    @discardableResult
    func selectOutput(host: Host, outputId: String, mode: DisplayMode?) async -> Bool {
        guard let token = CompanionTokens.token(forHost: host.id),
              let address = host.manualAddress ?? host.localAddress
        else {
            activeHostOutputId[host.id] = outputId
            savePersistedOutputId(outputId, for: host.id)
            if let mode {
                selectedHostMode[host.id] = mode
                savePersistedMode(mode, for: host.id)
                syncStreamFPS(for: mode)
            } else {
                let out = hostOutputs[host.id]?.first(where: { $0.id == outputId })
                if let current = out?.currentMode ?? out?.modes.first {
                    selectedHostMode[host.id] = current
                    savePersistedMode(current, for: host.id)
                }
            }
            return false
        }

        let companion = CompanionClient(
            address: address,
            pinned: CompanionTokens.fingerprint(forHost: host.id)
        )

        let success = await companion.selectOutput(token: token, id: outputId, mode: mode)
        if success {
            activeHostOutputId[host.id] = outputId
            savePersistedOutputId(outputId, for: host.id)

            if let mode {
                selectedHostMode[host.id] = mode
                savePersistedMode(mode, for: host.id)
                syncStreamFPS(for: mode)
            } else {
                let out = hostOutputs[host.id]?.first(where: { $0.id == outputId })
                if let current = out?.currentMode ?? out?.modes.first {
                    selectedHostMode[host.id] = current
                    savePersistedMode(current, for: host.id)
                }
            }
        }
        return success
    }

    private func syncStreamFPS(for mode: DisplayMode) {
        let hz = StreamSizeBounds.clampFPS(Int(mode.refresh.rounded()))
        if customFPS != hz {
            customFPS = hz
        }
    }
}

extension HostOutput {
    /// Curated resolution and refresh presets for the virtual screen.
    static let virtualCuratedModes: [DisplayMode] = [
        DisplayMode(width: 2560, height: 1600, refresh: 120.0),
        DisplayMode(width: 2560, height: 1600, refresh: 90.0),
        DisplayMode(width: 2560, height: 1600, refresh: 60.0),
        DisplayMode(width: 2560, height: 1440, refresh: 120.0),
        DisplayMode(width: 2560, height: 1440, refresh: 90.0),
        DisplayMode(width: 2560, height: 1440, refresh: 60.0),
        DisplayMode(width: 1920, height: 1200, refresh: 120.0),
        DisplayMode(width: 1920, height: 1200, refresh: 60.0),
        DisplayMode(width: 1920, height: 1080, refresh: 120.0),
        DisplayMode(width: 1920, height: 1080, refresh: 60.0)
    ]

    /// Default virtual screen fallback output when PC has not reported outputs.
    static let defaultVirtual = HostOutput(
        id: "virtual",
        name: "Virtual Screen (Mac Only)",
        connector: "Virtual-sunshine-vmon",
        connected: true,
        enabled: false,
        isVirtual: true,
        hdrSupported: false,
        currentMode: nil,
        modes: virtualCuratedModes
    )
}
