//  CommandLineToolInstaller.swift
//  Event Horizon › Install Command Line Tool…: links `event-horizon` into /usr/local/bin for
//  installs Homebrew didn't make, after the administrator prompt macOS shows.

import AppKit

@MainActor
enum CommandLineToolInstaller {

    nonisolated static let linkPath = "/usr/local/bin/event-horizon"

    /// The `glimmer` link earlier builds made. The install replaces it while it still points at our app.
    nonisolated static let legacyLinkPath = "/usr/local/bin/glimmer"

    /// Where an `event-horizon` link on the default PATH already sits: Homebrew's, then ours.
    nonisolated static let knownLinks = ["/opt/homebrew/bin/event-horizon", linkPath]

    static func install() {
        guard let executable = Bundle.main.executablePath else { return }
        if let existing = existingLink(to: executable) {
            show("The event-horizon command is already installed.",
                 detail: "It's at \(existing). Run event-horizon help in Terminal to see what it can do.")
            return
        }
        // A copy run from a disk image or Downloads moves or vanishes; the link would dangle.
        guard isInApplications(Bundle.main.bundlePath) else {
            show("Move Event Horizon to Applications first.",
                 detail: "The command runs this copy of Event Horizon, so it needs to stay where it is.")
            return
        }
        var error: NSDictionary?
        NSAppleScript(source: linkScript(to: executable, retiringLegacy: legacyLinkIsOurs()))?
            .executeAndReturnError(&error)
        if let error {
            // -128: the administrator prompt was cancelled.
            guard (error[NSAppleScript.errorNumber] as? Int) != -128 else { return }
            let reason = error[NSAppleScript.errorMessage] as? String ?? "unknown"
            Diag.warn("Install Command Line Tool failed: \(reason, privacy: .private)", "CLI")
            show("Couldn't install the event-horizon command.", detail: "Try again with an administrator account.")
            return
        }
        show("The event-horizon command is installed.", detail: "Run event-horizon help in Terminal to see what it can do.")
    }

    /// The first known link that resolves to this executable, if any.
    nonisolated static func existingLink(to executable: String, among candidates: [String] = knownLinks) -> String? {
        let target = resolved(executable) ?? executable
        return candidates.first { resolved($0) == target }
    }

    nonisolated static func isInApplications(_ bundlePath: String, home: String = NSHomeDirectory()) -> Bool {
        bundlePath.hasPrefix("/Applications/") || bundlePath.hasPrefix(home + "/Applications/")
    }

    /// True when a link points into an app bundle this command came from, Glimmer's or Event Horizon's.
    nonisolated static func isOurLegacyLink(_ destination: String) -> Bool {
        destination.contains("/Glimmer.app/") || destination.contains("/Event Horizon.app/")
    }

    nonisolated static func legacyLinkIsOurs() -> Bool {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: legacyLinkPath) else {
            return false
        }
        return isOurLegacyLink(destination)
    }

    /// `do shell script` with the path quoted once for the shell and once for AppleScript.
    nonisolated static func linkScript(to executable: String, retiringLegacy: Bool) -> String {
        let shellQuoted = "'" + executable.replacingOccurrences(of: "'", with: "'\\''") + "'"
        var command = "mkdir -p /usr/local/bin && ln -sf \(shellQuoted) \(linkPath)"
        if retiringLegacy { command += " && rm -f \(legacyLinkPath)" }
        let appleScriptQuoted = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(appleScriptQuoted)\" with administrator privileges"
    }

    private nonisolated static func resolved(_ path: String) -> String? {
        guard let real = realpath(path, nil) else { return nil }
        defer { free(real) }
        return String(cString: real)
    }

    private static func show(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        NSApp.activate()
        alert.runModal()
    }
}
