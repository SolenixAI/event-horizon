//
//  AppModel+Audio.swift
//
//  Builds before 2026.9.7 muted by zeroing the system volume. A Mac that crashed
//  mid-stream on one gets its level back at the next launch. Delete next release.
//

import AudioToolbox
import CoreAudio
import Foundation

/// The output that was muted: its UID (stable across relaunches) and level.
struct MutedOutput: Codable, Equatable {
    let uid: String
    let volume: Float
}

extension AppModel {
    nonisolated static let mutePendingRestoreKey = "muteMacPendingRestore"

    /// Launch-time recovery for a session that died while muted. The record
    /// is consumed either way, so a vanished device can't retry forever.
    nonisolated static func restoreOrphanedMute(in defaults: UserDefaults = .standard) {
        guard let output = pendingRestore(in: defaults) else { return }
        defaults.removeObject(forKey: mutePendingRestoreKey)
        guard let device = deviceID(forUID: output.uid) else { return }
        setVolume(output.volume, of: device)
        Diag.notice("Audio: restored the output muted by a session that ended early", "Launch")
    }

    nonisolated static func pendingRestore(in defaults: UserDefaults = .standard) -> MutedOutput? {
        guard let data = defaults.data(forKey: mutePendingRestoreKey) else { return nil }
        return try? JSONDecoder().decode(MutedOutput.self, from: data)
    }

    // MARK: CoreAudio

    private nonisolated static func deviceID(forUID uid: String) -> AudioObjectID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cfUID = uid as CFString
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let st = withUnsafeMutablePointer(to: &cfUID) { qualifier in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                       UInt32(MemoryLayout<CFString>.size), qualifier, &size, &device)
        }
        guard st == noErr, device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return device
    }

    // The "virtual main volume" property models the single user-facing output
    // level even on devices whose hardware exposes only per-channel volume.
    private nonisolated static func setVolume(_ volume: Float, of device: AudioObjectID) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &addr) else { return }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &addr, &settable) == noErr, settable.boolValue else { return }
        var level = Float32(max(0, min(1, volume)))
        let size = UInt32(MemoryLayout<Float32>.size)
        _ = AudioObjectSetPropertyData(device, &addr, 0, nil, size, &level)
    }
}

extension AppModel {
    func audioDevices(for host: Host) -> [HostAudioDevice] {
        hostAudioDevices[host.id] ?? []
    }

    func activeAudioDevice(for host: Host) -> HostAudioDevice? {
        let devices = audioDevices(for: host)
        let activeId = activeHostAudioId[host.id]
        return devices.first(where: { $0.id == activeId })
            ?? devices.first(where: { $0.isDefault })
            ?? devices.first
    }

    func refreshAudioDevices(for host: Host) async {
        guard let token = CompanionTokens.token(forHost: host.id),
              let address = host.manualAddress ?? host.localAddress
        else { return }

        let companion = CompanionClient(
            address: address,
            pinned: CompanionTokens.fingerprint(forHost: host.id)
        )
        guard let payload = await companion.audioDevices(token: token) else { return }
        hostAudioDevices[host.id] = payload.devices
        activeHostAudioId[host.id] = payload.activeId
    }

    @discardableResult
    func selectAudioDevice(host: Host, deviceId: String) async -> Bool {
        guard let token = CompanionTokens.token(forHost: host.id),
              let address = host.manualAddress ?? host.localAddress
        else { return false }

        let companion = CompanionClient(
            address: address,
            pinned: CompanionTokens.fingerprint(forHost: host.id)
        )
        let ok = await companion.selectAudioDevice(token: token, id: deviceId)
        if ok {
            activeHostAudioId[host.id] = deviceId
            if let existing = hostAudioDevices[host.id] {
                hostAudioDevices[host.id] = existing.map {
                    HostAudioDevice(
                        id: $0.id,
                        name: $0.name,
                        isVirtual: $0.isVirtual,
                        isDefault: $0.id == deviceId
                    )
                }
            }
        }
        return ok
    }
}
