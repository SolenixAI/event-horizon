//
//  ScratchDefaults.swift
//
//  Cleans up a test's own preferences domain. `removePersistentDomain` clears the
//  values but leaves an empty plist in ~/Library/Preferences, so the file goes too.
//

import Foundation

enum ScratchDefaults {

    /// Clears the domain `name`, flushes the cache, and deletes the plist file.
    static func drop(_ name: String) {
        let defaults = UserDefaults(suiteName: name)
        defaults?.removePersistentDomain(forName: name)
        defaults?.synchronize()
        CFPreferencesSynchronize(name as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(name).plist")
        try? FileManager.default.removeItem(at: plist)
    }
}
