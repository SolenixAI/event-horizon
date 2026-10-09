//
//  AppModel+Desk.swift
//
//  Citadel's Home, the PC on the desk: what the screen does when clicked,
//  switching from one app to another, and the games' cover art (Sunshine's
//  /appasset, cached on disk per PC).
//

import AppKit
import Foundation

/// Cover art on disk: ~/Library/Caches/<bundle id>/covers/<PC>/<app>.png.
enum CoverArt {
    static func url(hostID: String, appID: Int) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let bundle = Bundle.main.bundleIdentifier ?? "dev.solenix.citadel"
        return caches.appendingPathComponent(bundle).appendingPathComponent("covers")
            .appendingPathComponent(hostID, isDirectory: true).appendingPathComponent("\(appID).png")
    }

    static func image(hostID: String, appID: Int) -> NSImage? {
        NSImage(contentsOf: url(hostID: hostID, appID: appID))
    }
}

extension AppModel {

    /// The PC's Desktop app: the desk's own screen.
    func desktopApp(of host: Host) -> LibraryApp? {
        host.apps.first { $0.name.caseInsensitiveCompare("Desktop") == .orderedSame }
    }

    /// The shelf: every visible app that is not the Desktop.
    func shelfApps(of host: Host) -> [LibraryApp] {
        host.apps.filter { !$0.hidden && $0.id != desktopApp(of: host)?.id }
    }

    /// The app Sunshine says is running on the PC, by name.
    func runningAppName(on host: Host) -> String? {
        guard let status = hostLiveStatus, status.hostID == host.id,
              case .streamingApp(let name) = status.state else { return nil }
        return name
    }

    /// Click on the PC's screen: back into a stream that is on the desk, or
    /// open the Desktop (waking the PC or pairing again first when it needs it).
    func openDesk(_ host: Host) {
        if isStreaming {
            if nativeStreamBackgrounded { resumeStreamWindow() }
            return
        }
        switch menuBarPrimaryAction {
        case .wake: wakeHost(host, thenConnect: true)
        case .waking: cancelWake(host)
        case .pairAgain: requestPairing(for: host)
        default:
            if let desktop = desktopApp(of: host) { requestStream(app: desktop, on: host) } else { streamHeroApp() }
        }
    }

    /// Open an app from the shelf. The one already on screen comes back; a
    /// different one replaces it (Sunshine runs one app at a time).
    func openFromShelf(_ app: LibraryApp, on host: Host) {
        guard isStreaming else { requestStream(app: app, on: host); return }
        if lastLaunchAttempt?.app.id == app.id {
            if nativeStreamBackgrounded { resumeStreamWindow() }
            return
        }
        stopStreamFromMenu(source: "Home")
        Task { @MainActor [weak self] in
            for _ in 0..<100 where self?.isStreaming == true {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard let self, !self.isStreaming else { return }
            self.requestStream(app: app, on: host)
        }
    }

    /// Fetch the PC's app list and any cover it has not cached yet. Quiet:
    /// a PC that is asleep or has no art just leaves the shelf's own tiles.
    func ensureCoverArt(for host: Host) async {
        _ = await refreshAppList(for: host)
        guard let fresh = hosts.first(where: { $0.id == host.id }) else { return }
        let missing = fresh.apps.filter {
            !FileManager.default.fileExists(atPath: CoverArt.url(hostID: fresh.id, appID: $0.id).path)
        }
        guard !missing.isEmpty else { return }
        let client = NetworkClient(server: nativeServerInfo(for: fresh))
        var landed = false
        for app in missing {
            guard let data = try? await client.appAsset(appID: app.id) else { continue }
            let url = CoverArt.url(hostID: fresh.id, appID: app.id)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? data.write(to: url, options: .atomic)) != nil { landed = true }
        }
        await client.shutdown()
        if landed { coverArtRevision &+= 1 }
    }
}
