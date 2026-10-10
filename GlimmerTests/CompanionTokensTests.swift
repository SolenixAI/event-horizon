//
//  CompanionTokensTests.swift
//
//  The token store on a temp folder and a fake keychain. Never the real folder or keychain.
//

import Foundation
import Testing
@testable import Glimmer

/// Stands in for the login keychain and counts every call, so a test can
/// prove the keychain is not touched once migration has run.
final class FakeLegacyKeychain: CompanionLegacyKeychain, @unchecked Sendable {
    var items: [String: String]
    private(set) var readCalls = 0
    private(set) var removeCalls = 0

    init(_ items: [String: String] = [:]) { self.items = items }

    func readable() -> [String: String] {
        readCalls += 1
        return items
    }

    func removeAll() {
        removeCalls += 1
        items = [:]
    }
}

struct CompanionTokensTests {

    private func tmpDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("companion-\(UUID().uuidString)", isDirectory: true)
    }

    private func store(_ dir: URL, legacy: FakeLegacyKeychain = FakeLegacyKeychain()) -> CompanionTokenStore {
        CompanionTokenStore(directory: dir, legacy: legacy)
    }

    private func mode(_ url: URL) -> Int? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let number = attrs[.posixPermissions] as? NSNumber else { return nil }
        return number.intValue & 0o777
    }

    @Test func savedTokenAndFingerprintComeBack() {
        let s = store(tmpDir())
        s.save("tok-1", fingerprint: "fp-1", forHost: "pc-a")
        #expect(s.token(forHost: "pc-a") == "tok-1")
        #expect(s.fingerprint(forHost: "pc-a") == "fp-1")
    }

    @Test func aNewStoreOnTheSameFolderSeesTheSave() {
        let dir = tmpDir()
        store(dir).save("tok-1", fingerprint: "fp-1", forHost: "pc-a")
        let next = store(dir)
        #expect(next.token(forHost: "pc-a") == "tok-1")
        #expect(next.fingerprint(forHost: "pc-a") == "fp-1")
    }

    @Test func hostsAreKeptApart() {
        let s = store(tmpDir())
        s.save("tok-a", fingerprint: "fp-a", forHost: "pc-a")
        s.save("tok-b", fingerprint: "fp-b", forHost: "pc-b")
        #expect(s.token(forHost: "pc-a") == "tok-a")
        #expect(s.token(forHost: "pc-b") == "tok-b")
        #expect(s.fingerprint(forHost: "pc-b") == "fp-b")
    }

    @Test func anUnknownHostHasNothing() {
        let s = store(tmpDir())
        #expect(s.token(forHost: "nobody") == nil)
        #expect(s.fingerprint(forHost: "nobody") == nil)
    }

    @Test func deleteForgetsOnlyThatHost() {
        let s = store(tmpDir())
        s.save("tok-a", fingerprint: "fp-a", forHost: "pc-a")
        s.save("tok-b", fingerprint: "fp-b", forHost: "pc-b")
        s.delete(forHost: "pc-a")
        #expect(s.token(forHost: "pc-a") == nil)
        #expect(s.fingerprint(forHost: "pc-a") == nil)
        #expect(s.token(forHost: "pc-b") == "tok-b")
    }

    @Test func tokenFileIsOwnerOnly() {
        let s = store(tmpDir())
        s.save("tok-1", fingerprint: "fp-1", forHost: "pc-a")
        #expect(mode(s.fileURL) == 0o600)
    }

    @Test func folderIsOwnerOnly() {
        let dir = tmpDir()
        store(dir).save("tok-1", fingerprint: "fp-1", forHost: "pc-a")
        #expect(mode(dir) == 0o700)
    }

    @Test func legacyKeychainItemsAreCopiedOnFirstUseAndDeleted() {
        let legacy = FakeLegacyKeychain(["pc-a": "tok-old", "pc-a.fingerprint": "fp-old"])
        let s = store(tmpDir(), legacy: legacy)
        #expect(s.token(forHost: "pc-a") == "tok-old")
        #expect(s.fingerprint(forHost: "pc-a") == "fp-old")
        #expect(legacy.removeCalls == 1)
        #expect(legacy.items.isEmpty)
    }

    @Test func migratedFileIsOwnerOnly() {
        let legacy = FakeLegacyKeychain(["pc-a": "tok-old"])
        let s = store(tmpDir(), legacy: legacy)
        _ = s.token(forHost: "pc-a")
        #expect(mode(s.fileURL) == 0o600)
    }

    @Test func migrationRunsOnceAndTheKeychainIsNeverTouchedAfterwards() {
        let dir = tmpDir()
        let legacy = FakeLegacyKeychain(["pc-a": "tok-old"])
        _ = store(dir, legacy: legacy).token(forHost: "pc-a")
        let readsAfterMigration = legacy.readCalls

        let next = store(dir, legacy: legacy)
        _ = next.token(forHost: "pc-a")
        next.save("tok-b", fingerprint: "fp-b", forHost: "pc-b")
        next.delete(forHost: "pc-a")

        #expect(legacy.readCalls == readsAfterMigration)
        #expect(legacy.removeCalls == 1)
    }

    @Test func legacyItemThatCannotBeReadSilentlyLeavesNoToken() {
        let legacy = FakeLegacyKeychain([:])
        let s = store(tmpDir(), legacy: legacy)
        #expect(s.token(forHost: "pc-a") == nil)
        #expect(legacy.removeCalls == 1)
    }

    @Test func saveBeforeMigrationKeepsLegacyItemsOfOtherHosts() {
        let legacy = FakeLegacyKeychain(["pc-a": "tok-old"])
        let s = store(tmpDir(), legacy: legacy)
        s.save("tok-b", fingerprint: "fp-b", forHost: "pc-b")
        #expect(s.token(forHost: "pc-a") == "tok-old")
        #expect(s.token(forHost: "pc-b") == "tok-b")
    }

    @Test func deleteBeforeMigrationForgetsTheLegacyToken() {
        let legacy = FakeLegacyKeychain(["pc-a": "tok-old", "pc-a.fingerprint": "fp-old"])
        let s = store(tmpDir(), legacy: legacy)
        s.delete(forHost: "pc-a")
        #expect(s.token(forHost: "pc-a") == nil)
        #expect(s.fingerprint(forHost: "pc-a") == nil)
    }
}
