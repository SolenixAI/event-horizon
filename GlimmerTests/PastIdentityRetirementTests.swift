//
//  PastIdentityRetirementTests.swift
//
//  A PC that reinstalled Sunshine before the Mac learned to replace its entry left a
//  second, dead entry behind. When the PC answers as itself, that past identity goes.
//

import Foundation
import Testing
@testable import Glimmer

/// Drives `retirePastIdentities(ofHost:defaults:)` with fake defaults holding two
/// saved PCs, and checks which entries remain.
@MainActor
struct PastIdentityRetirementTests {

    private static let liveID = "LIVE-ID"
    private static let ghostID = "GHOST-ID"
    private static let address = "192.168.4.157"

    /// `domain`, emptied, holding the ghost in slot 1 and the live PC in slot 2.
    private func twoEntries(_ domain: String, ghostHostname: String = "zephyr-citadel",
                            ghostAddress: String = address) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: domain))
        ScratchDefaults.drop(domain)
        defaults.set(2, forKey: "hosts.size")
        for (slot, id, hostname, address) in [(1, Self.ghostID, ghostHostname, ghostAddress),
                                              (2, Self.liveID, "zephyr-citadel", Self.address)] {
            defaults.set(hostname, forKey: "hosts.\(slot).hostname")
            defaults.set(id, forKey: "hosts.\(slot).uuid")
            defaults.set(address, forKey: "hosts.\(slot).localaddress")
            defaults.set(address, forKey: "hosts.\(slot).manualaddress")
        }
        return defaults
    }

    private func storedIDs(_ defaults: UserDefaults) -> [String] {
        (0..<defaults.integer(forKey: "hosts.size")).compactMap {
            defaults.string(forKey: "hosts.\($0 + 1).uuid")
        }.filter { !$0.isEmpty }
    }

    @Test func aPCAnsweringAsItselfRetiresItsPastIdentity() throws {
        let domain = "dev.solenix.eventhorizon.tests.past-identity-retired"
        let defaults = try twoEntries(domain)
        defer { ScratchDefaults.drop(domain) }
        AppModel().retirePastIdentities(ofHost: Self.liveID, defaults: defaults)
        #expect(storedIDs(defaults) == [Self.liveID])
    }

    @Test func aPCAtAnotherAddressStays() throws {
        let domain = "dev.solenix.eventhorizon.tests.past-identity-other-address"
        let defaults = try twoEntries(domain, ghostAddress: "192.168.4.200")
        defer { ScratchDefaults.drop(domain) }
        AppModel().retirePastIdentities(ofHost: Self.liveID, defaults: defaults)
        #expect(storedIDs(defaults) == [Self.ghostID, Self.liveID])
    }

    @Test func anotherPCAtTheSameAddressStays() throws {
        let domain = "dev.solenix.eventhorizon.tests.past-identity-other-name"
        let defaults = try twoEntries(domain, ghostHostname: "den-pc")
        defer { ScratchDefaults.drop(domain) }
        AppModel().retirePastIdentities(ofHost: Self.liveID, defaults: defaults)
        #expect(storedIDs(defaults) == [Self.ghostID, Self.liveID])
    }
}
