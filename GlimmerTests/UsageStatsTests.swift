//
//  UsageStatsTests.swift
//
//  The opt-in gate: while stats are off nothing is built or sent, and what is
//  sent is tagged for the shared PostHog project and carries no PC details.
//

import Foundation
import Testing
@testable import Glimmer

private actor SentRequests {
    private(set) var requests: [URLRequest] = []
    func append(_ request: URLRequest) { requests.append(request) }
}

@MainActor
@Suite(.serialized)
struct UsageStatsTests {
    private let defaults: UserDefaults
    private let sent = SentRequests()

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "UsageStatsTests"))
        defaults.removePersistentDomain(forName: "UsageStatsTests")
        UsageStats.defaults = defaults
        let sent = sent
        UsageStats.transport = { await sent.append($0) }
    }

    private static func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func offByDefaultSendsNothing() async {
        #expect(UsageStats.capture("app_opened") == nil)
        UsageStats.connectStarted()
        #expect(UsageStats.sessionLive() == nil)
        #expect(UsageStats.streamFinished(receipt: nil, failure: .unreachable, cancelled: false) == nil)
        #expect(await sent.requests.isEmpty)
        #expect(defaults.string(forKey: UsageStats.installIDKey) == nil)
    }

    @Test func turningOnMidStreamReportsNoHalfSession() {
        UsageStats.connectStarted()
        UsageStats.sessionLive()
        defaults.set(true, forKey: UsageStats.enabledKey)
        #expect(UsageStats.streamFinished(receipt: nil, failure: nil, cancelled: false) == nil)
    }

    @Test func onSendsOneTaggedEvent() async throws {
        defaults.set(true, forKey: UsageStats.enabledKey)
        await UsageStats.capture("app_opened")?.value
        let requests = await sent.requests
        #expect(requests.count == 1)
        let body = try Self.body(try #require(requests.first))
        let properties = try #require(body["properties"] as? [String: Any])
        #expect(body["event"] as? String == "app_opened")
        #expect(properties["app"] as? String == "event-horizon")
        #expect(properties["$process_person_profile"] as? Bool == false)
        // A test run is never the shipped build, so its events are tagged internal.
        #expect(properties["internal"] as? Bool == true)
        #expect(body["distinct_id"] as? String == defaults.string(forKey: UsageStats.installIDKey))
    }

    @Test func failuresSendOnlyAllowedKeys() async throws {
        defaults.set(true, forKey: UsageStats.enabledKey)
        UsageStats.connectStarted()
        await UsageStats.streamFinished(receipt: nil, failure: .unreachable, cancelled: false)?.value
        UsageStats.connectStarted()
        await UsageStats.sessionLive()?.value
        await UsageStats.streamFinished(receipt: nil, failure: .other, cancelled: false)?.value
        let bodies = try await sent.requests.map(Self.body)
        #expect(bodies.compactMap { $0["event"] as? String } == ["stream_failed", "session_started", "session_ended"])
        let allowed: Set = ["error_kind", "outcome", "duration_minutes", "connect_seconds",
                            "app", "app_version", "os_version", "$process_person_profile", "internal"]
        for body in bodies {
            let properties = try #require(body["properties"] as? [String: Any])
            #expect(Set(properties.keys).isSubset(of: allowed))
        }
        let ended = try #require(bodies.last?["properties"] as? [String: Any])
        #expect(ended["outcome"] as? String == "failed")
        #expect(ended["error_kind"] as? String == "other")
    }

    // Here, not in CrashReportsTests: it shares UsageStats' defaults with this serialized suite.
    @Test func crashReportsWaitForTheSwitch() {
        CrashReports.sendNew()
        #expect(defaults.object(forKey: CrashReports.sinceKey) == nil)
        UsageStats.setEnabled(true)
        #expect(defaults.object(forKey: CrashReports.sinceKey) != nil)
        UsageStats.setEnabled(false)
        #expect(defaults.object(forKey: CrashReports.sinceKey) == nil)
    }

    @Test func turningOffForgetsTheInstall() {
        defaults.set("old-id", forKey: UsageStats.installIDKey)
        UsageStats.setEnabled(false)
        #expect(defaults.string(forKey: UsageStats.installIDKey) == nil)
    }
}
