//
//  DynamicOutputsE2ETests.swift
//
//  Automated Multi-Display End-to-End Proof Harness.
//  Spins up a lightweight mock TLS companion server on loopback to verify
//  host output discovery, active output resolution, mode resolution,
//  and output switching without requiring physical display hardware.
//

import Foundation
import Network
import Security
import Testing
@testable import Glimmer

// MARK: - Test Suite

@Suite struct DynamicOutputsE2ETests {

    static let rustSerdeWireJson = """
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
          "current_mode": null,
          "modes": []
        },
        {
          "id": "HDMI-A-1",
          "name": "LG TV OLED55",
          "connector": "HDMI-A-1",
          "connected": true,
          "enabled": true,
          "is_virtual": false,
          "hdr_supported": true,
          "current_mode": { "width": 3840, "height": 2160, "refresh": 120.0 },
          "modes": [
            { "width": 3840, "height": 2160, "refresh": 120.0 },
            { "width": 2560, "height": 1440, "refresh": 120.0 }
          ]
        },
        {
          "id": "DP-1",
          "name": "Desk Monitor (ROG PG279Q)",
          "connector": "DP-1",
          "connected": true,
          "enabled": false,
          "is_virtual": false,
          "hdr_supported": false,
          "current_mode": { "width": 2560, "height": 1440, "refresh": 144.0 },
          "modes": [
            { "width": 2560, "height": 1440, "refresh": 144.0 }
          ]
        }
      ]
    }
    """

    /// 1. Parsing and state hydration:
    ///    When an OutputsPayload fixture containing [Virtual Screen, LG TV OLED55 (HDMI-A-1), Desk Monitor ROG PG279Q (DP-1)]
    ///    is fetched over loopback TLS, model.outputs(for: host) contains exactly 3 displays.
    /// 2. Active output resolution:
    ///    When active ID is HDMI-A-1, model.activeOutput(for: host) resolves to LG TV OLED55.
    /// 3. Output switching:
    ///    Calling model.selectOutput with DP-1 changes active output to Desk Monitor ROG PG279Q.
    /// 4. Mode resolution:
    ///    Resolving model.activeMode returns the selected or active mode (e.g. 1440p @ 120Hz, 1440p @ 144Hz, 4K @ 120Hz).
    @Test @MainActor func endToEndMultiDisplayDiscoveryAndSwitching() async throws {
        let server = try await MockCompanionServer.start()
        defer {
            server.stop()
            CompanionClient.port = 47970
        }
        CompanionClient.port = server.port

        let hostId = "e2e-multi-display-\(UUID().uuidString)"
        let host = Host(
            id: hostId,
            name: "Zephyr-Citadel",
            customName: nil,
            localAddress: "127.0.0.1",
            manualAddress: nil,
            apps: [],
            lastConnected: nil,
            serverCertPEM: server.certPEM,
            appVersion: nil,
            macAddress: nil
        )

        let testToken = "test-e2e-token-\(UUID().uuidString)"
        CompanionTokens.save(testToken, fingerprint: server.fingerprint, forHost: host.id)
        defer {
            CompanionTokens.delete(forHost: host.id)
            UserDefaults.standard.removeObject(forKey: AppModel.outputDefaultsKey(for: host.id))
            UserDefaults.standard.removeObject(forKey: AppModel.modeDefaultsKey(for: host.id))
        }

        let model = AppModel()

        // 1. Parsing and state hydration
        await model.refreshOutputs(for: host)
        assertHydratedOutputs(model.outputs(for: host))

        // 2. Active output resolution (HDMI-A-1 by default in fixture)
        #expect(model.activeHostOutputId[host.id] == "HDMI-A-1")
        let active = model.activeOutput(for: host)
        #expect(active?.id == "HDMI-A-1")
        #expect(active?.name == "LG TV OLED55")

        // 4a. Active mode resolution: defaults to output's currentMode
        let activeMode = model.activeMode(for: host)
        #expect(activeMode == DisplayMode(width: 3840, height: 2160, refresh: 120.0))

        // 3. Output switching: Select Desk Monitor DP-1
        let switchSuccess = await model.selectOutput(host: host, outputId: "DP-1", mode: nil)
        #expect(switchSuccess == true)
        #expect(model.activeHostOutputId[host.id] == "DP-1")
        #expect(model.activeOutput(for: host)?.name == "Desk Monitor (ROG PG279Q)")
        #expect(model.loadPersistedOutputId(for: host.id) == "DP-1")

        // Active mode should update to DP-1's default mode (1440p @ 144Hz)
        #expect(model.activeMode(for: host) == DisplayMode(width: 2560, height: 1440, refresh: 144.0))

        // 4b. Explicit mode selection: Downscale LG TV to 1440p @ 120Hz
        let qhd120 = DisplayMode(width: 2560, height: 1440, refresh: 120.0)
        let modeSwitchSuccess = await model.selectOutput(host: host, outputId: "HDMI-A-1", mode: qhd120)
        #expect(modeSwitchSuccess == true)
        #expect(model.activeHostOutputId[host.id] == "HDMI-A-1")
        #expect(model.activeMode(for: host) == qhd120)
        #expect(model.loadPersistedMode(for: host.id) == qhd120)

        // Verify request reached server with correct wire payload
        #expect(server.lastSelectRequest?.id == "HDMI-A-1")
        #expect(server.lastSelectRequest?.mode == qhd120)
    }

