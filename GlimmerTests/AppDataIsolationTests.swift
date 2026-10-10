//
//  AppDataIsolationTests.swift
//
//  A build keeps its data under its own bundle identifier. Only the shipped app
//  uses the shared names, so a test copy can never read, move or delete real data.
//

import Foundation
import Testing
@testable import Glimmer

struct AppDataIsolationTests {
    private static let shipped = "dev.solenix.eventhorizon"
    private static let testCopy = "dev.solenix.eventhorizon.updatetest"
    private static let base = URL(fileURLWithPath: "/Users/someone/Library/Application Support", isDirectory: true)
    private static let library = URL(fileURLWithPath: "/Users/someone/Library", isDirectory: true)

    @Test func shippedAppKeepsTheSharedFolders() {
        let root = AppDataFolders.dataRoot(bundleIdentifier: Self.shipped, applicationSupport: Self.base)
        #expect(root.lastPathComponent == "Event Horizon")
        let logs = AppDataFolders.logsDirectory(bundleIdentifier: Self.shipped, library: Self.library)
        #expect(logs.path == "/Users/someone/Library/Logs/Event Horizon")
    }

    @Test func testCopyGetsItsOwnDataRoot() {
        let shippedRoot = AppDataFolders.dataRoot(bundleIdentifier: Self.shipped, applicationSupport: Self.base)
        let copyRoot = AppDataFolders.dataRoot(bundleIdentifier: Self.testCopy, applicationSupport: Self.base)
        #expect(copyRoot != shippedRoot)
        #expect(copyRoot.lastPathComponent == "Event Horizon (\(Self.testCopy))")
        #expect(copyRoot.deletingLastPathComponent() == Self.base)
    }

    @Test func testCopyGetsItsOwnLogsFolder() {
        let shippedLogs = AppDataFolders.logsDirectory(bundleIdentifier: Self.shipped, library: Self.library)
        let copyLogs = AppDataFolders.logsDirectory(bundleIdentifier: Self.testCopy, library: Self.library)
        #expect(copyLogs != shippedLogs)
        #expect(copyLogs.path.hasPrefix("/Users/someone/Library/Logs/"))
    }

    @Test func testCopyGetsItsOwnKeychainService() {
        let shippedService = "dev.solenix.eventhorizon.companion"
        #expect(AppDataFolders.keychainService(shippedService, bundleIdentifier: Self.shipped) == shippedService)
        let copyService = AppDataFolders.keychainService(shippedService, bundleIdentifier: Self.testCopy)
        #expect(copyService != shippedService)
        #expect(copyService.hasPrefix(shippedService))
    }

    @Test func legacyMigrationsBelongToTheShippedAppOnly() {
        #expect(AppDataFolders.isShipped(bundleIdentifier: Self.shipped))
        #expect(!AppDataFolders.isShipped(bundleIdentifier: Self.testCopy))
    }
}
