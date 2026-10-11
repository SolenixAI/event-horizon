//
//  UsageStats.swift
//
//  Anonymous usage events for PostHog, sent only while the person has turned on
//  Share anonymous usage stats in Settings › General. Off by default. No PC
//  names, addresses or app titles ever leave the Mac.
//

import Foundation

@MainActor
enum UsageStats {
    nonisolated static let enabledKey = "shareUsageStats"
    static let installIDKey = "usageStatsInstallID"
    /// Everything the switch sends, said once, where the switch shows it.
    static let consentLine = "When you open Event Horizon and stream, how long and how smoothly streams run, "
        + "their size, crash reports, your country, and the app and macOS versions, under a random ID "
        + "that's forgotten when you turn this off. Never your PC's name or address, or what you play."
    // The project's public ingestion key: it can only write events.
    nonisolated static let projectKey = "phc_yiiguNiBP8LGF8vrcWnDVMs3CkaEBLPk3gwGNrpqLs5G"
    nonisolated static let endpoint = URL(string: "https://us.i.posthog.com/i/v0/e/")

    /// Tests swap both so nothing reads real defaults or touches the network.
    static var defaults: UserDefaults = .standard
    static var transport: @Sendable (URLRequest) async -> Void = { request in
        _ = try? await URLSession.shared.data(for: request)
    }

    private static var connectStartedAt: Date?
    private static var liveAt: Date?

    // MARK: - Events

    static func appOpened() { capture("app_opened") }

    /// The attempt's first stage stamps the start; later stages and reconnects don't.
    static func connectStarted() {
        guard connectStartedAt == nil else { return }
        connectStartedAt = Date()
    }

    /// Latched once per session, like the receipt's live edge, and only while
    /// stats are on, so turning them on mid-stream never reports half a session.
    @discardableResult
    static func sessionLive() -> Task<Void, Never>? {
        guard liveAt == nil, defaults.bool(forKey: enabledKey) else { return nil }
        let now = Date()
        liveAt = now
        var properties: [String: Any] = [:]
        if let start = connectStartedAt {
            properties["connect_seconds"] = rounded(now.timeIntervalSince(start))
        }
        return capture("session_started", properties)
    }

    /// One event per attempt: the end of a session that went live, however it
    /// ended, or the failure of one that never did.
    @discardableResult
    static func streamFinished(
        receipt: SessionReceipt?, failure: AppModel.StreamErrorKind?, cancelled: Bool
    ) -> Task<Void, Never>? {
        defer { connectStartedAt = nil; liveAt = nil }
        guard !cancelled else { return nil }
        guard let liveAt else {
            return failure.flatMap { capture("stream_failed", ["error_kind": "\($0)"]) }
        }
        var properties: [String: Any] = [
            "duration_minutes": rounded(Date().timeIntervalSince(liveAt) / 60),
            "outcome": failure == nil ? "ended" : "failed"]
        if let failure { properties["error_kind"] = "\(failure)" }
        if let receipt {
            properties["width"] = receipt.width
            properties["height"] = receipt.height
            properties["refresh_hz"] = receipt.refreshHz
            if let rtt = receipt.medianRttMs { properties["rtt_ms"] = rounded(rtt) }
            if let goodput = receipt.avgGoodputMbps { properties["goodput_mbps"] = rounded(goodput) }
        }
        return capture("session_ended", properties)
    }

    /// Turning stats off forgets the install's ID, so turning them on again starts fresh.
    static func setEnabled(_ enabled: Bool) {
        if enabled {
            CrashReports.startCounting()
            capture("app_opened")
        } else {
            defaults.removeObject(forKey: installIDKey)
            CrashReports.stopCounting()
        }
    }

    // MARK: - Sending

    /// The one gate: nothing is built, so nothing is sent, while stats are off.
    @discardableResult
    static func capture(_ event: String, _ properties: [String: Any] = [:]) -> Task<Void, Never>? {
        guard defaults.bool(forKey: enabledKey),
              let request = request(event: event, properties: properties, installID: installID()) else { return nil }
        let send = transport
        return Task { await send(request) }
    }

    nonisolated static func request(event: String, properties: [String: Any], installID: String) -> URLRequest? {
        guard let endpoint else { return nil }
        var all = properties
        all["app"] = "event-horizon"
        all["app_version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let os = ProcessInfo.processInfo.operatingSystemVersion
        all["os_version"] = "\(os.majorVersion).\(os.minorVersion)"
        all["$process_person_profile"] = false
        // Test builds and test runs are tagged so the project's filter drops them.
        if !AppDataFolders.isShippedBuild { all["internal"] = true }
        let body: [String: Any] = [
            "api_key": projectKey, "event": event, "distinct_id": installID, "properties": all]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        return request
    }

    private static func installID() -> String {
        if let id = defaults.string(forKey: installIDKey) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: installIDKey)
        return id
    }

    private nonisolated static func rounded(_ value: Double) -> Double { (value * 10).rounded() / 10 }
}
