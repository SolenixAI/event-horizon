//
//  CompanionClientTests.swift
//
//  The companion's answers to a pairing request, as the Mac reads them. Only
//  "paired" with a token is a pairing; anything else falls back to Sunshine's code.

import Foundation
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

/// The PC makes the code; the Mac shows it. Only a six-digit code with a
/// ticket is a code.
struct CompanionCodeTests {

    @Test func aSixDigitCodeWithItsTicketIsAnAsk() {
        let ask = CompanionClient.ask(from: ["code": "123456", "ticket": "t1"])
        #expect(ask == CompanionClient.Ask(code: "123456", ticket: "t1"))
    }

    @Test func anythingOtherThanSixDigitsIsNoCode() {
        #expect(CompanionClient.ask(from: ["code": "12345", "ticket": "t1"]) == nil)
        #expect(CompanionClient.ask(from: ["code": "12345a", "ticket": "t1"]) == nil)
        #expect(CompanionClient.ask(from: ["code": "1234567", "ticket": "t1"]) == nil)
    }

    @Test func aCodeWithoutATicketIsNoCode() {
        #expect(CompanionClient.ask(from: ["code": "123456"]) == nil)
        #expect(CompanionClient.ask(from: ["code": "123456", "ticket": ""]) == nil)
    }

    @Test func theCodeReadsInTwoGroupsOfThree() {
        #expect(CompanionClient.spaced("123456") == "123 456")
    }
}

/// The Mac pins the PC's certificate: the first one it sees, then only that one.
struct CompanionPinTests {

    @Test func withNoPinAnyCertificateIsTrusted() {
        #expect(CompanionClient.trusts("ab12", pinned: nil))
    }

    @Test func aPinnedPCMustShowTheSameCertificate() {
        #expect(CompanionClient.trusts("ab12", pinned: "ab12"))
        #expect(CompanionClient.trusts("AB12", pinned: "ab12"))
        #expect(!CompanionClient.trusts("cd34", pinned: "ab12"))
    }

    @Test func theFingerprintIsTheSHA256OfTheCertificate() {
        // SHA-256 of the bytes "abc" (FIPS 180-2 test vector).
        let fingerprint = CompanionClient.fingerprint(ofDER: Data("abc".utf8))
        #expect(fingerprint == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

/// Forget: the PC forgets this Mac, or has no record of it any more.
struct CompanionForgetTests {

    @Test func aForgottenMacIsNoLongerPaired() {
        #expect(CompanionClient.forgetOutcome(statusCode: 204) == .forgotten)
        #expect(CompanionClient.forgetOutcome(statusCode: 401) == .forgotten)
    }

    @Test func aPCThatCannotBeReachedKeepsTheMac() {
        #expect(CompanionClient.forgetOutcome(statusCode: 502) == .unreachable)
        #expect(CompanionClient.forgetOutcome(statusCode: nil) == .unreachable)
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

    @Test func theLeaseTellsThePCTheStatsChoice() throws {
        for share in [true, false] {
            let body = try #require(CompanionClient.leaseBody(sharesStats: share))
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Bool])
            #expect(json == ["share_usage_stats": share])
        }
    }

    @Test func aDroppedRequestIsRetriedNotTheEnd() {
        #expect(CompanionClient.leaseOutcome(statusCode: nil) == .unreachable)
        #expect(CompanionClient.leaseOutcome(statusCode: 500) == .unreachable)
        #expect(CompanionClient.leaseOutcome(statusCode: 503) == .unreachable)
    }
}

/// A Mac the PC already trusts sees other Macs' requests with their codes.
struct CompanionWaitingTests {
    @Test func waitingMacsAreReadWithTheirCodes() {
        let body: [String: Any] = ["waiting": [["mac_id": "mac-b", "mac_name": "Raptor", "code": "123456"]]]
        #expect(CompanionClient.waiting(from: body)
            == [CompanionClient.WaitingMac(macID: "mac-b", macName: "Raptor", code: "123456")])
    }

    @Test func malformedEntriesAreDropped() {
        let body: [String: Any] = ["waiting": [
            ["mac_id": "", "mac_name": "A", "code": "123456"],
            ["mac_id": "b", "mac_name": "B", "code": "12345"],
            ["mac_id": "c", "mac_name": "C", "code": "12345x"],
            ["mac_id": "d", "mac_name": "D"]
        ]]
        #expect(CompanionClient.waiting(from: body).isEmpty)
        #expect(CompanionClient.waiting(from: [:]).isEmpty)
    }

    @Test func theAlertNamesTheMacThePcAndTheSpacedCode() {
        let den = Host(id: "pc-1", name: "den", customName: "Den PC", localAddress: "192.0.2.10",
                       manualAddress: nil, apps: [], lastConnected: nil, serverCertPEM: nil,
                       appVersion: nil, macAddress: nil)
        let approval = AppModel.approval(.init(macID: "mac-b", macName: "Raptor", code: "123456"), on: den)
        #expect(approval == WaitingApproval(hostID: "pc-1", pcName: "Den PC", macID: "mac-b",
                                            macName: "Raptor", code: "123 456"))
    }
}
