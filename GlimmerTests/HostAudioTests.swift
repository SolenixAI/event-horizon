//
//  HostAudioTests.swift
//
//  Unit tests for host PC audio output decoding, Event Horizon Audio branding, and AppModel selection.
//

import Foundation
import Testing
@testable import Glimmer

@Suite struct HostAudioTests {
    @Test func decodeAudioPayloadMatchesCompanionWireContract() throws {
        let json = """
        {
          "active_id": "sink-sunshine-stereo",
          "devices": [
            {
              "id": "sink-sunshine-stereo",
              "name": "Event Horizon Audio",
              "is_virtual": true,
              "is_default": true
            },
            {
              "id": "alsa_output.usb-SteelSeries_Arctis-00.analog-stereo",
              "name": "Arctis Nova Pro Wireless",
              "is_virtual": false,
              "is_default": false
            }
          ]
        }
        """

        let payload = try JSONDecoder().decode(AudioPayload.self, from: Data(json.utf8))
        #expect(payload.activeId == "sink-sunshine-stereo")
        #expect(payload.devices.count == 2)
        #expect(payload.devices[0].name == "Event Horizon Audio")
        #expect(payload.devices[0].isVirtual == true)
        #expect(payload.devices[0].isDefault == true)
        #expect(payload.devices[1].name == "Arctis Nova Pro Wireless")
        #expect(payload.devices[1].isVirtual == false)
    }

    @Test @MainActor func appModelAudioDevicesAndActiveDeviceResolution() {
        let host = Host(
            id: "host-audio-test",
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
        #expect(model.audioDevices(for: host).isEmpty)
        #expect(model.activeAudioDevice(for: host) == nil)

        let virtual = HostAudioDevice(
            id: "sink-sunshine-stereo",
            name: "Event Horizon Audio",
            isVirtual: true,
            isDefault: false
        )
        let speakers = HostAudioDevice(
            id: "alsa_output.pci.stereo",
            name: "Desk Speakers",
            isVirtual: false,
            isDefault: true
        )

        model.hostAudioDevices[host.id] = [virtual, speakers]
        #expect(model.activeAudioDevice(for: host)?.id == speakers.id)

        model.activeHostAudioId[host.id] = virtual.id
        #expect(model.activeAudioDevice(for: host)?.id == virtual.id)
    }
}
