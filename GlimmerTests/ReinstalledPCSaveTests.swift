//
//  ReinstalledPCSaveTests.swift
//
//  A PC that reinstalls Sunshine comes back with a new uuid and certificate. Saving
//  the new pairing must replace the old entry, not add a second one.
//

import Foundation
import Testing
@testable import Glimmer

/// A PC that reinstalled Sunshine pairs again with a new uuid and certificate. These
/// tests drive `saveHost` with fake defaults and check the saved PCs it leaves behind.
@MainActor
struct ReinstalledPCSaveTests {

    private typealias App = AppModel.PairedApp
    private static let oldID = "OLD-ID"
    private static let newID = "NEW-ID"
    private static let address = "100.64.0.5"
    private static let freshApps = [App(id: 7, name: "Fresh Game", hdr: false, hidden: false)]

    /// `domain`, emptied, holding one PC paired as `zephyr-citadel` under `oldID` at `address`,
    /// with one game stored. A custom name is set when given. Each test removes its domain.
    private func savedPC(_ domain: String, customName: String? = nil) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: domain))
        defaults.removePersistentDomain(forName: domain)
        defaults.set(1, forKey: "hosts.size")
        defaults.set("zephyr-citadel", forKey: "hosts.1.hostname")
        defaults.set(Self.oldID, forKey: "hosts.1.uuid")
        defaults.set(Self.address, forKey: "hosts.1.localaddress")
        defaults.set(Self.address, forKey: "hosts.1.manualaddress")
        defaults.set(false, forKey: "hosts.1.wol")
        if let customName {
            defaults.set(true, forKey: "hosts.1.customname")
            defaults.set(customName, forKey: "hosts.1.name")
        }
        #expect(AppModel.storeApps([App(id: 1, name: "Old Game", hdr: false, hidden: false)],
                                   hostID: Self.oldID, in: defaults))
        return defaults
    }

    /// Saves the reinstalled PC at `address` through the model, as pairing does.
    private func pairReinstalled(into defaults: UserDefaults, at address: String = address) throws {
        try AppModel().saveHost(uuid: Self.newID, hostname: "zephyr-citadel", address: address,
                                serverCertPEM: nil, appVersion: nil, apps: Self.freshApps,
                                macAddress: nil, defaults: defaults)
    }

    private func storedIDs(_ defaults: UserDefaults) -> [String] {
        (0..<defaults.integer(forKey: "hosts.size")).compactMap {
            defaults.string(forKey: "hosts.\($0 + 1).uuid")
        }.filter { !$0.isEmpty }
    }

    @Test func aReinstalledPCReplacesItsOldEntry() throws {
        let domain = "io.ugfugl.Glimmer.tests.reinstalled-replaces"
        let defaults = try savedPC(domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        try pairReinstalled(into: defaults)
        #expect(storedIDs(defaults) == [Self.newID])
        #expect(defaults.string(forKey: "hosts.1.hostname") == "zephyr-citadel")
        #expect(defaults.string(forKey: "hosts.1.apps.1.name") == "Fresh Game")
        #expect(defaults.integer(forKey: "hosts.1.apps.size") == 1)
    }

    @Test func theReplacementKeepsItsCustomNameAndWakeSetting() throws {
        let domain = "io.ugfugl.Glimmer.tests.reinstalled-keeps-name"
        let defaults = try savedPC(domain, customName: "Den PC")
        defer { defaults.removePersistentDomain(forName: domain) }
        try pairReinstalled(into: defaults)
        #expect(defaults.bool(forKey: "hosts.1.customname"))
        #expect(defaults.string(forKey: "hosts.1.name") == "Den PC")
        #expect(defaults.object(forKey: "hosts.1.wol") as? Bool == false)
    }

    @Test func aPCAtAnotherAddressIsNotReplaced() throws {
        let domain = "io.ugfugl.Glimmer.tests.reinstalled-other-address"
        let defaults = try savedPC(domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        try pairReinstalled(into: defaults, at: "192.168.1.20")
        #expect(storedIDs(defaults) == [Self.oldID, Self.newID])
    }
}
