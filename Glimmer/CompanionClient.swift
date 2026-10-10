//
//  CompanionClient.swift
//
//  The PC companion's Link (docs/companion/DESIGN.md): HTTPS, pinned by fingerprint,
//  two-step pairing with the PC's code, and the lease that keeps the PC awake.
//

import CryptoKit
import Foundation
import Security

/// The companion's Link on one PC: `GET /hello`, `POST /pair`, `GET /pair/{ticket}`,
/// `POST /lease` and `DELETE /pair`.
struct CompanionClient: Sendable {
    static let port = 47970
    /// The Mac renews well inside the companion's 90 s lease.
    static let leaseInterval: Duration = .seconds(30)

    enum PairResult: Equatable, Sendable {
        case paired(token: String)
        case denied, expired, replaced, sunshineDown, unavailable
    }

    /// The code the PC shows for one request, and the ticket for its answer.
    struct Ask: Equatable, Sendable {
        let code: String
        let ticket: String
    }

    enum LeaseOutcome: Equatable, Sendable {
        case renewed, refused, unreachable
    }

    enum ForgetOutcome: Equatable, Sendable {
        case forgotten, unreachable
    }

    let address: String
    private let trust: CompanionTrust

    /// `pinned` is the fingerprint this PC's certificate must have; nil trusts
    /// the first certificate it shows.
    init(address: String, pinned: String?) {
        self.address = address
        self.trust = CompanionTrust(pinned: pinned)
    }

    /// The fingerprint of the certificate the PC showed last, if it showed one.
    var fingerprint: String? { trust.observed }

    private func url(_ path: String) -> URL? {
        let host = address.contains(":") ? "[\(address)]" : address
        return URL(string: "https://\(host):\(Self.port)\(path)")
    }

    private func send(_ request: URLRequest, timeout: TimeInterval) async throws -> (Data, URLResponse) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config, delegate: trust, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await session.data(for: request)
    }

    /// Whether this PC runs the companion. Quick: a PC without it refuses
    /// the port at once.
    func isPresent() async -> Bool {
        guard let url = url("/hello"),
              let (data, response) = try? await send(URLRequest(url: url), timeout: 2),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return body["app"] as? String == "event-horizon-companion"
    }

    /// Step one: the PC makes the code and returns it at once. With no PIN the
    /// Mac is already paired with Sunshine and only asks for the companion's token.
    func ask(macID: String, macName: String, pin: String?) async -> Ask? {
        guard let url = url("/pair") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["mac_id": macID, "mac_name": macName]
        if let pin { body["pin"] = pin }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await send(request, timeout: 10),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return Self.ask(from: body)
    }

    /// Step two: waits for the person at the PC to answer. The companion
    /// answers within its two-minute wait.
    func answer(ticket: String) async -> PairResult {
        guard let url = url("/pair/\(ticket)"),
              let (data, _) = try? await send(URLRequest(url: url), timeout: 130),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .unavailable }
        return Self.result(from: body)
    }

    /// The PC's answer to a pairing request. Pure, so it is tested directly.
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

    /// The PC's code and ticket. Pure, so it is tested directly.
    static func ask(from body: [String: Any]) -> Ask? {
        guard let code = body["code"] as? String,
              code.count == 6, code.allSatisfy({ $0.isASCII && $0.isNumber }),
              let ticket = body["ticket"] as? String, !ticket.isEmpty
        else { return nil }
        return Ask(code: code, ticket: ticket)
    }

    /// The code as people read it: "123 456".
    static func spaced(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }

    /// Keep the PC awake for the next 90 s.
    func lease(token: String) async -> LeaseOutcome {
        guard let url = url("/lease") else { return .unreachable }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let response = try? await send(request, timeout: 5).1
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

    /// Remove this Mac from the PC. A 401 means the PC has no record of this
    /// Mac any more, which is the same end.
    func forget(token: String) async -> ForgetOutcome {
        guard let url = url("/pair") else { return .unreachable }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let response = try? await send(request, timeout: 10).1
        return Self.forgetOutcome(statusCode: (response as? HTTPURLResponse)?.statusCode)
    }

    static func forgetOutcome(statusCode: Int?) -> ForgetOutcome {
        switch statusCode {
        case 204, 401: .forgotten
        default: .unreachable
        }
    }

    /// Whether a certificate with this fingerprint may serve the Link. Before
    /// a pin exists any certificate may; after, only the pinned one.
    static func trusts(_ observed: String, pinned: String?) -> Bool {
        guard let pinned else { return true }
        return pinned.lowercased() == observed.lowercased()
    }

    /// SHA-256 of a certificate's DER bytes, in lowercase hex.
    static func fingerprint(ofDER der: Data) -> String {
        SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }
}

/// Checks the PC's certificate on every request: it must be the pinned one,
/// or, before any pin exists, whatever the PC shows. Remembers what it saw.
final class CompanionTrust: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let pinned: String?
    private let lock = NSLock()
    private var seen: String?

    init(pinned: String?) {
        self.pinned = pinned
    }

    /// The fingerprint of the certificate the PC showed last.
    var observed: String? { lock.withLock { seen } }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let fingerprint = CompanionClient.fingerprint(ofDER: SecCertificateCopyData(leaf) as Data)
        lock.withLock { seen = fingerprint }
        guard CompanionClient.trusts(fingerprint, pinned: pinned) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
