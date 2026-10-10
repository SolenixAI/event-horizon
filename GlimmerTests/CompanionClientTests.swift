//
//  CompanionClientTests.swift
//
//  The companion's answers to a pairing request, as the Mac reads them. Only
//  "paired" with a token is a pairing; anything unknown is "unavailable", so
//  the person falls back to typing the code into Sunshine.
//

import Testing
@testable import Glimmer

struct CompanionClientTests {

    @Test func pairedCarriesTheToken() {
        let result = CompanionClient.result(from: ["outcome": "paired", "token": "ab12"])
        #expect(result == .paired(token: "ab12"))
    }

    @Test func pairedWithoutATokenIsNotAPairing() {
        #expect(CompanionClient.result(from: ["outcome": "paired"]) == .unavailable)
    }

    @Test func everyRefusalHasItsOwnResult() {
        #expect(CompanionClient.result(from: ["outcome": "denied"]) == .denied)
        #expect(CompanionClient.result(from: ["outcome": "expired"]) == .expired)
        #expect(CompanionClient.result(from: ["outcome": "replaced"]) == .replaced)
        #expect(CompanionClient.result(from: ["outcome": "sunshine_down"]) == .sunshineDown)
    }

    @Test func anUnknownAnswerFallsBackToTheManualCode() {
        #expect(CompanionClient.result(from: ["outcome": "something new"]) == .unavailable)
        #expect(CompanionClient.result(from: [:]) == .unavailable)
    }
}

/// The lease keeps the PC awake for the whole stream: only the companion
/// refusing the token ends it; a dropped request is retried next round.
struct CompanionLeaseTests {

    @Test func aRenewalIsTheCompanionsNoContent() {
        #expect(CompanionClient.leaseOutcome(statusCode: 204) == .renewed)
    }

    @Test func onlyARefusedTokenEndsTheLease() {
        #expect(CompanionClient.leaseOutcome(statusCode: 401) == .refused)
        #expect(CompanionClient.leaseOutcome(statusCode: 403) == .refused)
    }

    @Test func aDroppedRequestIsRetriedNotTheEnd() {
        #expect(CompanionClient.leaseOutcome(statusCode: nil) == .unreachable)
        #expect(CompanionClient.leaseOutcome(statusCode: 500) == .unreachable)
        #expect(CompanionClient.leaseOutcome(statusCode: 503) == .unreachable)
    }
}
