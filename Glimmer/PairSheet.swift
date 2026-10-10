//
//  PairSheet.swift
//
//  The "Pair a new PC" flow. Extracted from SettingsView (which was at its
//  file-length limit) and given a discover-first UX: the sheet opens to a live
//  mDNS list of PCs on the network (the Discovery actor, previously unwired),
//  the user picks one (or falls back to a manual address), and pairing then
//  auto-starts so the displayed PIN is immediately enterable on the host.
//
//  Also hosts CodeTiles + FloatingWindowLevel, both used only here.
//

import AppKit
import Network
import SwiftUI

/// The onboarding's hooks: the pairing steps report what happened and the flow moves on.
struct EmbeddedPairing {
    let chose: () -> Void
    let paired: () -> Void
    let back: () -> Void
    let next: () -> Void
}

struct PairSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    /// Set by the first-launch pass: no title, no window level, and the flow's own steps.
    var embedded: EmbeddedPairing?
    /// Set once the person has read the Mac-side explanation. Nothing is sent to the PC before it.
    @State private var pairingConfirmed = false
    @State private var hostnameOrIP: String
    /// The name discovery listed the PC under; nil for a typed address.
    @State private var pcName: String?
    @State private var pin: String = ""
    /// nil = still choosing a host; non-nil = a host was picked/entered and we
    /// move to the PIN/handshake step.
    @State private var chosen: Bool

    @State private var pairedHost: Host?
    @State private var pairingAttempt: PairingAttempt?
    @State private var pairingTask: Task<Void, Never>?
    private var paired: Bool { pairedHost != nil }

    /// Pair Again… for this PC until Back returns to the chooser; nil pairs a new one.
    @State private var rePairName: String?

    /// A typed address or a PC to pair again jumps straight to the PIN step,
    /// dialling what a stream dials; with neither the sheet starts on the chooser.
    init(initialAddress: String = "", repairing host: Host? = nil, embedded: EmbeddedPairing? = nil) {
        let address = host.map(AppModel.routeAddress) ?? initialAddress
        _hostnameOrIP = State(initialValue: address)
        _pcName = State(initialValue: host?.displayName)
        _chosen = State(initialValue: !address.isEmpty)
        _rePairName = State(initialValue: host?.displayName)
        self.embedded = embedded
    }

    /// The host we're pairing with, whitespace-trimmed. Empty means the user
    /// hasn't picked or typed one yet.
    private var trimmedHost: String {
        hostnameOrIP.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What the sheet calls the PC: its discovered name, else the address typed.
    private var pcLabel: String { pcName ?? trimmedHost }

    private var pairingFailed: Bool {
        if case .failure = model.pairingPhase { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if embedded == nil {
                Text(Self.title(paired: paired, chosen: chosen, rePairName: rePairName))
                    .font(.title2.bold())
                    .contentTransition(.opacity)
            }

            if paired {
                successBody
            } else if !chosen {
                HostChooser(selected: { addr, name in
                    hostnameOrIP = addr
                    pcName = name
                    chosen = true
                    embedded?.chose()
                })
            } else {
                pinBody
            }

            footer
        }
        .padding(embedded == nil ? 28 : 0)
        .frame(width: embedded == nil ? 480 : nil, alignment: .leading)
        // Float above all other Event Horizon windows so the PIN being read off isn't
        // hidden behind the launcher or Settings. Reverts on dismiss. Not in the pass.
        .background { if embedded == nil { FloatingWindowLevel() } }
        .onDisappear { cancelPairing() }
    }

    static func title(paired: Bool, chosen: Bool, rePairName: String?) -> String {
        if paired { return "Paired" }
        guard chosen else { return "Choose a PC" }
        return rePairName.map { "Pair \($0) again" } ?? "Pair a new PC"
    }

    @ViewBuilder private var successBody: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: reduceMotion ? false : paired)
            Text("\(pairedHost?.displayName ?? pcLabel) is ready to stream.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .sensoryFeedback(.success, trigger: paired)
        // Auto-close after a brief beat so the check + haptic register; select
        // the freshly-paired host so the launcher lands on it.
        .task(id: paired) {
            guard paired else { return }
            // No auto-dismiss: the success screen shows Done / "Stream Now" buttons,
            // and a 900ms auto-close made them unclickable. The user dismisses it.
            selectPairedHost()
            embedded?.paired()
        }
    }

    /// Before anything is sent to the PC, the Mac says what the PC will show and
    /// what to click. Then the code screen starts the pairing.
    @ViewBuilder private var pinBody: some View {
        if pairingConfirmed {
            pairStage
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Event Horizon shows a code here. If \(pcLabel) runs the companion, it shows the same code. "
                    + "Check that the two match, then click Allow on \(pcLabel).")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Without the companion, you enter a code in Sunshine on \(pcLabel) instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var pairStage: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let code = model.companionCode {
                // The PC made this code. The person checks it matches before Allow;
                // the Sunshine PIN is never shown on this path.
                CodeTiles(code: code)
                Text("Check that your PC shows \(CompanionClient.spaced(code)), then click Allow there.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if case .awaitingPin = model.pairingPhase, !model.pairingViaCompanion {
                Text("On \(pcLabel), enter this code")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                CodeTiles(code: pin)
                Text("On your PC, open Sunshine's web page and choose PIN, then type this code.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                // A headless PC has no screen to type on; its page opens here too.
                Button("Open Sunshine on This Mac") { model.openSunshinePINPage(forHost: trimmedHost) }
                    .buttonStyle(.link)
                    .font(.footnote)
                Text("Sunshine uses its own certificate, so your browser asks you to confirm before opening it.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            if pin.isEmpty { pin = model.generatePairingPIN() }
            // Showing the sheet IS the start of pairing: the handshake must be
            // open on the PC for the PIN to land.
            startPairing()
        }

        if let status = statusText, !paired {
            HStack(spacing: 8) {
                if pairingFailed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.orange)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(status).font(.callout)
                Spacer()
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))
        }
    }

    private var statusText: String? {
        switch model.pairingPhase {
        case .idle, .success: return nil
        case .connecting: return "Connecting to \(pcLabel)…"
        case .awaitingPin:
            return model.pairingViaCompanion ? "Waiting for Allow on \(pcLabel)…" : "Waiting for the code on \(pcLabel)…"
        case .failure(let failure): return failure.message(pc: pcLabel)
        }
    }

    @ViewBuilder private var footer: some View {
        HStack {
            if paired {
                if let embedded {
                    Spacer()
                    Button("Continue") { embedded.next() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(StreamButtonStyle())
                } else {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Stream Now") {
                        selectPairedHost()
                        model.streamDefaultApp()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(StreamButtonStyle())
                }
            } else if !chosen {
                Spacer()
                if let embedded {
                    Button("Back") { embedded.back() }
                } else {
                    Button("Cancel") { cancelPairing(); dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            } else {
                Spacer()
                Button("Back") { backToChooser(); embedded?.back() }
                if embedded == nil {
                    Button("Cancel") { cancelPairing(); dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                if !pairingConfirmed {
                    Button("Continue") { pairingConfirmed = true }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(StreamButtonStyle())
                } else if pairingFailed {
                    // Pairing starts with the code; a retry gets a fresh one.
                    Button("Try Again") {
                        pin = model.generatePairingPIN()
                        startPairing()
                    }
                    .buttonStyle(StreamButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func backToChooser() {
        cancelPairing()
        chosen = false
        rePairName = nil
        pin = ""
        pairingConfirmed = false
    }

    private func startPairing() {
        guard pairingTask == nil, !paired, !trimmedHost.isEmpty else { return }
        if pin.count != 4 { pin = model.generatePairingPIN() }
        let attempt = model.beginPairing(address: trimmedHost)
        pairingAttempt = attempt
        pairingTask = Task {
            let host = await model.pair(attempt: attempt, pin: pin)
            guard attempt.accepts(pairingAttempt, address: trimmedHost, cancelled: Task.isCancelled) else { return }
            pairedHost = host
            pairingTask = nil
        }
    }

    private func cancelPairing() {
        pairingTask?.cancel()
        pairingTask = nil
        if let pairingAttempt { model.cancelPairing(pairingAttempt) }
        pairingAttempt = nil
    }

    private func selectPairedHost() {
        if let pairedHost { model.selectHost(pairedHost) }
    }
}

// MARK: - Discover-first host chooser

/// Live mDNS list of PCs on the network + a manual-address fallback. Picking a
/// row (or submitting the manual field) hands the address, and the name when
/// discovery knew one, back via `selected`, which advances to the PIN step.
private struct HostChooser: View {
    let selected: (_ address: String, _ name: String?) -> Void
    @State private var found: [HostDiscovery.Discovered] = []
    /// macOS refused Event Horizon Local Network access, so nothing can be found.
    @State private var denied = false
    @State private var manual: String = ""
    @State private var showManual = false
    /// Flips ~7s into an empty discovery (Bonjour can be blocked on locked-down
    /// or guest networks). Swaps the spinner copy and auto-reveals the manual
    /// field so the user isn't stranded on a permanent "Looking for PCs...".
    @State private var discoveryStalled = false
    /// 0 until the person presses Continue on the explanation; then it counts up, and each
    /// bump restarts discovery (the app coming back to the front after a Local Network denial).
    @State private var discoveryRun = 0

    private static let localNetworkSettings =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")
    private static let hostSetupGuide =
        URL(string: "https://github.com/Se7enbrc/glimmer/blob/main/docs/HOST_SETUP.md")

    private var manualAddress: String? { AppModel.normalizedPCAddress(manual) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The explanation comes before the Local Network prompt: discovery
            // starts only on Continue, so the reason is already on screen.
            Text("Event Horizon looks for PCs running Sunshine on your local network; "
                + "macOS will ask to allow that.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if discoveryRun == 0 {
                Button("Continue") { discoveryRun = 1 }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(StreamButtonStyle())
            } else if denied {
                deniedNotice
            } else if found.isEmpty && !showManual && !discoveryStalled {
                // Spinner only while still actively looking. The stalled nudge is
                // hoisted out so it survives the auto-reveal of the manual field.
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Looking for PCs on your network…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else if found.isEmpty && discoveryStalled {
                stalledNotice
            }

            if !found.isEmpty {
                VStack(spacing: 8) {
                    ForEach(found) { host in
                        Button {
                            selected(host.host, host.displayName)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "display")
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(host.displayName).fontWeight(.medium)
                                    Text(host.host).font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular, in: .rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if discoveryRun > 0, showManual {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name or address")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("e.g. tower.local or 192.168.1.10", text: $manual)
                            .textFieldStyle(.roundedBorder)
                            .disableAutocorrection(true)
                            .onSubmit { submitManual() }
                        Button("Continue") { submitManual() }
                            .buttonStyle(StreamButtonStyle())
                            .disabled(manualAddress == nil)
                    }
                    if manualAddress == nil, !manual.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(PairingFailure.addressHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if discoveryRun > 0 {
                Button {
                    showManual = true
                } label: {
                    Label("Enter an address manually", systemImage: "keyboard")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
        .task(id: discoveryRun) {
            guard discoveryRun > 0 else { return }
            // Stream discovered hosts until the view goes away. HostDiscovery
            // is an actor; start() is actor-isolated so we await it, then
            // consume the stream for this run.
            let session = await HostDiscovery.shared.start()
            for await update in session.stream {
                found = update.hosts
                denied = update.denied
            }
            await HostDiscovery.shared.stop(run: session.run)
        }
        // Bonjour-hostile-network nudge: after ~7s with nothing found and the
        // user not already in the manual field, surface the fallback path.
        .task(id: discoveryRun) {
            guard discoveryRun > 0 else { return }
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if !Task.isCancelled, found.isEmpty, !showManual {
                discoveryStalled = true
                showManual = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if denied { discoveryRun += 1 }
        }
    }

    private var deniedNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Event Horizon isn't allowed to find devices on your network.", systemImage: "hand.raised.fill")
                .foregroundStyle(.secondary)
            if let url = Self.localNetworkSettings {
                Link("Open Local Network Settings", destination: url)
                    .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var stalledNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
                Text("No PCs found yet. Enter the address below.")
                    .foregroundStyle(.secondary)
            }
            // The usual cause: Sunshine isn't installed or running on the PC yet.
            if let url = Self.hostSetupGuide {
                Link("Set Up Your PC", destination: url)
                    .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func submitManual() {
        guard let addr = manualAddress else { return }
        selected(addr, nil)
    }
}

// MARK: - Window level

/// Raises its hosting NSWindow to `.floating` while present so the pairing
/// sheet stays above the launcher + Settings windows.
private struct FloatingWindowLevel: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.level = .floating }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { nsView.window?.level = .floating }
    }
}

// MARK: - PIN tiles

/// Display-only tiles showing a pairing code, one digit a tile: the PC's
/// six-digit code, or the Sunshine PIN the person types there. Static labels,
/// not input fields; the digits are generated here and read off, not typed.
private struct CodeTiles: View {
    let code: String
    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Array(code.enumerated()), id: \.offset) { _, ch in
                    Text(String(ch))
                        .font(.system(size: 40, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity, minHeight: 78)
                        .glassEffect(
                            .regular.tint(Color.accentColor.opacity(0.12)),
                            in: .rect(cornerRadius: 14)
                        )
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pairing code")
        .accessibilityValue(code.map(String.init).joined(separator: " "))
    }
}
