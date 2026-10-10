//
//  DataFolderMigrationTests.swift
//
//  The one-time moves from Glimmer's folders to Event Horizon's: the Application
//  Support folder (identity, pinned PCs, companion tokens) and the Logs folder.
//  Every test works in its own scratch folder, never the real one.
//

import Foundation
import Testing
@testable import Glimmer

struct DataFolderMigrationTests {

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dfm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, _ url: URL, mode: Int = 0o644) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    private func read(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private func mode(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)??.intValue
    }

    private func names(_ dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// The Glimmer folder as an older build left it: identity, pinned PC and tokens.
    private func oldFolder(in root: URL) throws -> URL {
        let old = root.appendingPathComponent("Glimmer", isDirectory: true)
        try write("cert-pem", old.appendingPathComponent("Identity/client-cert.pem"), mode: 0o600)
        try write("key-pem", old.appendingPathComponent("Identity/client-key.pem"), mode: 0o600)
        try write("pinned-pem", old.appendingPathComponent("PinnedHosts/host-1.pem"), mode: 0o600)
        try write("{\"hosts\":{}}", old.appendingPathComponent("Companion/tokens.json"), mode: 0o600)
        return old
    }

    private func newFolder(in root: URL) -> URL {
        root.appendingPathComponent("Event Horizon", isDirectory: true)
    }

    // MARK: Application Support folder

    @Test func testRunsNeverUseTheRealDataFolder() {
        let path = AppDataFolders.root.path
        #expect(!path.contains("/Library/Application Support/"))
        #expect(path.contains("Event Horizon tests"))
    }

    @Test func movesTheWholeFolderAndRemovesTheOldOne() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try oldFolder(in: root)
        let new = newFolder(in: root)

        #expect(DataFolderMigration.moveFolder(from: old, to: new) == .moved)

        #expect(read(new.appendingPathComponent("Identity/client-cert.pem")) == "cert-pem")
        #expect(read(new.appendingPathComponent("Identity/client-key.pem")) == "key-pem")
        #expect(read(new.appendingPathComponent("PinnedHosts/host-1.pem")) == "pinned-pem")
        #expect(read(new.appendingPathComponent("Companion/tokens.json")) == "{\"hosts\":{}}")
        #expect(!exists(old))
        #expect(names(root) == ["Event Horizon"])
    }

    @Test func keepsOwnerOnlyPermissionsOnTheSecrets() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try oldFolder(in: root)
        let new = newFolder(in: root)

        _ = DataFolderMigration.moveFolder(from: old, to: new)

        #expect(mode(new.appendingPathComponent("Identity/client-key.pem")) == 0o600)
        #expect(mode(new.appendingPathComponent("Companion/tokens.json")) == 0o600)
    }

    @Test func anInterruptedCopyNeverBecomesTheNewFolder() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try oldFolder(in: root)
        let new = newFolder(in: root)
        // A copy that died half way: a staging folder holding a partial file.
        try write("partial", root.appendingPathComponent("Event Horizon.migrating-DEAD/Identity/client-cert.pem"))

        #expect(DataFolderMigration.moveFolder(from: old, to: new) == .moved)

        #expect(read(new.appendingPathComponent("Identity/client-cert.pem")) == "cert-pem")
        #expect(names(root) == ["Event Horizon"])
    }

    @Test func aCopyThatFailsVerificationKeepsTheOldFolderAndWritesNoNewFolder() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try oldFolder(in: root)
        let new = newFolder(in: root)

        let outcome = DataFolderMigration.moveFolder(from: old, to: new) { src, dst in
            try FileManager.default.copyItem(at: src, to: dst)
            try Data("corrupt".utf8).write(to: dst.appendingPathComponent("Identity/client-cert.pem"))
        }

        #expect(outcome == .failed)
        #expect(read(old.appendingPathComponent("Identity/client-cert.pem")) == "cert-pem")
        #expect(names(root) == ["Glimmer"])
    }

    @Test func aCopyThatThrowsKeepsTheOldFolder() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try oldFolder(in: root)

        let outcome = DataFolderMigration.moveFolder(from: old, to: newFolder(in: root)) { _, _ in
            throw CocoaError(.fileWriteOutOfSpace)
        }

        #expect(outcome == .failed)
        #expect(read(old.appendingPathComponent("Companion/tokens.json")) == "{\"hosts\":{}}")
        #expect(names(root) == ["Glimmer"])
    }

    @Test func completesAMoveWhoseOldFolderWasNotRemoved() throws {
        // The rename happened, then the app stopped before the old folder went.
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try oldFolder(in: root)
        let new = newFolder(in: root)
        try FileManager.default.copyItem(at: old, to: new)

        #expect(DataFolderMigration.moveFolder(from: old, to: new) == .moved)

        #expect(!exists(old))
        #expect(read(new.appendingPathComponent("Identity/client-cert.pem")) == "cert-pem")
    }

    @Test func neverOverwritesANewFolderThatDiffersFromTheOldOne() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try oldFolder(in: root)
        let new = newFolder(in: root)
        try write("newer-cert", new.appendingPathComponent("Identity/client-cert.pem"), mode: 0o600)

        #expect(DataFolderMigration.moveFolder(from: old, to: new) == .conflict)

        #expect(read(new.appendingPathComponent("Identity/client-cert.pem")) == "newer-cert")
        #expect(read(old.appendingPathComponent("Identity/client-cert.pem")) == "cert-pem")
        #expect(exists(old))
    }

    @Test func doesNothingWithoutAnOldFolder() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(DataFolderMigration.moveFolder(from: root.appendingPathComponent("Glimmer"),
                                               to: newFolder(in: root)) == .nothingToMove)
        #expect(names(root).isEmpty)
    }

    @Test func aSecondRunIsANoOp() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try oldFolder(in: root)
        let new = newFolder(in: root)

        #expect(DataFolderMigration.moveFolder(from: old, to: new) == .moved)
        #expect(DataFolderMigration.moveFolder(from: old, to: new) == .nothingToMove)
        #expect(read(new.appendingPathComponent("Identity/client-cert.pem")) == "cert-pem")
    }

    // MARK: Logs folder

    @Test func movesLogsIntoEventHorizonFolderWithTheNewPrefix() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("Glimmer", isDirectory: true)
        try write("diag", old.appendingPathComponent("glimmer-2026-10-09T10:00:00Z.log"))
        try write("telemetry", old.appendingPathComponent("telemetry-2026-10-09T10:00:00Z.ndjson"))
        try write("asan", old.appendingPathComponent("asan.log.123"))
        let new = newFolder(in: root)

        #expect(DataFolderMigration.moveLogs(from: old, to: new) == .moved)

        #expect(names(new) == ["asan.log.123",
                               "event-horizon-2026-10-09T10:00:00Z.log",
                               "telemetry-2026-10-09T10:00:00Z.ndjson"])
        #expect(read(new.appendingPathComponent("event-horizon-2026-10-09T10:00:00Z.log")) == "diag")
        #expect(!exists(old))
    }

    @Test func logNamesChangeOnlyTheOldPrefix() {
        #expect(DataFolderMigration.logFileName("glimmer-a.log") == "event-horizon-a.log")
        #expect(DataFolderMigration.logFileName("telemetry-a.ndjson") == "telemetry-a.ndjson")
        #expect(DataFolderMigration.logFileName("notglimmer-a.log") == "notglimmer-a.log")
    }

    @Test func aLogAlreadyMovedWithTheSameBytesIsDroppedFromTheOldFolder() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("Glimmer", isDirectory: true)
        try write("same", old.appendingPathComponent("glimmer-a.log"))
        let new = newFolder(in: root)
        try write("same", new.appendingPathComponent("event-horizon-a.log"))

        #expect(DataFolderMigration.moveLogs(from: old, to: new) == .moved)

        #expect(names(new) == ["event-horizon-a.log"])
        #expect(!exists(old))
    }

    @Test func aLogWithDifferentBytesAlreadyThereIsKeptInTheOldFolder() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("Glimmer", isDirectory: true)
        try write("old", old.appendingPathComponent("glimmer-a.log"))
        let new = newFolder(in: root)
        try write("new", new.appendingPathComponent("event-horizon-a.log"))

        #expect(DataFolderMigration.moveLogs(from: old, to: new) == .conflict)

        #expect(read(old.appendingPathComponent("glimmer-a.log")) == "old")
        #expect(read(new.appendingPathComponent("event-horizon-a.log")) == "new")
    }

    @Test func aSecondLogMoveIsANoOp() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("Glimmer", isDirectory: true)
        try write("diag", old.appendingPathComponent("glimmer-a.log"))
        let new = newFolder(in: root)

        #expect(DataFolderMigration.moveLogs(from: old, to: new) == .moved)
        #expect(DataFolderMigration.moveLogs(from: old, to: new) == .nothingToMove)
    }
}
