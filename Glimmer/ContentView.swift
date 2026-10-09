import SwiftUI
import AppKit

// MARK: - Main Window

struct MainWindow: View {
    @Environment(AppModel.self) private var model
    /// Lifted out of EmptyPairingState so the sheet survives the swap to
    /// ConnectSurface the instant pairing fills `model.hosts` - the sheet used
    /// to hang off the empty state itself and vanish mid-handshake success.
    @State private var showPair = false

    var body: some View {
        @Bindable var model = model
        return Group {
            if model.hosts.isEmpty {
                EmptyPairingState(showPair: $showPair)
            } else {
                DeskHome()
            }
        }
        .onAppear { model.setHIDDiscovery(true, for: .launcher) }
        .onDisappear { model.setHIDDiscovery(false, for: .launcher) }
        .sheet(isPresented: $showPair) {
            PairSheet().environment(model)
        }
        // Pair a PC… from the menu bar, and Pair Again… from the menu bar, the
        // Stream button, the banner and the Trust needed chip land here.
        .sheet(isPresented: $model.pairSheetShown) {
            PairSheet(repairing: model.pairSheetHost).environment(model)
        }
        // No .frame: forcing either axis to .infinity gives the window an
        // unbounded box to fill, and the only thing available to fill it with is
        // nothing. The content states its own size; the window follows it.
        .overlay(alignment: .top) {
            // Disconnect-beat toast - a brief, calm acknowledgement after a
            // stream ends instead of the launcher just snapping back.
            StreamEndedToast()
                .padding(.top, 16)
        }
        .navigationTitle("Citadel")
    }
}

/// The Stream menu: the launcher's one action in its words, where ⌘? finds it, and the PCs
/// on ⌘1-⌘9 (nine at most; ⌘0 reads as reset). PCs lock while streaming, since ⌘ stays with the Mac.
struct StreamMenu: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        primaryItem
        Button("Stop Streaming") { model.stopStreamFromMenu(source: "the Stream menu") }
            .disabled(!model.isStreaming || model.menuStopInProgress)
        if !model.hosts.isEmpty { Divider() }
        ForEach(Array(model.hosts.enumerated()), id: \.element.id) { index, host in
            Toggle(host.displayName, isOn: Binding(
                get: { model.selectedHost?.id == host.id }, set: { if $0 { model.selectHost(host) } }))
                .keyboardShortcut(index < 9 ? KeyboardShortcut(KeyEquivalent(Character("\(index + 1)"))) : nil)
                .disabled(model.isStreaming)
        }
    }

    /// The same resolver as the launcher and the menu bar, so all three offer one action.
    @ViewBuilder private var primaryItem: some View {
        let host = model.selectedHost
        switch model.menuBarPrimaryAction {
        case .stream(let app): Button("Stream \(app)") { model.streamHeroApp() }
        case .wake: Button("Wake and Connect") { if let host { model.wakeHost(host, thenConnect: true) } }
        case .waking: Button("Stop Waiting") { if let host { model.cancelWake(host) } }
        case .pairAgain:
            Button("Pair Again…") {
                model.requestPairing(for: host)
                openWindow(id: "main")
            }
        case .cancelConnection: Button("Cancel Connection") { model.cancelConnect() }
        case .backToStream:
            Button("Back to Stream") {
                if model.isMiniPlayer { model.toggleMiniPlayer() }
                model.resumeStreamWindow()
            }
        case .stopStreaming, .none: Button("Stream") {}.disabled(true)
        }
    }
}

// MARK: - Connect surface

/// The primary controls' surface: the accent lifted toward white at the top left and
/// deepened at the bottom right, opaque, so the app buttons and Stream are the violet on screen.
@MainActor
var accentSurfaceGradient: LinearGradient {
    LinearGradient(colors: [Color.accentColor.mix(with: .white, by: 0.10), Color.accentColor.mix(with: .black, by: 0.18)],
                   startPoint: .topLeading, endPoint: .bottomTrailing)
}

// NOTE: the readiness chip's composite-status model now lives with
// `ReadinessChip` in ContentView+ReadinessChip.swift, the menu-bar dropdown and
// the shared per-host right-click menu in ContentView+Menus.swift, and the
// morphing hero button in ContentView+StreamButton.swift (pointers kept on
// purpose).
