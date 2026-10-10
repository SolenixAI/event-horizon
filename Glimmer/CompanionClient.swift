//
//  CompanionClient.swift
//
//  Event Horizon's side of the PC companion (docs/companion/DESIGN.md). A PC
//  that runs the companion pairs with one click on Allow at the PC (nobody
//  types the code into Sunshine's page), and stays awake while this Mac
//  streams from it: the Mac renews a lease every 30 s.
//

import Foundation
import Security

/// The companion's Link on one PC: `GET /hello`, `POST /pair`, `POST /lease`.
struct CompanionClient: Sendable {
    static let port = 47970
    /// The Mac renews well inside the companion's 90 s lease.
    static let leaseInterval: Duration = .seconds(30)

    enum PairResult: Equatable, Sendable {
        case paired(token: String)
        case denied, expired, replaced, sunshineDown, unavailable
    }

    let address: String

    private func url(_ path: String) -> URL? {
        let host = address.contains(":") ? "[\(address)]" : address
        return URL(string: "http://\(host):\(Self.port)\(path)")
    }

    private static func session(timeout: TimeInterval) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        return URLSession(configuration: config)
    }

    /// Whether this PC runs the companion. Quick: a PC without it refuses
    /// the port at once.
    func isPresent() async -> Bool {
        guard let url = url("/hello"),
              let (data, response) = try? await Self.session(timeout: 2).data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return body["app"] as? String == "event-horizon-companion"
    }

    /// Ask the person at the PC to allow this Mac. Returns when they answer,
    /// or after the companion's 2-minute wait. With no PIN the Mac is already
    /// paired with Sunshine and only asks for the companion's token.
    func pair(macID: String, macName: String, pin: String?) async -> PairResult {
        guard let url = url("/pair") else { return .unavailable }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["mac_id": macID, "mac_name": macName, "code": pin ?? ""]
        if let pin { body["pin"] = pin }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await Self.session(timeout: 130).data(for: request),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .unavailable }
        return Self.result(from: body)
    }

    /// The companion's answer as a result. Pure, so it is tested directly.
    static func result(from body: [String: Any]) -> PairResult {
        switch body["outcome"] as? String {
        case "paired": (body["token"] as? String).map { .paired(token: $0) } ?? .unavailable
        case "denied": .denied
        case "expired": .expired
        case "replaced": .replaced
        case "sunshine_down": .sunshineDown
        default: .unavailable
        }
    }

    enum LeaseOutcome: Equatable, Sendable {
        case renewed, refused, unreachable
    }

    /// Keep the PC awake for the next 90 s.
    func lease(token: String) async -> LeaseOutcome {
        guard let url = url("/lease") else { return .unreachable }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let response = try? await Self.session(timeout: 5).data(for: request).1
        return Self.leaseOutcome(statusCode: (response as? HTTPURLResponse)?.statusCode)
    }

    /// Only a refused token ends the lease; anything else is tried again
    /// next round, so one dropped request never lets the PC sleep.
    static func leaseOutcome(statusCode: Int?) -> LeaseOutcome {
        switch statusCode {
        case 204: .renewed
        case 401, 403: .refused
        default: .unreachable
        }
    }
}

/// The companion tokens this Mac holds, one per PC, in the login Keychain.
enum CompanionTokens {
    private static let service = "dev.solenix.eventhorizon.companion"

    static func save(_ token: String, forHost hostID: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: hostID]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func token(forHost hostID: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: hostID,
                                    kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
