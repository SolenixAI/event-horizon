//
//  UpdaterConfigurationTests.swift
//
//  Pins the update settings in Info.plist, the one source of truth for the feed,
//  the key and the install policy: checks run daily and never install without asking.
//

#if canImport(Sparkle)
import Foundation
import Testing

struct UpdaterConfigurationTests {
    private static let infoPlistURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // GlimmerTests
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("Glimmer/Info.plist")

    private static func infoPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: infoPlistURL)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(object as? [String: Any])
    }

    @Test func feedIsTheLatestReleaseAsset() throws {
        let plist = try Self.infoPlist()
        #expect(plist["SUFeedURL"] as? String
            == "https://github.com/SolenixAI/event-horizon/releases/latest/download/appcast.xml")
    }

    @Test func checksRunDailyFromLaunch() throws {
        let plist = try Self.infoPlist()
        #expect(plist["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(plist["SUScheduledCheckInterval"] as? Int == 86_400)
    }

    @Test func updatesAreNeverInstalledWithoutAsking() throws {
        let plist = try Self.infoPlist()
        #expect(plist["SUAutomaticallyUpdate"] as? Bool == false)
        #expect(plist["SUAllowsAutomaticUpdates"] as? Bool == false)
    }

    @Test func publicKeyIsAnEd25519PublicKey() throws {
        let plist = try Self.infoPlist()
        let key = try #require(plist["SUPublicEDKey"] as? String)
        #expect(key == "cPwm0aRVkUvDfPqi5G38cJ1dwKfvNwvyFzHy+vrus5c=")
        #expect(Data(base64Encoded: key)?.count == 32)
    }

    @Test func installerServiceStaysOffForAnUnsandboxedApp() throws {
        let plist = try Self.infoPlist()
        #expect((plist["SUEnableInstallerLauncherService"] as? Bool ?? false) == false)
    }
}
#endif
