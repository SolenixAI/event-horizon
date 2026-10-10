//
//  BuildMark.swift
//
//  Any build that isn't the shipped app says so, in its window and on its Dock
//  icon, so no one pairs or streams in a test copy by mistake. The mark comes from
//  the bundle identifier the build runs under, so a release can never carry it.
//

import SwiftUI

enum BuildMark {
    /// "Test build" for any bundle identifier but the shipped app's; nil for the app itself.
    static func label(bundleIdentifier id: String) -> String? {
        AppDataFolders.isShipped(bundleIdentifier: id) ? nil : "Test build"
    }

    /// The mark for this process.
    static var current: String? { label(bundleIdentifier: AppDataFolders.bundleIdentifier) }
}

/// The window's mark: a small glass capsule on the title-bar line, with the
/// caution dot the readiness chip uses. Nothing at all in the shipped app.
struct BuildMarkCapsule: View {
    var body: some View {
        if let mark = BuildMark.current {
            HStack(spacing: 6) {
                Circle().fill(Color.orange).frame(width: 7, height: 7)
                Text(mark).font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: .capsule)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(mark) of Event Horizon")
        }
    }
}
