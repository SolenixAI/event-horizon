//
//  HostOutputTests.swift
//
//  Unit tests for HostOutput data models, JSON decoding, SelectOutputRequest encoding,
//  DisplayMode label formatting, and AppModel persistence.
//

import Foundation
import Testing
@testable import Glimmer

struct HostOutputTests {

    @Test func decodesOutputsPayloadFromLinkApiJson() throws {
        let json = """
        {
          "active_id": "HDMI-A-1",
          "outputs": [
            {
              "id": "virtual",
              "name": "Virtual Screen (Mac Only)",
              "connector": "Virtual-sunshine-vmon",
              "connected": true,
              "enabled": false,
              "is_virtual": true,
              "hdr_supported": false,
              "current_mode": { "width": 2560, "height": 1600, "refresh": 60.0 },
              "modes": [
                { "width": 2560, "height": 1600, "refresh": 60.0 }
              ]
            },
            {
              "id": "HDMI-A-1",
              "name": "LG TV OLED",
              "connector": "HDMI-A-1",
              "connected": true,
              "enabled": true,
              "is_virtual": false,
              "hdr_supported": true,
              "current_mode": { "width": 3840, "height": 2160, "refresh": 120.0 },
              "modes": [
                { "width": 3840, "height": 2160, "refresh": 120.0 },
                { "width": 2560, "height": 1440, "refresh": 120.0 },
                { "width": 1920, "height": 1080, "refresh": 120.0 }
              ]
            }
          ]
        }
        """

        let data = try #require(json.data(using: .utf8))
        let payload = try JSONDecoder().decode(OutputsPayload.self, from: data)

        #expect(payload.activeId == "HDMI-A-1")
        #expect(payload.outputs.count == 2)

        let virtual = payload.outputs[0]
        #expect(virtual.id == "virtual")
        #expect(virtual.name == "Virtual Screen (Mac Only)")
        #expect(virtual.connector == "Virtual-sunshine-vmon")
        #expect(virtual.connected == true)
        #expect(virtual.enabled == false)
        #expect(virtual.isVirtual == true)
        #expect(virtual.hdrSupported == false)
        #expect(virtual.currentMode == DisplayMode(width: 2560, height: 1600, refresh: 60.0))
        #expect(virtual.modes.count == 1)

        let tv = payload.outputs[1]
        #expect(tv.id == "HDMI-A-1")
        #expect(tv.name == "LG TV OLED")
        #expect(tv.connector == "HDMI-A-1")
        #expect(tv.connected == true)
        #expect(tv.enabled == true)
        #expect(tv.isVirtual == false)
        #expect(tv.hdrSupported == true)
        #expect(tv.currentMode == DisplayMode(width: 3840, height: 2160, refresh: 120.0))
        #expect(tv.modes.count == 3)
        #expect(tv.modes[1] == DisplayMode(width: 2560, height: 1440, refresh: 120.0))
    }

    @Test func encodesSelectOutputRequestWithMode() throws {
        let mode = DisplayMode(width: 2560, height: 1440, refresh: 120.0)
        let request = SelectOutputRequest(id: "HDMI-A-1", mode: mode)

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(SelectOutputRequest.self, from: data)

        #expect(decoded.id == "HDMI-A-1")
        #expect(decoded.mode == mode)

        // Verify JSON string structure
        let jsonObject = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(jsonObject["id"] as? String == "HDMI-A-1")
        let modeObj = try #require(jsonObject["mode"] as? [String: Any])
        #expect(modeObj["width"] as? Int == 2560)
        #expect(modeObj["height"] as? Int == 1440)
        #expect(modeObj["refresh"] as? Double == 120.0)
    }

    @Test func encodesSelectOutputRequestWithoutMode() throws {
        let request = SelectOutputRequest(id: "virtual", mode: nil)

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(SelectOutputRequest.self, from: data)

        #expect(decoded.id == "virtual")
        #expect(decoded.mode == nil)
    }

    @Test func displayModeLabelFormatting() {
        let qhd120 = DisplayMode(width: 2560, height: 1440, refresh: 120.0)
        #expect(qhd120.resolutionLabel == "1440p")
        #expect(qhd120.label == "1440p @ 120Hz")

        let uhd60 = DisplayMode(width: 3840, height: 2160, refresh: 60.0)
        #expect(uhd60.resolutionLabel == "4K")
        #expect(uhd60.label == "4K @ 60Hz")

        let fhd144 = DisplayMode(width: 1920, height: 1080, refresh: 143.98)
        #expect(fhd144.resolutionLabel == "1080p")
        #expect(fhd144.label == "1080p @ 144Hz")

        let macRatio = DisplayMode(width: 2560, height: 1600, refresh: 59.94)
        #expect(macRatio.resolutionLabel == "2560×1600")
        #expect(macRatio.label == "2560×1600 @ 60Hz")
    }

