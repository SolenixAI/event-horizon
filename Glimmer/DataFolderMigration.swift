//
//  DataFolderMigration.swift
//
//  One-time moves of Glimmer's data folders to Event Horizon's names. A folder is
//  copied into a staging sibling, verified byte for byte, renamed into place, and
//  only then is the old folder removed. A failed copy leaves the old folder intact.
//

import Foundation
import os.log

enum DataFolderMigration {

    enum Outcome: Equatable {
        case nothingToMove
        case moved
        /// Both folders hold different bytes for one file. Nothing is removed.
        case conflict
        /// The copy or the move failed. The old folder is intact.
        case failed
    }

    private static let log = Logger(subsystem: "dev.solenix.eventhorizon", category: "DataFolders")
    private static let legacyLogPrefix = "glimmer-"
    private static let logPrefix = "event-horizon-"

    /// Copies `old` to a staging folder beside `new`, verifies it, then renames it to `new`.
    @discardableResult
    static func moveFolder(from old: URL, to new: URL,
                           copy: (URL, URL) throws -> Void = DataFolderMigration.copyTree) -> Outcome {
        let fm = FileManager.default
        removeStaging(beside: new)
        guard fm.fileExists(atPath: old.path) else { return .nothingToMove }
        if fm.fileExists(atPath: new.path) {
            if files(under: new).isEmpty { try? fm.removeItem(at: new) } else {
                // The new folder is the one in use. Remove the old one only when it holds nothing the new one lacks.
                guard covers(new, old) else {
                    log.error("data folder conflict: old copy differs from the Event Horizon folder; old folder kept")
                    return .conflict
                }
                try? fm.removeItem(at: old)
                return .moved
            }
        }
        let staging = new.deletingLastPathComponent()
            .appendingPathComponent(stagingPrefix(for: new) + UUID().uuidString, isDirectory: true)
        do {
            try copy(old, staging)
        } catch {
            try? fm.removeItem(at: staging)
            log.error("data folder copy failed: \(error.localizedDescription)")
            return .failed
        }
        guard sameTree(staging, old) else {
            try? fm.removeItem(at: staging)
            log.error("data folder copy did not verify; old folder kept")
            return .failed
        }
        do {
            try fm.moveItem(at: staging, to: new)
        } catch {
            try? fm.removeItem(at: staging)
            log.error("data folder move failed: \(error.localizedDescription)")
            return .failed
        }
        // If this removal fails, both folders match and the next launch removes the old one.
        try? fm.removeItem(at: old)
        log.notice("moved data folder to Event Horizon")
        return .moved
    }

    /// Moves the files of the Glimmer Logs folder into Event Horizon's, renaming `glimmer-` to `event-horizon-`.
    @discardableResult
    static func moveLogs(from old: URL, to new: URL) -> Outcome {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: old, includingPropertiesForKeys: nil),
              !entries.isEmpty else {
            try? fm.removeItem(at: old)
            return .nothingToMove
        }
        try? fm.createDirectory(at: new, withIntermediateDirectories: true)
        var kept = false
        for entry in entries {
            let target = new.appendingPathComponent(logFileName(entry.lastPathComponent))
            if fm.fileExists(atPath: target.path) {
                if fm.contents(atPath: target.path) == fm.contents(atPath: entry.path) {
                    try? fm.removeItem(at: entry)
                } else {
                    kept = true
                }
            } else {
                do { try fm.moveItem(at: entry, to: target) } catch { kept = true }
            }
        }
        if kept { return .conflict }
        try? fm.removeItem(at: old)
        return .moved
    }

    /// The name a Glimmer log has in Event Horizon's Logs folder. Other names are unchanged.
    static func logFileName(_ name: String) -> String {
        guard name.hasPrefix(legacyLogPrefix) else { return name }
        return logPrefix + name.dropFirst(legacyLogPrefix.count)
    }

    /// Copies a whole folder tree. `FileManager.copyItem` keeps the permission bits.
    static func copyTree(_ src: URL, _ dst: URL) throws {
        try FileManager.default.copyItem(at: src, to: dst)
    }

    // MARK: Verification

    private static func stagingPrefix(for new: URL) -> String {
        new.lastPathComponent + ".migrating-"
    }

    /// Removes folders an interrupted copy left beside `new`. Only names this migration makes can match.
    private static func removeStaging(beside new: URL) {
        let fm = FileManager.default
        let parent = new.deletingLastPathComponent()
        let prefix = stagingPrefix(for: new)
        for entry in (try? fm.contentsOfDirectory(atPath: parent.path)) ?? [] where entry.hasPrefix(prefix) {
            try? fm.removeItem(at: parent.appendingPathComponent(entry))
        }
    }

    /// True when `dst` holds the same files as `src`, and the same file count.
    private static func sameTree(_ dst: URL, _ src: URL) -> Bool {
        covers(dst, src) && files(under: dst).count == files(under: src).count
    }

    /// True when every file under `src` is in `dst` with the same bytes and permissions.
    private static func covers(_ dst: URL, _ src: URL) -> Bool {
        let fm = FileManager.default
        for (relative, srcFile) in files(under: src) {
            let dstFile = relative.reduce(dst) { $0.appendingPathComponent($1) }
            guard let want = fm.contents(atPath: srcFile.path),
                  let got = fm.contents(atPath: dstFile.path), want == got,
                  permissions(srcFile) == permissions(dstFile) else { return false }
        }
        return true
    }

    /// Regular files under `root`, keyed by their path components relative to it.
    private static func files(under folder: URL) -> [[String]: URL] {
        var found: [[String]: URL] = [:]
        // The enumerator reports /private/var paths, so the root is resolved the same way (realpath).
        let root = realPath(folder)
        let base = root.pathComponents.count
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return found
        }
        for case let file as URL in walker {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            found[Array(file.pathComponents.dropFirst(base))] = file
        }
        return found
    }

    private static func realPath(_ url: URL) -> URL {
        guard let real = realpath(url.path, nil) else { return url }
        defer { free(real) }
        return URL(fileURLWithPath: String(cString: real), isDirectory: true)
    }

    private static func permissions(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)??.intValue
    }
}

