//
//  AWDLHelperManager+Signing.swift
//
//  What Settings says when the network helper cannot help, and the signing check
//  that tells a refusal from a helper that did not start.
//

import Foundation
import Security

extension AWDLHelperManager {
    static let refusalMessage = "The network helper didn't accept this copy of Event Horizon, so Wi-Fi streams "
        + "may stutter. Use the copy in Applications, signed by the same developer as the helper."
    /// A team-signed app is never refused, so failing calls mean launchd could not start
    /// the helper. The heartbeat registers it again once; this shows if that fails too.
    static let notRunningMessage = "The network helper couldn't start, so Wi-Fi streams may stutter. "
        + "Event Horizon set it up again and it still failed. Restart your Mac, then turn this off and on."

    /// This copy's signing team, read from its own signature (nil when unsigned or ad hoc).
    nonisolated static func ownTeam() -> String? {
        var code: SecCode?, staticCode: SecStaticCode?, info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                == errSecSuccess, let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