    @Test @MainActor func outputDefaultsPersistence() {
        let testHostId = "test-host-uuid-1234"
        let model = AppModel()

        // Clean any leftover test state
        UserDefaults.standard.removeObject(forKey: AppModel.outputDefaultsKey(for: testHostId))
        UserDefaults.standard.removeObject(forKey: AppModel.modeDefaultsKey(for: testHostId))

        #expect(model.loadPersistedOutputId(for: testHostId) == nil)
        #expect(model.loadPersistedMode(for: testHostId) == nil)

        // Save and verify output ID
        model.savePersistedOutputId("HDMI-A-1", for: testHostId)
        #expect(model.loadPersistedOutputId(for: testHostId) == "HDMI-A-1")

        // Save and verify display mode
        let mode = DisplayMode(width: 3840, height: 2160, refresh: 120.0)
        model.savePersistedMode(mode, for: testHostId)
        #expect(model.loadPersistedMode(for: testHostId) == mode)

        // Clear display mode
        model.savePersistedMode(nil, for: testHostId)
        #expect(model.loadPersistedMode(for: testHostId) == nil)

        // Clean up
        UserDefaults.standard.removeObject(forKey: AppModel.outputDefaultsKey(for: testHostId))
        UserDefaults.standard.removeObject(forKey: AppModel.modeDefaultsKey(for: testHostId))
    }

    @Test @MainActor func outputsFallbackAndActiveOutputSelection() {
        let host = Host(
            id: "host-test-id",
            name: "Gaming-Rig",
            customName: nil,
            localAddress: "192.168.1.100",
            manualAddress: nil,
            apps: [],
            lastConnected: nil,
            serverCertPEM: nil,
            appVersion: nil,
            macAddress: nil
        )

        let model = AppModel()

        // No outputs loaded yet -> should fall back to defaultVirtual
        let defaultOutputs = model.outputs(for: host)
        #expect(defaultOutputs.count == 1)
        #expect(defaultOutputs[0].id == "virtual")
        #expect(defaultOutputs[0].isVirtual == true)

        let active = model.activeOutput(for: host)
        #expect(active?.id == "virtual")

        // Provide discovered outputs
        let tvOutput = HostOutput(
            id: "HDMI-A-1",
            name: "LG OLED C2",
            connector: "HDMI-A-1",
            connected: true,
            enabled: true,
            isVirtual: false,
            hdrSupported: true,
            currentMode: DisplayMode(width: 3840, height: 2160, refresh: 120.0),
            modes: [
                DisplayMode(width: 3840, height: 2160, refresh: 120.0),
                DisplayMode(width: 2560, height: 1440, refresh: 120.0)
            ]
        )

        model.hostOutputs[host.id] = [HostOutput.defaultVirtual, tvOutput]
        #expect(model.outputs(for: host).count == 2)

        // Without explicit active ID, falls back to virtual
        #expect(model.activeOutput(for: host)?.id == "virtual")

        // Set active ID to TV
        model.activeHostOutputId[host.id] = "HDMI-A-1"
        #expect(model.activeOutput(for: host)?.id == "HDMI-A-1")
        #expect(model.activeOutput(for: host)?.name == "LG OLED C2")
    }

    @Test func deskOutputPickerIcons() {
        let virtual = HostOutput(id: "v1", name: "Virtual Screen", connector: "Virtual-sunshine-vmon", isVirtual: true)
        #expect(DeskOutputPicker.iconName(for: virtual) == "laptopcomputer")

        let lgTv = HostOutput(id: "tv1", name: "LG TV OLED", connector: "HDMI-A-1", isVirtual: false)
        #expect(DeskOutputPicker.iconName(for: lgTv) == "tv")

        let samsungTv = HostOutput(id: "tv2", name: "Living Room TV", connector: "DP-1", isVirtual: false)
        #expect(DeskOutputPicker.iconName(for: samsungTv) == "tv")

        let hdmiMonitor = HostOutput(id: "mon1", name: "Desk Monitor", connector: "HDMI-2", isVirtual: false)
        #expect(DeskOutputPicker.iconName(for: hdmiMonitor) == "tv")

        let dpMonitor = HostOutput(id: "mon2", name: "Dell Ultrasharp", connector: "DP-2", isVirtual: false)
        #expect(DeskOutputPicker.iconName(for: dpMonitor) == "display")
    }

