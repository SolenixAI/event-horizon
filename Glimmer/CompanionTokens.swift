//
//  CompanionTokens.swift
//
//  Companion tokens in one mode-0600 file beside Identity. The keychain is read once, to migrate.
//

import Foundation
import LocalAuthentication
import Security

/// The companion tokens this Mac holds, one per PC. Each PC's certificate fingerprint sits beside its token.
enum CompanionTokens {
    private static let shared = CompanionTokenStore(directory: companionFolder,
                                                    legacy: LoginKeychainCompanionTokens())

    static func save(_ token: String, fingerprint: String, forHost hostID: String) {
        shared.save(token, fingerprint: fingerprint, forHost: hostID)
    }

    static func token(forHost hostID: String) -> String? {
        shared.token(forHost: hostID)
    }

    static func fingerprint(forHost hostID: String) -> String? {
        shared.fingerprint(forHost: hostID)
    }

    static func delete(forHost hostID: String) {
        shared.delete(forHost: hostID)
    }

    /// `~/Library/Application Support/Event Horizon/Companion/`, the same root Identity and PinnedHosts use.
    private static let companionFolder: URL = AppDataFolders.root.appendingPathComponent("Companion", isDirectory: true)
}

/// Everything the token file holds, plus whether the keychain-era items were already copied over.
struct CompanionTokenFile: Codable, Equatable {
    struct Host: Codable, Equatable {
        var token: String?
        var fingerprint: String?
    }

    var migrated = false
    var hosts: [String: Host] = [:]
}

/// The keychain-era items as a copy source. Reads are silent: an item that would need a prompt is skipped.
protocol CompanionLegacyKeychain: Sendable {
    /// Account name to value, for each item the keychain gives up without a prompt.
    func readable() -> [String: String]
    /// Deletes every legacy item.
    func removeAll()
}

/// Token file at `<directory>/tokens.json`, mode 0600 in a 0700 folder. The first use copies any
/// legacy keychain items into the file, then deletes them. The keychain is never touched after that.
final class CompanionTokenStore: @unchecked Sendable {
    /// Invariant: `lock` guards every read and write of the file, so one store is safe to share across threads.
    private let lock = NSLock()
    private let legacy: CompanionLegacyKeychain
    private static let fingerprintSuffix = ".fingerprint"

    let fileURL: URL

    init(directory: URL, legacy: CompanionLegacyKeychain) {
        fileURL = directory.appendingPathComponent("tokens.json", isDirectory: false)
        self.legacy = legacy
    }

    func save(_ token: String, fingerprint: String, forHost hostID: String) {
        lock.withLock {
            var state = current()
            state.hosts[hostID] = CompanionTokenFile.Host(token: token, fingerprint: fingerprint)
            persist(state)
        }
    }

    func token(forHost hostID: String) -> String? {
        lock.withLock { current().hosts[hostID]?.token }
    }

    func fingerprint(forHost hostID: String) -> String? {
        lock.withLock { current().hosts[hostID]?.fingerprint }
    }

    func delete(forHost hostID: String) {
        lock.withLock {
            var state = current()
            state.hosts[hostID] = nil
            persist(state)
        }
    }

    /// The file as it stands, after the one-time copy from the keychain if that has not run yet.
    private func current() -> CompanionTokenFile {
        let state = read() ?? CompanionTokenFile()
        return state.migrated ? state : migrate(state)
    }

    private func migrate(_ start: CompanionTokenFile) -> CompanionTokenFile {
        var state = start
        for (account, value) in legacy.readable() {
            if account.hasSuffix(Self.fingerprintSuffix) {
                let host = String(account.dropLast(Self.fingerprintSuffix.count))
                state.hosts[host, default: CompanionTokenFile.Host()].fingerprint = value
            } else {
                state.hosts[account, default: CompanionTokenFile.Host()].token = value
            }
        }
        state.migrated = true
        // The copy must reach the file before the keychain items go. If the write fails, the items stay for a retry.
        guard persist(state) else { return state }
        legacy.removeAll()
        return state
    }

    private func read() -> CompanionTokenFile? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CompanionTokenFile.self, from: data)
    }

    @discardableResult
    private func persist(_ state: CompanionTokenFile) -> Bool {
        guard let data = try? JSONEncoder().encode(state) else { return false }
        return (try? FileIdentityStore.writeOwnerOnly(data, to: fileURL)) != nil
    }
}

/// The login-keychain items the keychain-era build wrote, one per PC plus one fingerprint per PC.
/// Every query forbids UI, so an item that would prompt is skipped instead of shown.
struct LoginKeychainCompanionTokens: CompanionLegacyKeychain {
    static let service = AppDataFolders.keychainService(
        "dev.solenix.eventhorizon.companion", bundleIdentifier: AppDataFolders.bundleIdentifier)

    func readable() -> [String: String] {
        let context = Self.silentContext()
        var values: [String: String] = [:]
        for account in accounts(context) {
            if let value = value(account: account, context: context) {
                values[account] = value
            }
        }
        return values
    }

    func removeAll() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: Self.service,
                                    kSecUseAuthenticationContext as String: Self.silentContext()]
        SecItemDelete(query as CFDictionary)
    }

    private func accounts(_ context: LAContext) -> [String] {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: Self.service,
                                    kSecMatchLimit as String: kSecMatchLimitAll,
                                    kSecReturnAttributes as String: true,
                                    kSecUseAuthenticationContext as String: context]
        var items: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
              let rows = items as? [[String: Any]] else { return [] }
        return rows.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    private func value(account: String, context: LAContext) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: Self.service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne,
                                    kSecUseAuthenticationContext as String: context]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func silentContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }
}
