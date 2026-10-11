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
        UsageStats.sessionLive()
        UsageStats.streamFinished(receipt: nil, failure: .unreachable, cancelled: false)
        await Task.yield()
        #expect(await sent.requests.isEmpty)
        #expect(defaults.string(forKey: UsageStats.installIDKey) == nil)
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
        // Tests run a Debug build, which the project's internal filter drops.
        #expect(properties["internal"] as? Bool == true)
        #expect(body["distinct_id"] as? String == defaults.string(forKey: UsageStats.installIDKey))
    }

    @Test func failureSendsOnlyItsKind() throws {
        let request = try #require(UsageStats.request(
            event: "stream_failed", properties: ["error_kind": "unreachable"], installID: "test"))
        let properties = try #require(try Self.body(request)["properties"] as? [String: Any])
        let allowed: Set = ["error_kind", "app", "app_version", "os_version", "$process_person_profile", "internal"]
        #expect(Set(properties.keys).isSubset(of: allowed))
    }

    @Test func turningOffForgetsTheInstall() {
        defaults.set("old-id", forKey: UsageStats.installIDKey)
        UsageStats.setEnabled(false)
        #expect(defaults.string(forKey: UsageStats.installIDKey) == nil)
    }
}
