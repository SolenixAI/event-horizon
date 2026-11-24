//
//  DeskOutputPicker.swift
//
//  Dynamic host output device & display mode selector with liquid glass styling.
//

import AppKit
import SwiftUI

struct DeskOutputPicker: View {
    let host: Host
    @Environment(AppModel.self) private var model
    @State private var isSwitching = false

    private var outputs: [HostOutput] {
        model.outputs(for: host)
    }

    private var activeOutput: HostOutput? {
        model.activeOutput(for: host)
    }

    private var currentOutput: HostOutput {
        activeOutput ?? outputs.first ?? HostOutput.defaultVirtual
    }

    private var currentMode: DisplayMode? {
        model.activeMode(for: host)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                outputMenu
                if let active = activeOutput, active.modes.count > 1 {
                    modeMenu(for: active)
                }
            }
            outputMenu
        }
        .opacity(isSwitching ? 0.6 : 1.0)
        .disabled(isSwitching)
        .animation(.easeInOut(duration: 0.15), value: isSwitching)
    }

    // MARK: - Output Menu

    private var outputMenu: some View {
        Menu {
            Section("Display Outputs") {
                ForEach(outputs) { output in
                    Button {
                        Task { await selectOutput(output) }
                    } label: {
                        HStack {
                            Text(output.name)
                            if output.id == activeOutput?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            if let active = activeOutput, active.modes.count > 1 {
                Divider()
                Section("Display Modes") {
                    ForEach(active.modes, id: \.self) { mode in
                        Button {
                            Task { await selectMode(mode) }
                        } label: {
                            HStack {
                                Text(Self.modeTitle(mode, isNative: mode == active.modes.first))
                                if mode == currentMode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
            if model.isCompanionUpdateRequired(for: host) {
                Divider()
                Section("Diagnostics") {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            Self.companionUpdateCommand,
                            forType: .string
                        )
                    } label: {
                        Label(
                            "⚠️ Tower companion update required (v1 running, v2 needed for displays)",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: Self.iconName(for: currentOutput))
                    .font(.system(size: 11, weight: .medium))
                Text(Self.shortName(for: currentOutput))
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .glassEffect(.regular.interactive(), in: .capsule)
        .help("Host display output: \(currentOutput.name)")
        .accessibilityLabel("Display output")
        .accessibilityValue(currentOutput.name)
    }

    // MARK: - Mode Menu

    private func modeMenu(for output: HostOutput) -> some View {
        Menu {
            Section("Display Modes") {
                ForEach(output.modes, id: \.self) { mode in
                    Button {
                        Task { await selectMode(mode) }
                    } label: {
                        HStack {
                            Text(Self.modeTitle(mode, isNative: mode == output.modes.first))
                            if mode == currentMode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.horizonBlue)
                Text(currentMode?.label ?? output.modes.first?.label ?? "Mode")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .glassEffect(.regular.interactive(), in: .capsule)
        .help("Display resolution and refresh rate")
        .accessibilityLabel("Display mode")
        .accessibilityValue(currentMode?.label ?? "Default")
    }

    // MARK: - Actions & Reconnect

    private func selectOutput(_ output: HostOutput) async {
        guard !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }

        let wasStreaming = model.isStreaming
        let targetApp = model.lastLaunchAttempt?.app ?? model.deskTarget(of: host)

        if wasStreaming {
            await model.disconnect()
        }

        let targetMode = model.selectedHostMode[host.id]
        let validMode = output.modes.contains(where: {
            $0.width == targetMode?.width && $0.height == targetMode?.height
        })
            ? targetMode
            : (output.currentMode ?? output.modes.first)

        _ = await model.selectOutput(host: host, outputId: output.id, mode: validMode)

        if wasStreaming {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if let targetApp {
                model.requestStream(app: targetApp, on: host, resume: .anyApp)
            } else {
                model.openDesk(host)
            }
        }
    }

    private func selectMode(_ mode: DisplayMode) async {
        guard !isSwitching, let active = activeOutput else { return }
        isSwitching = true
        defer { isSwitching = false }

        let wasStreaming = model.isStreaming
        let targetApp = model.lastLaunchAttempt?.app ?? model.deskTarget(of: host)

        if wasStreaming {
            await model.disconnect()
        }

        _ = await model.selectOutput(host: host, outputId: active.id, mode: mode)

        if wasStreaming {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if let targetApp {
                model.requestStream(app: targetApp, on: host, resume: .anyApp)
            } else {
                model.openDesk(host)
            }
        }
    }

    // MARK: - Formatting Helpers

    nonisolated static func iconName(for output: HostOutput) -> String {
        if output.isVirtual {
            return "laptopcomputer"
        }
        let nameLower = output.name.lowercased()
        let connLower = output.connector.lowercased()
        if nameLower.contains("tv") || connLower.contains("tv") || output.connector.uppercased().hasPrefix("HDMI") {
            return "tv"
        }
        return "display"
    }

    nonisolated static func shortName(for output: HostOutput) -> String {
        if output.isVirtual {
            return "Virtual Screen"
        }
        let name = output.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.count > 20 {
            return String(name.prefix(18)) + "…"
        }
        return name.isEmpty ? output.connector : name
    }

    nonisolated static func modeTitle(_ mode: DisplayMode, isNative: Bool) -> String {
        if isNative {
            return "\(mode.label) · Native"
        }
        if mode.height == 1440 && mode.width == 2560 {
            return "\(mode.label) · 1440p"
        }
        if mode.height == 1080 && mode.width == 1920 {
            return "\(mode.label) · 1080p"
        }
        return mode.label
    }

    private static let companionUpdateCommand = (
        "cd ~/event-horizon/companion && "
        + "git pull origin feature/dynamic-host-output-selector && "
        + "cargo build --release && "
        + "cp target/release/event-horizon-companion ~/.local/bin/ && "
        + "systemctl --user restart event-horizon-companion.service"
    )
}
