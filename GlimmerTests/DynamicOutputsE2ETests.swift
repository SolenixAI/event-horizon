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

// MARK: - Mock Companion Server

final class MockCompanionServer: @unchecked Sendable {
    let listener: NWListener
    private(set) var port: Int
    let certPEM: String
    let fingerprint: String

    private let lock = NSLock()
    private var outputsPayloadJson: String
    private var outputsStatusCode: Int = 200
    private var selectStatusCode: Int = 200
    private(set) var lastSelectRequest: SelectOutputRequest?
    private(set) var receivedTokens: [String] = []
    private(set) var requestPaths: [String] = []
    private var activeConnections: [NWConnection] = []

    static let standardFixtureJson = """
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

    private init(listener: NWListener, port: Int, certPEM: String, fingerprint: String, outputsJson: String) {
        self.listener = listener
        self.port = port
        self.certPEM = certPEM
        self.fingerprint = fingerprint
        self.outputsPayloadJson = outputsJson
    }

    static func start(
        initialOutputsJson: String? = nil,
        preferredPort: UInt16 = 47970
    ) async throws -> MockCompanionServer {
        let (certPEM, keyPEM) = try await IdentityManager.shared.generateKeyPairAndCert()
        guard let der = PEM.der(certPEM) else {
            throw StreamError.crypto("Failed to extract DER from mock server cert")
        }
        let fingerprint = CompanionClient.fingerprint(ofDER: der)
        let secIdentity = try ControlTransport.clientIdentity(certPEM: certPEM, keyPEM: keyPEM)

        let options = NWProtocolTLS.Options()
        let security = options.securityProtocolOptions
        sec_protocol_options_set_local_identity(security, secIdentity)
        sec_protocol_options_set_peer_authentication_required(security, false)
        sec_protocol_options_add_tls_application_protocol(security, "http/1.1")

        let parameters = NWParameters(tls: options)
        parameters.allowLocalEndpointReuse = true

        let queue = DispatchQueue(label: "dev.solenix.eventhorizon.tests.mock-companion")

        let listener: NWListener
        if let desiredPort = NWEndpoint.Port(rawValue: preferredPort),
           let direct = try? NWListener(using: parameters, on: desiredPort) {
            listener = direct
        } else {
            listener = try NWListener(using: parameters, on: .any)
        }

        let server = MockCompanionServer(
            listener: listener,
            port: 0,
            certPEM: certPEM,
            fingerprint: fingerprint,
            outputsJson: initialOutputsJson ?? standardFixtureJson
        )

        let boundPort = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak server] connection in
                guard let server else {
                    connection.cancel()
                    return
                }
                server.registerConnection(connection, queue: queue)
            }

            listener.start(queue: queue)
        }

        server.port = Int(boundPort)
        return server
    }

    private func registerConnection(_ connection: NWConnection, queue: DispatchQueue) {
        lock.withLock {
            activeConnections.append(connection)
        }
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .cancelled, .failed:
                self.lock.withLock {
                    self.activeConnections.removeAll(where: { $0 === connection })
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
        readRequest(connection: connection, accumulator: Data())
    }

    private func readRequest(connection: NWConnection, accumulator: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var acc = accumulator
            if let data { acc.append(data) }

            if let headerEndRange = acc.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = acc[..<headerEndRange.lowerBound]
                let headerString = String(decoding: headerData, as: UTF8.self)

                var contentLength = 0
                for line in headerString.components(separatedBy: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        let parts = line.split(separator: ":", maxSplits: 1)
                        if parts.count == 2, let len = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                            contentLength = len
                        }
                    }
                }

                let bodyReceived = acc.count - headerEndRange.upperBound
                if bodyReceived >= contentLength {
                    let bodyData = acc[headerEndRange.upperBound..<(headerEndRange.upperBound + contentLength)]
                    self.dispatchRequest(connection: connection, headerString: headerString, bodyData: Data(bodyData))
                    return
                }
            }

            if isComplete || error != nil {
                if !acc.isEmpty, let headerEndRange = acc.range(of: Data("\r\n\r\n".utf8)) {
                    let headerString = String(decoding: acc[..<headerEndRange.lowerBound], as: UTF8.self)
                    let bodyData = Data(acc[headerEndRange.upperBound...])
                    self.dispatchRequest(connection: connection, headerString: headerString, bodyData: bodyData)
                } else {
                    connection.cancel()
                }
                return
            }

            self.readRequest(connection: connection, accumulator: acc)
        }
    }

    private func dispatchRequest(connection: NWConnection, headerString: String, bodyData: Data) {
        let lines = headerString.components(separatedBy: "\r\n")
        let requestLine = lines.first ?? ""
        let tokens = requestLine.split(separator: " ")
        let method = tokens.first.map(String.init) ?? "GET"
        let path = tokens.count > 1 ? String(tokens[1]) : "/"

        for line in lines {
            if line.lowercased().hasPrefix("authorization:") {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let token = parts[1].trimmingCharacters(in: .whitespaces)
                    lock.withLock { receivedTokens.append(token) }
                }
            }
        }

        lock.withLock {
            requestPaths.append("\(method) \(path)")
        }

        let responseData: Data
        switch (method, path) {
        case ("GET", "/hello"):
            responseData = makeHttpResponse(statusCode: 200, statusText: "OK", body: #"{"app":"event-horizon-companion","v":1}"#)

        case ("GET", "/outputs"):
            let (code, json) = lock.withLock { (outputsStatusCode, outputsPayloadJson) }
            if code == 200 {
                responseData = makeHttpResponse(statusCode: 200, statusText: "OK", body: json)
            } else {
                responseData = makeHttpResponse(statusCode: code, statusText: "Error", body: #"{"error":"outputs unavailable"}"#)
            }

        case ("POST", "/outputs/select"):
            let code = lock.withLock { selectStatusCode }
            if code == 200 {
                if let req = try? JSONDecoder().decode(SelectOutputRequest.self, from: bodyData) {
                    lock.withLock {
                        lastSelectRequest = req
                        if let payload = try? JSONDecoder().decode(OutputsPayload.self, from: Data(outputsPayloadJson.utf8)) {
                            let updated = OutputsPayload(activeId: req.id, outputs: payload.outputs)
                            if let encoded = try? JSONEncoder().encode(updated),
                               let str = String(data: encoded, encoding: .utf8) {
                                outputsPayloadJson = str
                            }
                        }
                    }
                }
                responseData = makeHttpResponse(statusCode: 200, statusText: "OK", body: #"{"status":"ok"}"#)
            } else {
                responseData = makeHttpResponse(statusCode: code, statusText: "Error", body: #"{"error":"select failed"}"#)
            }

        default:
            responseData = makeHttpResponse(statusCode: 404, statusText: "Not Found", body: #"{"error":"not found"}"#)
        }

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func makeHttpResponse(statusCode: Int, statusText: String, body: String) -> Data {
        let bodyBytes = Data(body.utf8)
        let header = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
            + "Content-Type: application/json; charset=utf-8\r\n"
            + "Content-Length: \(bodyBytes.count)\r\n"
            + "Connection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(bodyBytes)
        return data
    }

    func setOutputsStatusCode(_ code: Int) {
        lock.withLock { outputsStatusCode = code }
    }

    func setSelectStatusCode(_ code: Int) {
        lock.withLock { selectStatusCode = code }
    }

    func setOutputsPayloadJson(_ json: String) {
        lock.withLock { outputsPayloadJson = json }
    }

    func stop() {
        listener.cancel()
        lock.withLock {
            for conn in activeConnections {
                conn.cancel()
            }
            activeConnections.removeAll()
        }
    }
}

// MARK: - Test Suite

@Suite struct DynamicOutputsE2ETests {

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

        let outputs = model.outputs(for: host)
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
        #expect(lgTv.modes.count == 2)

        let deskMonitor = outputs[2]
        #expect(deskMonitor.id == "DP-1")
        #expect(deskMonitor.name == "Desk Monitor (ROG PG279Q)")
        #expect(deskMonitor.connector == "DP-1")
        #expect(deskMonitor.isVirtual == false)
        #expect(deskMonitor.hdrSupported == false)

        // 2. Active output resolution: active_id == HDMI-A-1 -> LG TV OLED55
        let active = model.activeOutput(for: host)
        #expect(active?.id == "HDMI-A-1")
        #expect(active?.name == "LG TV OLED55")
        #expect(active?.hdrSupported == true)

        // Initial active mode from LG TV OLED55 currentMode (4K @ 120Hz)
        let initialMode = model.activeMode(for: host)
        #expect(initialMode == DisplayMode(width: 3840, height: 2160, refresh: 120.0))
        #expect(initialMode?.resolutionLabel == "4K")
        #expect(initialMode?.label == "4K @ 120Hz")

        // 3. Output switching: select DP-1 without explicit mode
        let switchedToMonitor = await model.selectOutput(host: host, outputId: "DP-1", mode: nil)
        #expect(switchedToMonitor == true)

        let activeAfterSwitch = model.activeOutput(for: host)
        #expect(activeAfterSwitch?.id == "DP-1")
        #expect(activeAfterSwitch?.name == "Desk Monitor (ROG PG279Q)")
        #expect(model.loadPersistedOutputId(for: host.id) == "DP-1")

        // 4. Mode resolution on DP-1: auto-resolved to DP-1's currentMode (1440p @ 144Hz)
        let monitorMode = model.activeMode(for: host)
        #expect(monitorMode == DisplayMode(width: 2560, height: 1440, refresh: 144.0))
        #expect(monitorMode?.resolutionLabel == "1440p")
        #expect(monitorMode?.label == "1440p @ 144Hz")

        // Switch back to HDMI-A-1 with explicit mode: 1440p @ 120Hz
        let targetMode = DisplayMode(width: 2560, height: 1440, refresh: 120.0)
        let switchedWithMode = await model.selectOutput(host: host, outputId: "HDMI-A-1", mode: targetMode)
        #expect(switchedWithMode == true)

        let tvOutputWithMode = model.activeOutput(for: host)
        #expect(tvOutputWithMode?.id == "HDMI-A-1")
        #expect(tvOutputWithMode?.name == "LG TV OLED55")

        let activeTvMode = model.activeMode(for: host)
        #expect(activeTvMode == targetMode)
        #expect(activeTvMode?.resolutionLabel == "1440p")
        #expect(activeTvMode?.label == "1440p @ 120Hz")
        #expect(model.loadPersistedMode(for: host.id) == targetMode)

        // Verify the mock server received the authorization bearer header
        #expect(server.receivedTokens.contains("Bearer \(testToken)"))
    }

    /// 5. Mock network contract:
    ///    Direct client networking verification against loopback TLS server
    ///    validating wire contract headers, token passing, and JSON structure.
    @Test func companionClientDirectNetworkContract() async throws {
        let server = try await MockCompanionServer.start()
        defer {
            server.stop()
            CompanionClient.port = 47970
        }
        CompanionClient.port = server.port

        let client = CompanionClient(address: "127.0.0.1", pinned: server.fingerprint)

        // /hello check
        let isPresent = await client.isPresent()
        #expect(isPresent == true)

        // /outputs GET
        let outputsPayload = await client.outputs(token: "mock-token-abc")
        let payload = try #require(outputsPayload)
        #expect(payload.activeId == "HDMI-A-1")
        #expect(payload.outputs.count == 3)
        #expect(payload.outputs[1].id == "HDMI-A-1")
        #expect(payload.outputs[1].name == "LG TV OLED55")
        #expect(payload.outputs[2].id == "DP-1")
        #expect(payload.outputs[2].name == "Desk Monitor (ROG PG279Q)")

        // /outputs/select POST with mode
        let testMode = DisplayMode(width: 2560, height: 1440, refresh: 120.0)
        let selected = await client.selectOutput(token: "mock-token-abc", id: "HDMI-A-1", mode: testMode)
        #expect(selected == true)
        #expect(server.lastSelectRequest?.id == "HDMI-A-1")
        #expect(server.lastSelectRequest?.mode == testMode)

        // /outputs/select POST without mode
        let selectedWithoutMode = await client.selectOutput(token: "mock-token-abc", id: "virtual", mode: nil)
        #expect(selectedWithoutMode == true)
        #expect(server.lastSelectRequest?.id == "virtual")
        #expect(server.lastSelectRequest?.mode == nil)
    }

    /// 5b. Exact wire contract compatibility with companion/src/outputs.rs:
    ///     Decodes Rust serde snake_case wire JSON matching exact payload models.
    @Test func exactWireContractCompatibilityWithCompanionOutputsRs() throws {
        let rustSerdeJson = """
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
              "current_mode": {
                "width": 3840,
                "height": 2160,
                "refresh": 120.0
              },
              "modes": [
                {
                  "width": 3840,
                  "height": 2160,
                  "refresh": 120.0
                },
                {
                  "width": 2560,
                  "height": 1440,
                  "refresh": 120.0
                }
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
              "current_mode": {
                "width": 2560,
                "height": 1440,
                "refresh": 144.0
              },
              "modes": [
                {
                  "width": 2560,
                  "height": 1440,
                  "refresh": 144.0
                }
              ]
            }
          ]
        }
        """

        let data = try #require(rustSerdeJson.data(using: .utf8))
        let payload = try JSONDecoder().decode(OutputsPayload.self, from: data)

        #expect(payload.activeId == "HDMI-A-1")
        #expect(payload.outputs.count == 3)

        let virtualOut = payload.outputs[0]
        #expect(virtualOut.id == "virtual")
        #expect(virtualOut.isVirtual == true)
        #expect(virtualOut.hdrSupported == false)
        #expect(virtualOut.currentMode == nil)
        #expect(virtualOut.modes.isEmpty)

        let tvOut = payload.outputs[1]
        #expect(tvOut.id == "HDMI-A-1")
        #expect(tvOut.name == "LG TV OLED55")
        #expect(tvOut.connector == "HDMI-A-1")
        #expect(tvOut.isVirtual == false)
        #expect(tvOut.hdrSupported == true)
        #expect(tvOut.currentMode == DisplayMode(width: 3840, height: 2160, refresh: 120.0))
        #expect(tvOut.modes.count == 2)
        #expect(tvOut.modes[0] == DisplayMode(width: 3840, height: 2160, refresh: 120.0))
        #expect(tvOut.modes[1] == DisplayMode(width: 2560, height: 1440, refresh: 120.0))

        let dpOut = payload.outputs[2]
        #expect(dpOut.id == "DP-1")
        #expect(dpOut.name == "Desk Monitor (ROG PG279Q)")
        #expect(dpOut.connector == "DP-1")
        #expect(dpOut.currentMode == DisplayMode(width: 2560, height: 1440, refresh: 144.0))

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

    /// Regression & fallback test:
    /// Replicates the exact condition observed with the Nov 8 tower companion binary
    /// where /outputs returns 404 Not Found. AppModel must gracefully fall back
    /// to Virtual Screen without crashing or failing.
    @Test @MainActor func regressionFallbackWhenCompanionOutputsReturns404() async throws {
        let server = try await MockCompanionServer.start()
        server.setOutputsStatusCode(404)
        defer {
            server.stop()
            CompanionClient.port = 47970
        }
        CompanionClient.port = server.port

        let hostId = "e2e-404-fallback-\(UUID().uuidString)"
        let host = Host(
            id: hostId,
            name: "Legacy-Companion-Tower",
            customName: nil,
            localAddress: "127.0.0.1",
            manualAddress: nil,
            apps: [],
            lastConnected: nil,
            serverCertPEM: server.certPEM,
            appVersion: nil,
            macAddress: nil
        )

        let testToken = "test-token-404-\(UUID().uuidString)"
        CompanionTokens.save(testToken, fingerprint: server.fingerprint, forHost: host.id)
        defer {
            CompanionTokens.delete(forHost: host.id)
            UserDefaults.standard.removeObject(forKey: AppModel.outputDefaultsKey(for: host.id))
            UserDefaults.standard.removeObject(forKey: AppModel.modeDefaultsKey(for: host.id))
        }

        let model = AppModel()
        await model.refreshOutputs(for: host)

        // When 404 is encountered, client safely falls back to defaultVirtual
        let outputs = model.outputs(for: host)
        #expect(outputs.count == 1)
        #expect(outputs[0].id == "virtual")
        #expect(outputs[0].name == "Virtual Screen (Mac Only)")
        #expect(outputs[0].isVirtual == true)
        #expect(model.activeOutput(for: host)?.id == "virtual")
    }
}