    @Test func deskOutputPickerShortName() {
        let virtual = HostOutput(id: "v", name: "Virtual Screen (Mac Only)", connector: "vmon", isVirtual: true)
        #expect(DeskOutputPicker.shortName(for: virtual) == "Virtual Screen")

        let standard = HostOutput(id: "tv", name: "LG TV OLED", connector: "HDMI-A-1")
        #expect(DeskOutputPicker.shortName(for: standard) == "LG TV OLED")

        let longNamed = HostOutput(id: "long", name: "LG Electronics Inc. OLED65C2PUA Ultra HD", connector: "HDMI-1")
        #expect(DeskOutputPicker.shortName(for: longNamed).hasSuffix("…"))
    }

    @Test func deskOutputPickerModeTitle() {
        let nativeMode = DisplayMode(width: 3840, height: 2160, refresh: 120.0)
        #expect(DeskOutputPicker.modeTitle(nativeMode, isNative: true) == "4K @ 120Hz · Native")

        let qhd = DisplayMode(width: 2560, height: 1440, refresh: 120.0)
        #expect(DeskOutputPicker.modeTitle(qhd, isNative: false) == "1440p @ 120Hz · 1440p")

        let fhd = DisplayMode(width: 1920, height: 1080, refresh: 60.0)
        #expect(DeskOutputPicker.modeTitle(fhd, isNative: false) == "1080p @ 60Hz · 1080p")
    }

    @Test @MainActor func activeModeResolution() {
        let host = Host(
            id: "host-mode-test",
            name: "Rig",
            customName: nil,
            localAddress: "192.168.1.50",
            manualAddress: nil,
            apps: [],
            lastConnected: nil,
            serverCertPEM: nil,
            appVersion: nil,
            macAddress: nil
        )
        let model = AppModel()

        let mode4k = DisplayMode(width: 3840, height: 2160, refresh: 120.0)
        let mode1440p = DisplayMode(width: 2560, height: 1440, refresh: 120.0)

        let out = HostOutput(
            id: "HDMI-A-1",
            name: "TV",
            connector: "HDMI-A-1",
            currentMode: mode4k,
            modes: [mode4k, mode1440p]
        )
        model.hostOutputs[host.id] = [out]
        model.activeHostOutputId[host.id] = "HDMI-A-1"

        // Default should be currentMode
        #expect(model.activeMode(for: host) == mode4k)

        // Setting explicit selection overrides
        model.selectedHostMode[host.id] = mode1440p
        #expect(model.activeMode(for: host) == mode1440p)
    }

    @Test @MainActor func disconnectWhenIdleIsNoop() async {
        let model = AppModel()
        #expect(!model.isStreaming)
        await model.disconnect()
        #expect(!model.isStreaming)
    }

    @Test @MainActor func defaultVirtualExposesCuratedModesAndPersistsSelection() async {
        let virtual = HostOutput.defaultVirtual
        #expect(virtual.modes.count == 10)
        #expect(virtual.modes.contains(DisplayMode(width: 2560, height: 1600, refresh: 120.0)))
        #expect(virtual.modes.contains(DisplayMode(width: 2560, height: 1600, refresh: 90.0)))
        #expect(virtual.modes.contains(DisplayMode(width: 2560, height: 1600, refresh: 60.0)))
        #expect(virtual.modes.contains(DisplayMode(width: 1920, height: 1080, refresh: 120.0)))

        let hostId = "virtual-mode-persist-\(UUID().uuidString)"
        let host = Host(
            id: hostId,
            name: "Virtual-Host",
            customName: nil,
            localAddress: nil,
            manualAddress: nil,
            apps: [],
            lastConnected: nil,
            serverCertPEM: nil,
            appVersion: nil,
            macAddress: nil
        )
        let savedPreset = UserDefaults.standard.string(forKey: "qualityPreset")
        let savedFPS = UserDefaults.standard.object(forKey: "customFPS")
        defer {
            UserDefaults.standard.removeObject(forKey: AppModel.outputDefaultsKey(for: hostId))
            UserDefaults.standard.removeObject(forKey: AppModel.modeDefaultsKey(for: hostId))
            if let savedPreset {
                UserDefaults.standard.set(savedPreset, forKey: "qualityPreset")
            } else {
                UserDefaults.standard.removeObject(forKey: "qualityPreset")
            }
            if let savedFPS {
                UserDefaults.standard.set(savedFPS, forKey: "customFPS")
            } else {
                UserDefaults.standard.removeObject(forKey: "customFPS")
            }
        }

        let model = AppModel()
        let presetBefore = model.qualityPreset
        let mode = DisplayMode(width: 2560, height: 1600, refresh: 90.0)
        _ = await model.selectOutput(host: host, outputId: "virtual", mode: mode)

        #expect(model.activeHostOutputId[hostId] == "virtual")
        #expect(model.selectedHostMode[hostId] == mode)
        #expect(model.loadPersistedMode(for: hostId) == mode)
        #expect(model.customFPS == 90)
        #expect(model.qualityPreset == presetBefore)
    }
}
