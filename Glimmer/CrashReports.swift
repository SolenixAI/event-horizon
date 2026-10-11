//
//  CrashReports.swift
//
//  Sends the crash reports macOS already writes for this app as PostHog
//  exceptions, once each, only while usage stats are on and only for crashes
//  after they were turned on. Paths, arguments and machine IDs stay behind.
//

import Foundation

@MainActor
enum CrashReports {
    static let sinceKey = "crashReportsSince"
    /// Tests point this at a fixture folder.
    static var directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DiagnosticReports")
    private static let maxPerLaunch = 10
    private nonisolated static let maxFrames = 50

    /// Opting in starts the clock, so a crash from before consent is never sent.
    static func startCounting() { UsageStats.defaults.set(Date(), forKey: sinceKey) }
    static func stopCounting() { UsageStats.defaults.removeObject(forKey: sinceKey) }

    /// At launch, each crash newer than the clock becomes one `$exception` event.
    /// The clock is read again on the main actor, so a switch flipped meanwhile counts.
    static func sendNew() {
        guard UsageStats.defaults.bool(forKey: UsageStats.enabledKey) else { return }
        guard let since = UsageStats.defaults.object(forKey: sinceKey) as? Date else {
            startCounting()
            return
        }
        let folder = directory
        let appName = ProcessInfo.processInfo.processName
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        Task.detached(priority: .utility) {
            let reports = newReports(in: folder, appName: appName, since: since)
            await MainActor.run { send(reports, bundleID: bundleID, appName: appName) }
        }
    }

    /// Up to 10 a launch, oldest first; the clock stops at the last one sent, so
    /// the rest go next launch.
    private static func send(_ reports: [(date: Date, text: String)], bundleID: String, appName: String) {
        guard UsageStats.defaults.bool(forKey: UsageStats.enabledKey),
              let since = UsageStats.defaults.object(forKey: sinceKey) as? Date else { return }
        let due = reports.filter { $0.date > since }.prefix(maxPerLaunch)
        for report in due {
            guard let properties = exceptionProperties(
                report: report.text, bundleID: bundleID, appName: appName) else { continue }
            UsageStats.capture("$exception", properties)
        }
        if let last = due.last { UsageStats.defaults.set(last.date, forKey: sinceKey) }
    }

    /// Reports of this app whose crash, as the report itself dates it, is newer than `since`.
    /// The file's own date only narrows the search: macOS can write a report late.
    nonisolated static func newReports(in folder: URL, appName: String, since: Date) -> [(date: Date, text: String)] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: Array(keys))) ?? []
        return files.compactMap { url -> (date: Date, text: String)? in
            guard url.lastPathComponent.hasPrefix("\(appName)-"), url.pathExtension == "ips",
                  let written = try? url.resourceValues(forKeys: keys).contentModificationDate, written > since,
                  let text = try? String(contentsOf: url, encoding: .utf8),
                  let crashed = crashDate(report: text), crashed > since else { return nil }
            return (crashed, text)
        }
        .sorted { $0.date < $1.date }
    }

    /// The crash time from the report's header line, e.g. "2026-10-10 18:36:45.00 -0230".
    nonisolated static func crashDate(report: String) -> Date? {
        guard let line = report.split(separator: "\n", maxSplits: 1).first,
              let stamp = json(line)?["timestamp"] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"
        return formatter.date(from: stamp)
    }

    /// An .ips report is a header line, then a JSON body. Keeps the exception, the
    /// short reason macOS gives, and the crashed thread's frames, innermost last.
    nonisolated static func exceptionProperties(report: String, bundleID: String, appName: String) -> [String: Any]? {
        let parts = report.split(separator: "\n", maxSplits: 1)
        guard parts.count == 2, let header = json(parts[0]), header["bundleID"] as? String == bundleID,
              let body = json(parts[1]), let exception = body["exception"] as? [String: Any] else { return nil }
        let images = (body["usedImages"] as? [[String: Any]] ?? []).map { $0["name"] as? String ?? "?" }
        let threads = body["threads"] as? [[String: Any]] ?? []
        let faulting = body["faultingThread"] as? Int ?? 0
        let frames = threads.indices.contains(faulting) ? threads[faulting]["frames"] as? [[String: Any]] ?? [] : []
        let type = [exception["type"], exception["signal"]].compactMap { $0 as? String }.joined(separator: " ")
        let reason = (body["termination"] as? [String: Any])?["indicator"] as? String
        let stack = frames.prefix(maxFrames).reversed().map { frame($0, images: images, appName: appName) }
        return [
            "$exception_list": [[
                "type": type,
                "value": reason ?? type,
                "mechanism": ["handled": false, "synthetic": false, "type": "macos-crash-report"],
                "stacktrace": ["type": "raw", "frames": stack]
            ]],
            "$exception_level": "fatal",
            "crash_app_version": header["app_version"] as? String ?? "",
            "crash_os_version": header["os_version"] as? String ?? ""
        ]
    }

    private nonisolated static func frame(_ frame: [String: Any], images: [String], appName: String) -> [String: Any] {
        let index = frame["imageIndex"] as? Int ?? -1
        let module = images.indices.contains(index) ? images[index] : "?"
        let offset = String(frame["imageOffset"] as? Int ?? 0, radix: 16)
        var out: [String: Any] = [
            "platform": "custom", "lang": "swift", "resolved": true, "module": module,
            "function": frame["symbol"] as? String ?? "\(module) + 0x\(offset)", "in_app": module == appName
        ]
        if let file = frame["sourceFile"] as? String { out["filename"] = (file as NSString).lastPathComponent }
        if let line = frame["sourceLine"] as? Int { out["lineno"] = line }
        return out
    }

    private nonisolated static func json(_ text: Substring) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }
}
