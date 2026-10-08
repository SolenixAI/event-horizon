//
//  PointerPolicy.swift
//
//  Who owns the pointer, decided by what the user opened. The PC's Desktop is
//  a Mac window: the cursor stays free and absolute, and Mac shortcuts map to
//  their PC twins (InputForwarder+CommandTranslate.swift). Any other app is a
//  game: relative aim, locked only while the stream window is key on the
//  active Space. Pure and testable without a window or a session.
//

import Foundation

/// How the stream window treats the Mac pointer. Snapshotted into
/// `StreamConfig` at session start.
public enum PointerPolicy: Sendable, Equatable {
    /// The cursor is never hidden, warped or trapped; it is sent as absolute positions.
    case free
    /// Relative aim: the pointer is captured while the stream is in front.
    case lock

    /// The app name Sunshine lists for the PC's own desktop.
    static let desktopAppName = "desktop"

    /// `.free` for the PC's Desktop (trimmed, any case), `.lock` for every other app.
    static func forApp(named name: String) -> PointerPolicy {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(desktopAppName) == .orderedSame ? .free : .lock
    }
}
