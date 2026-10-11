//
//  CrashReportsTests.swift
//
//  A macOS crash report becomes one PostHog exception with the crashed thread's
//  frames, and nothing identifying (paths, the crash reporter key) survives.
//

import Foundation
import Testing
@testable import Glimmer

@MainActor
struct CrashReportsTests {
    private static let header = #"{"app_name":"Event Horizon","bundleID":"dev.solenix.eventhorizon","#
        + #""timestamp":"2026-10-10 18:36:45.00 -0230","#
        + #""app_version":"2026.10.8","os_version":"macOS 26.7 (25G224)"}"#
    private static let body = #"{"exception":{"type":"EXC_BREAKPOINT","signal":"SIGTRAP"},"#
        + #""termination":{"indicator":"Trace/BPT trap: 5","reasons":["/Users/someone/secret"]},"#
        + #""faultingThread":0,"threads":[{"frames":[{"imageOffset":4660,"symbol":"AppModel.stream()","#
        + #""imageIndex":0,"sourceFile":"/Users/someone/src/AppModel+Streaming.swift","sourceLine":120},"#
        + #"{"imageOffset":10,"imageIndex":1}]}],"usedImages":[{"name":"Event Horizon","#
        + #""path":"/Applications/Event Horizon.app"},{"name":"libsystem_kernel.dylib"}],"#
        + #""procPath":"/Users/someone/x","crashReporterKey":"SECRET-KEY"}"#
    private static let report = header + "\n" + body

    private static func parse(bundleID: String = "dev.solenix.eventhorizon") -> [String: Any]? {
        CrashReports.exceptionProperties(report: report, bundleID: bundleID, appName: "Event Horizon")
    }

    @Test func reportBecomesOneException() throws {
        let properties = try #require(Self.parse())
        let list = try #require(properties["$exception_list"] as? [[String: Any]])
        let exception = try #require(list.first)
        #expect(exception["type"] as? String == "EXC_BREAKPOINT SIGTRAP")
        #expect(exception["value"] as? String == "Trace/BPT trap: 5")
        let stack = try #require(exception["stacktrace"] as? [String: Any])
        let frames = try #require(stack["frames"] as? [[String: Any]])
        #expect(frames.count == 2)
        // Innermost frame last, the app's own frame marked in_app with its file's name only.
        #expect(frames.last?["function"] as? String == "AppModel.stream()")
        #expect(frames.last?["filename"] as? String == "AppModel+Streaming.swift")
        #expect(frames.last?["in_app"] as? Bool == true)
        #expect(frames.first?["function"] as? String == "libsystem_kernel.dylib + 0xa")
        #expect(frames.first?["in_app"] as? Bool == false)
    }

    @Test func nothingIdentifyingSurvives() throws {
        let properties = try #require(Self.parse())
        let data = try JSONSerialization.data(withJSONObject: properties)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("/Users/"))
        #expect(!text.contains("SECRET-KEY"))
        #expect(!text.contains("/Applications/"))
    }

    @Test func anotherAppsReportIsIgnored() {
        #expect(Self.parse(bundleID: "com.example.other") == nil)
    }

    @Test func onlyNewReportsForThisAppAreRead() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = folder.appendingPathComponent("Event Horizon-old.ips")
        try Self.report.write(to: old, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_791_666_000)], ofItemAtPath: old.path)
        try Self.report.write(to: folder.appendingPathComponent("Event Horizon-new.ips"), atomically: true, encoding: .utf8)
        try Self.report.write(to: folder.appendingPathComponent("Other-new.ips"), atomically: true, encoding: .utf8)
        let crashed = try #require(CrashReports.crashDate(report: Self.report))
        let found = CrashReports.newReports(in: folder, appName: "Event Horizon", since: crashed.addingTimeInterval(-1))
        #expect(found.count == 1)
        // A report written after opting in, of a crash from before it, stays behind.
        #expect(CrashReports.newReports(in: folder, appName: "Event Horizon", since: crashed).isEmpty)
    }

    @Test func theCrashTimeComesFromTheReport() throws {
        let crashed = try #require(CrashReports.crashDate(report: Self.report))
        #expect(crashed == Date(timeIntervalSince1970: 1_791_666_405))
    }
}
