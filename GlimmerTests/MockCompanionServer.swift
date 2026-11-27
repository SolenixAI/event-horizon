//
//  MockCompanionServer.swift
//
//  In-memory mock TLS companion server for loopback unit and integration testing.
//

import Foundation
import Network
import Security
@testable import Glimmer

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
        sec_protocol_options_set_local_identity(options.securityProtocolOptions, secIdentity)
        if let suite = tls_ciphersuite_t(rawValue: UInt16(TLS_AES_128_GCM_SHA256)) {
            sec_protocol_options_append_tls_ciphersuite(options.securityProtocolOptions, suite)
        }
        if let suite = tls_ciphersuite_t(rawValue: UInt16(TLS_AES_256_GCM_SHA384)) {
            sec_protocol_options_append_tls_ciphersuite(options.securityProtocolOptions, suite)
        }
        if let suite = tls_ciphersuite_t(rawValue: UInt16(TLS_CHACHA20_POLY1305_SHA256)) {
            sec_protocol_options_append_tls_ciphersuite(options.securityProtocolOptions, suite)
        }
        sec_protocol_options_add_tls_application_protocol(options.securityProtocolOptions, "http/1.1")

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableFastOpen = false
        let parameters = NWParameters(tls: options, tcp: tcpOptions)

        let chosenPort: NWEndpoint.Port = NWEndpoint.Port(rawValue: preferredPort) ?? .any
        let listener: NWListener
        if let specific = try? NWListener(using: parameters, on: chosenPort) {
            listener = specific
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
        server.setupConnectionHandler()

        let queue = DispatchQueue(label: "dev.solenix.eventhorizon.mock-companion")
        let actualPort = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let portVal = Int(listener.port?.rawValue ?? 0)
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: portVal)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }

        server.port = actualPort
        return server
    }

    private func setupConnectionHandler() {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.lock.withLock {
                self.activeConnections.append(connection)
            }
            connection.start(queue: DispatchQueue(label: "dev.solenix.eventhorizon.mock-connection"))
            self.readRequest(connection: connection, accumulator: Data())
        }
    }

    private func readRequest(connection: NWConnection, accumulator: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var acc = accumulator
            if let data { acc.append(data) }

            if let headerEndRange = acc.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = acc[..<headerEndRange.lowerBound]
                let headerString = String(bytes: headerData, encoding: .utf8) ?? ""

                var contentLength = 0
                for line in headerString.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("content-length:") {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    if parts.count == 2, let len = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                        contentLength = len
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
                    let headerString = String(bytes: acc[..<headerEndRange.lowerBound], encoding: .utf8) ?? ""
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

        for line in lines where line.lowercased().hasPrefix("authorization:") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let rawToken = parts[1].trimmingCharacters(in: .whitespaces)
                let token = rawToken.hasPrefix("Bearer ") ? String(rawToken.dropFirst(7)) : rawToken
                lock.withLock {
                    receivedTokens.append(token)
                    if token != rawToken {
                        receivedTokens.append(rawToken)
                    }
                }
            }
        }

        lock.withLock {
            requestPaths.append("\(method) \(path)")
        }

        let responseData = handleRoute(method: method, path: path, bodyData: bodyData)
        connection.send(content: responseData, completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            self?.lock.withLock {
                self?.activeConnections.removeAll { $0 === connection }
            }
        })
    }

    private func handleRoute(method: String, path: String, bodyData: Data) -> Data {
        switch (method, path) {
        case ("GET", "/hello"):
            return makeHttpResponse(statusCode: 200, statusText: "OK", body: #"{"app":"event-horizon-companion","v":2}"#)
        case ("GET", "/outputs"):
            let code = lock.withLock { outputsStatusCode }
            if code == 200 {
                let json = lock.withLock { outputsPayloadJson }
                return makeHttpResponse(statusCode: 200, statusText: "OK", body: json)
            } else {
                return makeHttpResponse(statusCode: code, statusText: "Error", body: #"{"error":"not_found"}"#)
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
                return makeHttpResponse(statusCode: 200, statusText: "OK", body: #"{"status":"ok"}"#)
            } else {
                return makeHttpResponse(statusCode: code, statusText: "Error", body: #"{"error":"failed"}"#)
            }
        default:
            return makeHttpResponse(statusCode: 404, statusText: "Not Found", body: #"{"error":"not_found"}"#)
        }
    }

    private func makeHttpResponse(statusCode: Int, statusText: String, body: String) -> Data {
        let bodyBytes = Data(body.utf8)
        let header = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
            + "Content-Type: application/json\r\n"
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