    /// 5a. Mock network contract:
    ///     Directly tests CompanionClient network requests against MockCompanionServer loopback.
    @Test func companionClientDirectNetworkContract() async throws {
        let server = try await MockCompanionServer.start()
        defer {
            server.stop()
        }

        let client = CompanionClient(address: "127.0.0.1", pinned: server.fingerprint)

        // /hello GET
        let isPresent = await client.isPresent()
        #expect(isPresent == true)

        // /outputs GET
        let payload = await client.outputs(token: "mock-token-abc")
        #expect(payload != nil)
        #expect(payload?.activeId == "HDMI-A-1")
        #expect(payload?.outputs.count == 3)
        #expect(server.receivedTokens.contains("mock-token-abc"))

        // /outputs/select POST with mode
        let targetMode = DisplayMode(width: 2560, height: 1440, refresh: 120.0)
        let selected = await client.selectOutput(token: "mock-token-abc", id: "HDMI-A-1", mode: targetMode)
        #expect(selected == true)
        #expect(server.lastSelectRequest?.id == "HDMI-A-1")
        #expect(server.lastSelectRequest?.mode == targetMode)

        // /outputs/select POST without mode
        let selectedWithoutMode = await client.selectOutput(token: "mock-token-abc", id: "virtual", mode: nil)
        #expect(selectedWithoutMode == true)
        #expect(server.lastSelectRequest?.id == "virtual")
        #expect(server.lastSelectRequest?.mode == nil)
    }

    /// 5b. Exact wire contract compatibility with companion/src/outputs.rs
    @Test func exactWireContractCompatibilityWithCompanionOutputsRs() throws {
        let data = try #require(Self.rustSerdeWireJson.data(using: .utf8))
        let payload = try JSONDecoder().decode(OutputsPayload.self, from: data)

        #expect(payload.activeId == "HDMI-A-1")
        #expect(payload.outputs.count == 3)

        assertWirePayloadOutputs(payload.outputs)

        // SelectOutputRequest encoding verification matching Rust's serde expectations
        let selectReq = SelectOutputRequest(id: "HDMI-A-1", mode: DisplayMode(width: 2560, height: 1440, refresh: 120.0))
        let encoded = try JSONEncoder().encode(selectReq)
        let jsonDict = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(jsonDict["id"] as? String == "HDMI-A-1")
        let modeDict = try #require(jsonDict["mode"] as? [String: Any])
        #expect(modeDict["width"] as? Int == 2560)
        #expect(modeDict["height"] as? Int == 1440)
        #expect(modeDict["refresh"] as? Double == 120.0)
    }