/// Where this build keeps its data. The shipped app owns the shared names and the
/// one-time moves from Glimmer. Any other bundle identifier gets its own folder, Logs
/// folder and keychain service, so a test copy never reads, moves or deletes real data.
enum AppDataFolders {

    static let shippedBundleIdentifier = "dev.solenix.eventhorizon"

    /// True under XCTest: every root is then a scratch folder.
    private static var isTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static var scratchRoot: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Event Horizon tests \(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    }

    /// The bundle identifier this process runs under.
    static var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? shippedBundleIdentifier }

    /// True only for the shipped app. The legacy moves and keychain sweeps run here alone.
    static var isShippedBuild: Bool { !isTesting && isShipped(bundleIdentifier: bundleIdentifier) }

    static func isShipped(bundleIdentifier id: String) -> Bool { id == shippedBundleIdentifier }

    /// `Event Horizon` for the shipped app, `Event Horizon (<bundle id>)` for any other build.
    static func folderName(bundleIdentifier id: String) -> String {
        isShipped(bundleIdentifier: id) ? "Event Horizon" : "Event Horizon (\(id))"
    }

    /// The shipped service name, unchanged, or the same name with the bundle identifier added.
    static func keychainService(_ shippedService: String, bundleIdentifier id: String) -> String {
        isShipped(bundleIdentifier: id) ? shippedService : "\(shippedService).\(id)"
    }

    /// `<applicationSupport>/Event Horizon`, or its per-build sibling.
    static func dataRoot(bundleIdentifier id: String, applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent(folderName(bundleIdentifier: id), isDirectory: true)
    }

    /// `<library>/Logs/Event Horizon`, or its per-build sibling.
    static func logsDirectory(bundleIdentifier id: String, library: URL) -> URL {
        library.appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(folderName(bundleIdentifier: id), isDirectory: true)
    }

    /// The per-build Logs folder for this process. A scratch folder under XCTest.
    static let currentLogsDirectory: URL = {
        if isTesting { return scratchRoot.appendingPathComponent("Logs", isDirectory: true) }
        return logsDirectory(bundleIdentifier: bundleIdentifier,
                             library: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library"))
    }()

    /// The data folder for this process: identity, pinned PCs and companion tokens. The
    /// shipped app's first access moves the Glimmer folder in before anything reads it.
    static let root: URL = {
        if isTesting { return scratchRoot }
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let new = dataRoot(bundleIdentifier: bundleIdentifier, applicationSupport: base)
        if isShippedBuild {
            DataFolderMigration.moveFolder(from: base.appendingPathComponent("Glimmer", isDirectory: true), to: new)
        }
        return new
    }()
}
