import Foundation
import Security

final class HelperService: NSObject, NSXPCListenerDelegate, GlimmerHelperProtocol {
    private let suppressor: AWDLSuppressor

    // Every XPC peer must be our bundle id, Apple-anchored, and signed by the team
    // that signed this helper. main.swift hands this to the listener, so the OS
    // rejects any other process before it can reach this root helper. The team is
    // read from the helper's own signature, so each builder's signed build trusts
    // its own app. A helper with no team trusts no one.
    static func clientRequirement(team: String?) -> String? {
        guard let team, team.count == 10,
              team.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) })
        else { return nil }
        return "identifier \"dev.solenix.eventhorizon\" and anchor apple generic "
            + "and certificate leaf[subject.OU] = \"\(team)\""
    }

    /// The team identifier in this process's own code signature, if it has one.
    static func ownTeam() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                == errSecSuccess,
              let dict = info as? [String: Any]
        else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    init(suppressor: AWDLSuppressor) {
        self.suppressor = suppressor
        super.init()
    }

    // MARK: Listener

    // Only peers that already passed the listener's code-signing requirement
    // (set in main.swift) are ever offered here.
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: GlimmerHelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    // MARK: GlimmerHelperProtocol

    func setAWDLDown(_ down: Bool, reason: String, reply: @escaping @Sendable (Bool) -> Void) {
        // Defensively bound the reason string so even a verified peer can't
        // fill the log with megabytes of garbage.
        let bounded = String(reason.prefix(128)).replacingOccurrences(of: "\n", with: " ")
        // Fail-safe: if the peer holding awdl0 down vanishes (quit/crash/lost
        // connection) without releasing, restore it. Only that peer's exit counts,
        // so another client that connects and leaves can't cut a stream short.
        NSXPCConnection.current()?.invalidationHandler = down ? { [suppressor] in
            suppressor.setSuppressing(false, reason: "app-disconnected")
        } : nil
        suppressor.setSuppressing(down, reason: bounded)
        // Park: report verified state so the app's `suppressing` flag can't
        // claim a still-up radio (the heartbeat reconfirms as the async down
        // lands).
        if down {
            reply(!suppressor.isInterfaceUp())
        } else {
            suppressor.afterPendingChanges { reply(true) }
        }
    }

    func currentStatus(reply: @escaping (Bool, Date?) -> Void) {
        reply(suppressor.suppressing, suppressor.suppressionSince)
    }

    func ping(reply: @escaping (String) -> Void) {
        reply("glimmer-helper-ok")
    }

    func reSuppressCount(reply: @escaping (UInt64) -> Void) {
        reply(suppressor.reSuppressCount)
    }
}
