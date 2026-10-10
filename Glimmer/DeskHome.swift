//
//  DeskHome.swift
//
//  Event Horizon's Home: your PC on the desk. The PC's screen is the hero; a click
//  grows it into the window (the live stream surface sits on this frame,
//  StreamWindow+Embedded.swift), and ⌘W puts it back here, still running.
//  Under the screen: the PC's name and state, what is running on it, and a
//  shelf of its games with their own cover art.
//

import AppKit
import SwiftUI

/// The logo's blue: live, running, the PC's own light. Gold (the accent) is
/// for what you press.
extension Color {
    static let horizonBlue = Color(red: 0.227, green: 0.627, blue: 1.0)
}

struct DeskHome: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.scenePhase) private var scenePhase
    /// The bezel's width: the status row and the shelf line up with it.
    @State private var deskWidth: CGFloat = 0
    /// Mirrors StreamWindow.homeShowing, which is not observable: it is copied
    /// here on each change so Home re-renders when the stream leaves or returns to the desk.
    @State private var streamOnDesk = StreamWindow.homeShowing

    /// How the space's live flow runs. Hidden under Reduce Motion. Frozen while
    /// this window is not key or the app is in the background, and while a
    /// stream fills the window (on the desk, the stream's bitrate still flows).
    private var spaceFlow: SpaceFlow {
        if reduceMotion { return .hidden }
        if controlActiveState != .key || scenePhase != .active { return .paused }
        if model.isStreaming && !streamOnDesk { return .paused }
        return .running
    }

    var body: some View {
        VStack(spacing: 0) {
            ConnectBanner()
                .padding(.bottom, 10)
            if let host = model.selectedHost {
                DeskScreen(host: host, width: $deskWidth)
                    .layoutPriority(1)
                Group {
                    DeskStatus(host: host)
                        .padding(.top, 16)
                    let games = model.shelfApps(of: host)
                    if !games.isEmpty {
                        GameShelf(host: host, games: games, deskWidth: deskWidth)
                            .padding(.top, 18)
                    }
                    if model.hidPermissionPadName != nil {
                        ControllerPermissionRow()
                            .padding(.top, 12)
                    }
                }
                .frame(width: deskWidth > 0 ? deskWidth : nil)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 38)
        .padding(.bottom, 22)
        .frame(minWidth: 640, idealWidth: 1040, maxWidth: .infinity,
               minHeight: 600, idealHeight: 780, maxHeight: .infinity)
        // Home's surroundings: the deep-space field behind the PC, under the
        // whole window, title bar included. The live flow is anchored to the bezel.
        .backgroundPreferenceValue(BezelFrameKey.self) { bezel in
            GeometryReader { proxy in
                SpaceBackdrop(flow: spaceFlow, bezel: bezel.map { proxy[$0] },
                              sample: { await model.liveFlowReading() })
            }
            .ignoresSafeArea()
        }
        // No toolbar, so full screen is all PC; Settings (and ⌘,) sits on the
        // title-bar line, across from the window buttons.
        .overlay(alignment: .topTrailing) {
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .help("Settings")
            .accessibilityLabel("Settings")
            .padding(.top, 1)
            .padding(.trailing, 10)
            .ignoresSafeArea(.container, edges: .top)
        }
        .onReceive(NotificationCenter.default.publisher(for: StreamWindow.homeShowingDidChange)) { _ in
            streamOnDesk = StreamWindow.homeShowing
        }
        .task(id: model.selectedHost?.id) {
            guard let host = model.selectedHost else { return }
            await model.ensureCoverArt(for: host)
        }
    }
}

// MARK: - The PC's screen

/// The PC's bezel frame on Home, so the backdrop can anchor its trace to it.
struct BezelFrameKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// The PC as a screen on the desk. Its frame is where the live stream sits
/// while Home shows; without a stream it says what a click will do.
private struct DeskScreen: View {
    let host: Host
    @Binding var width: CGFloat
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    private var aspect: CGFloat {
        let w = CGFloat(model.effectiveWidth), h = CGFloat(model.effectiveHeight)
        return w > 0 && h > 0 ? w / h : 16.0 / 10.0
    }

    /// The stream itself covers the screen (on the desk or grown).
    private var streamCovers: Bool {
        guard model.isStreaming else { return false }
        if case .connecting = model.streamPhase { return false }
        return true
    }