    private func assertHydratedOutputs(_ outputs: [HostOutput]) {
        #expect(outputs.count == 3)

        let virtualScreen = outputs[0]
        #expect(virtualScreen.id == "virtual")
        #expect(virtualScreen.name == "Virtual Screen (Mac Only)")
        #expect(virtualScreen.connector == "Virtual-sunshine-vmon")
        #expect(virtualScreen.isVirtual == true)
        #expect(virtualScreen.hdrSupported == false)

        let lgTv = outputs[1]
        #expect(lgTv.id == "HDMI-A-1")
        #expect(lgTv.name == "LG TV OLED55")
        #expect(lgTv.connector == "HDMI-A-1")
        #expect(lgTv.isVirtual == false)
        #expect(lgTv.hdrSupported == true)
        #expect(lgTv.currentMode == DisplayMode(width: 3840, height: 2160, refresh: 120.0))
        #expect(lgTv.modes.count == 2)

        let deskMonitor = outputs[2]
        #expect(deskMonitor.id == "DP-1")
        #expect(deskMonitor.name == "Desk Monitor (ROG PG279Q)")
        #expect(deskMonitor.connector == "DP-1")
        #expect(deskMonitor.isVirtual == false)
        #expect(deskMonitor.hdrSupported == false)
        #expect(deskMonitor.currentMode == DisplayMode(width: 2560, height: 1440, refresh: 144.0))
    }

    private func assertWirePayloadOutputs(_ outputs: [HostOutput]) {
        let virtualOut = outputs[0]
        #expect(virtualOut.id == "virtual")
        #expect(virtualOut.isVirtual == true)
        #expect(virtualOut.hdrSupported == false)
        #expect(virtualOut.currentMode == nil)
        #expect(virtualOut.modes.isEmpty)

        let tvOut = outputs[1]
        #expect(tvOut.id == "HDMI-A-1")
        #expect(tvOut.name == "LG TV OLED55")
        #expect(tvOut.connector == "HDMI-A-1")
        #expect(tvOut.isVirtual == false)
        #expect(tvOut.hdrSupported == true)
        #expect(tvOut.currentMode == DisplayMode(width: 3840, height: 2160, refresh: 120.0))
        #expect(tvOut.modes.count == 2)
        #expect(tvOut.modes[0] == DisplayMode(width: 3840, height: 2160, refresh: 120.0))
        #expect(tvOut.modes[1] == DisplayMode(width: 2560, height: 1440, refresh: 120.0))

        let dpOut = outputs[2]
        #expect(dpOut.id == "DP-1")
        #expect(dpOut.name == "Desk Monitor (ROG PG279Q)")
        #expect(dpOut.connector == "DP-1")
        #expect(dpOut.currentMode == DisplayMode(width: 2560, height: 1440, refresh: 144.0))
    }

    /// 6. Fallback safety when companion is older (e.g. returns 404 for /outputs)
    @Test @MainActor func regressionFallbackWhenCompanionOutputsReturns404() async throws {
        let server = try await MockCompanionServer.start()
        server.setOutputsStatusCode(404)
        defer {
            server.stop()
            CompanionClient.port = 47970
        }
        CompanionClient.port = server.port

        let hostId = "e2e-fallback-\(UUID().uuidString)"
        let host = Host(
            id: hostId,
            name: "Legacy-Host",
            customName: nil,
            localAddress: "127.0.0.1",
            manualAddress: nil,
            apps: [],
            lastConnected: nil,
            serverCertPEM: server.certPEM,
            appVersion: nil,
            macAddress: nil
        )

        let testToken = "test-legacy-token"
        CompanionTokens.save(testToken, fingerprint: server.fingerprint, forHost: host.id)
        defer {
            CompanionTokens.delete(forHost: host.id)
        }

        let model = AppModel()

        // Calling refreshOutputs against a 404 server should not throw or crash
        await model.refreshOutputs(for: host)

        // Outputs should gracefully fall back to the default virtual display
        let outputs = model.outputs(for: host)
        #expect(outputs.count == 1)
        #expect(outputs[0].id == "virtual")
        #expect(outputs[0].name == "Virtual Screen (Mac Only)")
        #expect(outputs[0].isVirtual == true)
        #expect(model.activeOutput(for: host)?.id == "virtual")
    }
}