    var body: some View {
        Button { model.openDesk(host) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black)
                if !streamCovers { idleFace }
            }
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
            .padding(5)
            .background {
                // The bezel: glass around the screen, the one raised object on Home.
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 17))
            }
            .overlay {
                // Light catching the bezel's top edge, so it reads as raised on a
                // dark window too.
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(colorScheme == .dark ? 0.28 : 0.6), .white.opacity(0)],
                                                 startPoint: .top, endPoint: .center), lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .opacity(hovering ? 1 : 0)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.18), radius: 18, y: 10)
            .anchorPreference(key: BezelFrameKey.self, value: .bounds) { $0 }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.2), value: hovering)
        // The live stream sits exactly on the screen (inside the bezel).
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { box in
            let screen = Self.screenRect(box: box, aspect: aspect)
            StreamWindow.deskFrame = screen
            width = screen.width + 10
        }
        .help(helpText)
        .accessibilityLabel("\(host.displayName) screen")
        .accessibilityValue(stateLine.title)
        .accessibilityHint(helpText)
    }

    /// The black screen's rect in window space: fitted to the aspect inside
    /// the button's box, inset by the 5pt bezel.
    static func screenRect(box outer: CGRect, aspect: CGFloat) -> CGRect {
        let box = outer.insetBy(dx: 5, dy: 5)
        guard box.width > 0, box.height > 0 else { return .zero }
        var size = CGSize(width: box.width, height: box.width / aspect)
        if size.height > box.height { size = CGSize(width: box.height * aspect, height: box.height) }
        return CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    private var stateLine: (symbol: String, title: String, detail: String, busy: Bool) {
        if model.isStreaming, case .connecting = model.streamPhase {
            let name = model.lastLaunchAttempt?.app.name ?? "Desktop"
            return ("", "Opening \(name)…", "", true)
        }
        switch model.menuBarPrimaryAction {
        case .wake: return ("moon.zzz", "\(host.displayName) is asleep", "Click to wake it and open the Desktop", false)
        case .waking: return ("", "Waking \(host.displayName)…", "Click to stop waiting", true)
        case .pairAgain: return ("lock.trianglebadge.exclamationmark", "Pair again", "\(host.displayName) has a new certificate", false)
        default:
            if let running = model.runningAppName(on: host) {
                return ("cursorarrow.click.2", running, "Running on your PC · Click to open it", false)
            }
            return ("cursorarrow.click.2", "Desktop", "Click to open your PC", false)
        }
    }

    /// No tooltip while the PC fills the window: this view is under it.
    private var helpText: String {
        guard model.isStreaming else { return stateLine.detail }
        return model.nativeStreamBackgrounded ? "Back to your PC" : ""
    }

    private var idleFace: some View {
        VStack(spacing: 10) {
            if stateLine.busy {
                ProgressView().controlSize(.large).environment(\.colorScheme, .dark)
            } else {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                    .shadow(color: Color.horizonBlue.opacity(0.35), radius: 24)
            }
            Text(stateLine.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            if !stateLine.detail.isEmpty {
                Text(stateLine.detail)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(24)
    }
}

// MARK: - Status line

/// The PC's name (the switcher with more than one), its state, what is
/// running on it, and the stream's specs.
private struct DeskStatus: View {
    let host: Host
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(host.displayName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                SpecChipsRow()
            }
            if let running = model.appOnScreen(on: host),
               running.caseInsensitiveCompare("Desktop") != .orderedSame {
                RunningLabel(name: running)
            }
            Spacer(minLength: 12)
            ReadinessChip()
        }
        .hostContextMenu(host)
    }
}

/// "Running Farthest Frontier": the PC's own light, in blue.
private struct RunningLabel: View {
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.horizonBlue).frame(width: 7, height: 7)
            Text("Running \(name)")
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.horizonBlue)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Game shelf

/// The PC's games as covers on a glass shelf. A click opens the game in the
/// window; the one on screen says so.
private struct GameShelf: View {
    let host: Host
    let games: [LibraryApp]
    let deskWidth: CGFloat
    @Environment(AppModel.self) private var model

    /// Covers grow with the desk: about nine across, never smaller than 100 pt.
    private var coverWidth: CGFloat { min(max((deskWidth - 28) / 9 - 14, 100), 150) }

    var body: some View {
        // As wide as its covers when they fit, else the desk's width and scrolling.
        ViewThatFits(in: .horizontal) {
            row
            ScrollView(.horizontal) { row }
                .scrollIndicators(.never)
                // The trailing covers fade out: there is more shelf to scroll to.
                .mask {
                    LinearGradient(stops: [.init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(games) { app in
                CoverTile(host: host, app: app, width: coverWidth)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct CoverTile: View {
    let host: Host
    let app: LibraryApp
    let width: CGFloat
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    private var isLaunching: Bool {
        guard model.isStreaming, case .connecting = model.streamPhase else { return false }
        return model.lastLaunchAttempt?.app.id == app.id
    }

    private var isOnScreen: Bool { model.appOnScreen(on: host) == app.name }

    var body: some View {
        Button { model.openFromShelf(app, on: host) } label: {
            VStack(alignment: .leading, spacing: 6) {
                cover
                    .frame(width: width, height: width * 1.5)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(isOnScreen ? Color.horizonBlue : Color.accentColor, lineWidth: 2)
                            .opacity(isOnScreen || hovering ? 1 : 0)
                    }
                    .overlay {
                        if isLaunching {
                            ProgressView().controlSize(.regular).environment(\.colorScheme, .dark)
                        }
                    }
                    .shadow(color: .black.opacity(hovering ? 0.35 : 0), radius: 10, y: 6)
                    .scaleEffect(hovering ? 1.03 : 1)
                Text(app.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isOnScreen ? Color.horizonBlue : .primary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: width, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.18), value: hovering)
        .help(isOnScreen ? "Back to \(app.name)" : "Play \(app.name)")
        .accessibilityLabel(app.name)
        .accessibilityValue(isOnScreen ? "Running" : "")
        .accessibilityHint(isOnScreen ? "Opens it in the window" : "Starts it on \(host.displayName)")
    }

    @ViewBuilder private var cover: some View {
        let _ = model.coverArtRevision
        if let image = CoverArt.image(hostID: host.id, appID: app.id) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(colors: [Color.horizonBlue.opacity(0.55), Color.accentColor.opacity(0.45)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: app.systemImage)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Controller permission

/// A pad macOS doesn't recognise needs Input Monitoring. A quiet row, not an
/// alert: the user answers when they want.
private struct ControllerPermissionRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "gamecontroller")
                .foregroundStyle(.secondary)
            Text("\(model.hidPermissionPadName ?? "Your controller") needs Input Monitoring to work with Event Horizon.")
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Allow…") { model.continueHIDPermission() }
            Button("Not Now") { model.dismissHIDPermission() }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}
